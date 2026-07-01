//
//  MockSoundPrintProvider.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

import Foundation

struct MockSoundPrintProvider: SoundPrintProvider {
    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult {
        Self.analyzeSentiment(input: input)
    }

    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult {
        Self.extractTasteSignals(input: input)
    }

    func generatePersona(input: PersonaInput) async throws -> PersonaResult {
        Self.generatePersona(input: input)
    }

    func generateCompactSummary(input: CompactSummaryInput) async throws -> CompactSummaryResult {
        Self.generateCompactSummary(input: input)
    }

    static func analyzeSentiment(input: SentimentInput) -> SentimentResult {
        let words = Set(input.reviewText.normalizedSoundPrintWords)
        let positiveMatches = words.intersection(positiveKeywords).count
        let negativeMatches = words.intersection(negativeKeywords).count

        let keywordAdjustedScore = baseScore(for: input.rating)
            + (Double(positiveMatches) * 0.1)
            - (Double(negativeMatches) * 0.2)

        return SentimentResult(
            score: keywordAdjustedScore.clamped(to: -1.0...1.0),
            confidence: input.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 0.8
        )
    }

    static func baseScore(for rating: Double) -> Double {
        if rating >= 4.0 {
            return 0.7
        }

        if rating >= 3.0 {
            return 0.2
        }

        return -0.5
    }

    static func extractTasteSignals(input: TasteExtractionInput) -> TasteExtractionResult {
        let sentimentScore = input.sentimentScore ?? baseScore(for: input.rating)
        let avoidanceSignals = extractAvoidanceSignals(input: input)

        guard sentimentScore >= 0.0 else {
            return TasteExtractionResult(signals: [], avoidanceSignals: avoidanceSignals)
        }

        let searchableText = ([input.reviewText, input.standoutMoment ?? ""] + input.tags).joined(separator: " ")
        let normalizedText = searchableText.normalizedSoundPrintText
        let reviewSnippet = input.reviewText.trimmedForSoundPrint
        let fallbackSnippet = input.tags.isEmpty ? input.albumTitle : "Tags: \(input.tags.joined(separator: ", "))"
        let evidenceSnippet = reviewSnippet.isEmpty ? fallbackSnippet : reviewSnippet
        let hasReviewText = !input.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        var signals = tasteRules.compactMap { rule -> TasteSignal? in
            let matchCount = rule.keywords.filter { normalizedText.containsNormalizedSoundPrintPhrase($0) }.count

            guard matchCount > 0 else {
                return nil
            }

            let weight = (0.55 + (sentimentScore * 0.35) + (Double(matchCount - 1) * 0.05)).clamped(to: 0.0...1.0)
            let confidenceBase = hasReviewText ? 0.75 : 0.6
            let confidence = (confidenceBase + (Double(matchCount - 1) * 0.05)).clamped(to: 0.0...1.0)

            return TasteSignal(
                dimensionName: rule.dimensionName,
                label: rule.label,
                summary: "Leans into \(rule.label.lowercased()).",
                weight: weight,
                confidence: confidence,
                evidenceSnippet: evidenceSnippet,
                isPositiveEvidence: true
            )
        }

        applyFavoriteTrackEvidence(to: &signals, input: input, normalizedText: normalizedText, sentimentScore: sentimentScore)
        applyStandoutMomentEvidence(to: &signals, input: input)
        dampenThinPositiveEvidence(in: &signals, input: input)

        return TasteExtractionResult(signals: signals, avoidanceSignals: avoidanceSignals)
    }

    /// `favoriteTracks` is treated as positive evidence, primarily for replayability: naming
    /// specific tracks as favorites is itself a signal the album has real replay pull. When the
    /// review/tags independently agree (mentions "replay"/"repeat"/"addictive"), confidence gets
    /// a bonus rather than staying flat, per the agreement rule.
    private static func applyFavoriteTrackEvidence(
        to signals: inout [TasteSignal],
        input: TasteExtractionInput,
        normalizedText: String,
        sentimentScore: Double
    ) {
        guard !input.favoriteTracks.isEmpty else {
            return
        }

        let hasReplayAgreement = ["replay", "repeat", "addictive"]
            .contains { normalizedText.containsNormalizedSoundPrintPhrase($0) }
        let agreementBonus = (input.favoriteTracks.count >= 2 && hasReplayAgreement) ? 0.15 : 0.0
        let trackEvidence = "Favorite tracks: \(input.favoriteTracks.joined(separator: ", "))"

        if let index = signals.firstIndex(where: { $0.dimensionName == "replayability" }) {
            let existing = signals[index]
            signals[index] = TasteSignal(
                dimensionName: existing.dimensionName,
                label: existing.label,
                summary: existing.summary,
                weight: (existing.weight + 0.1 + agreementBonus).clamped(to: 0.0...1.0),
                confidence: (existing.confidence + 0.1 + agreementBonus).clamped(to: 0.0...1.0),
                evidenceSnippet: existing.evidenceSnippet,
                isPositiveEvidence: true
            )
        } else {
            signals.append(
                TasteSignal(
                    dimensionName: "replayability",
                    label: "Replay Pull",
                    summary: "Leans into replay pull.",
                    weight: (0.5 + (sentimentScore * 0.2) + agreementBonus).clamped(to: 0.0...1.0),
                    confidence: (0.55 + agreementBonus).clamped(to: 0.0...1.0),
                    evidenceSnippet: trackEvidence,
                    isPositiveEvidence: true
                )
            )
        }
    }

    /// `standoutMoment` is high-quality positive evidence: it already fed the keyword-matched
    /// dimensions above via the shared searchable text, so here it just gets a small confidence
    /// bump on whatever it helped produce, since a user calling out a specific moment is stronger
    /// signal than generic review language.
    private static func applyStandoutMomentEvidence(to signals: inout [TasteSignal], input: TasteExtractionInput) {
        guard let standoutMoment = input.standoutMoment, !standoutMoment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let normalizedStandout = standoutMoment.normalizedSoundPrintText

        for index in signals.indices {
            let matchesStandout = tasteRules
                .first { $0.dimensionName == signals[index].dimensionName }?
                .keywords
                .contains { normalizedStandout.containsNormalizedSoundPrintPhrase($0) } ?? false

            guard matchesStandout else {
                continue
            }

            let existing = signals[index]
            signals[index] = TasteSignal(
                dimensionName: existing.dimensionName,
                label: existing.label,
                summary: existing.summary,
                weight: (existing.weight + 0.05).clamped(to: 0.0...1.0),
                confidence: (existing.confidence + 0.1).clamped(to: 0.0...1.0),
                evidenceSnippet: standoutMoment.trimmedForSoundPrint,
                isPositiveEvidence: true
            )
        }
    }

    /// Conflict dampening: a low rating with exactly one favorite track shouldn't be generalized
    /// into a broad positive taste claim — cap that scoped signal's weight/confidence low instead
    /// of letting it seed a high-weight dimension.
    private static func dampenThinPositiveEvidence(in signals: inout [TasteSignal], input: TasteExtractionInput) {
        guard input.rating < 3.0, input.favoriteTracks.count == 1 else {
            return
        }

        for index in signals.indices where signals[index].dimensionName == "replayability" {
            let existing = signals[index]
            signals[index] = TasteSignal(
                dimensionName: existing.dimensionName,
                label: existing.label,
                summary: existing.summary,
                weight: min(existing.weight, 0.3),
                confidence: min(existing.confidence, 0.35),
                evidenceSnippet: existing.evidenceSnippet,
                isPositiveEvidence: true
            )
        }
    }

    /// `skipTracks` is avoidance/tracklist-consistency evidence, not a blanket negative on the
    /// album — it coexists with whatever positive dimensions the log otherwise produced.
    static func extractAvoidanceSignals(input: TasteExtractionInput) -> [AvoidanceSignal] {
        let searchableText = ([input.reviewText] + input.tags).joined(separator: " ")
        let normalizedText = searchableText.normalizedSoundPrintText
        let hasReviewText = !input.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let confidenceBase = hasReviewText ? 0.6 : 0.45
        let reviewSnippet = input.reviewText.trimmedForSoundPrint
        let fallbackSnippet = input.tags.isEmpty ? input.albumTitle : "Tags: \(input.tags.joined(separator: ", "))"
        let evidenceSnippet = reviewSnippet.isEmpty ? fallbackSnippet : reviewSnippet

        var signals: [AvoidanceSignal] = avoidanceRules.compactMap { rule -> AvoidanceSignal? in
            let matchCount = rule.keywords.filter { normalizedText.containsNormalizedSoundPrintPhrase($0) }.count

            guard matchCount > 0 else {
                return nil
            }

            let strength = (0.5 + (Double(matchCount - 1) * 0.1)).clamped(to: 0.0...1.0)
            let confidence = (confidenceBase + (Double(matchCount - 1) * 0.05)).clamped(to: 0.0...1.0)

            return AvoidanceSignal(
                signalName: rule.signalName,
                label: rule.label,
                summary: "Loses patience with \(rule.label.lowercased()).",
                strength: strength,
                confidence: confidence,
                evidenceSnippet: evidenceSnippet
            )
        }

        let skipCount = input.skipTracks.count
        let hasSkipKeywordMatch = skipHeavyKeywords.contains { normalizedText.containsNormalizedSoundPrintPhrase($0) }

        guard skipCount >= 2 || hasSkipKeywordMatch else {
            return signals
        }

        // Agreement: track selections plus matching language make this a stronger signal
        // than either alone.
        let agreementBonus = (skipCount >= 2 && hasSkipKeywordMatch) ? 0.15 : 0.0
        var strength = (0.45 + (Double(min(skipCount, 4)) * 0.08) + agreementBonus).clamped(to: 0.0...1.0)
        var confidence = (confidenceBase + agreementBonus).clamped(to: 0.0...1.0)

        // Conflict dampening: a high rating alongside skip tracks reads as a tracklist-patience
        // quirk, not a strong overall dislike, so keep this modest rather than suppressing it.
        if input.rating >= 4.0 {
            strength = min(strength, 0.4)
            confidence = min(confidence, 0.45)
        }

        let skipSnippet = skipCount > 0 ? "Skipped: \(input.skipTracks.joined(separator: ", "))" : evidenceSnippet

        signals.append(
            AvoidanceSignal(
                signalName: "skipHeavyAlbums",
                label: "Skip-Heavy Albums",
                summary: "Tends to skip through parts of albums like this.",
                strength: strength,
                confidence: confidence,
                evidenceSnippet: skipSnippet
            )
        )

        return signals
    }

    // TODO(task 7): replace with real deterministic headline/summary/bullet generation.
    static func generateCompactSummary(input: CompactSummaryInput) -> CompactSummaryResult {
        let topDimension = input.dimensions.sorted { $0.weight > $1.weight }.first
        let headline = topDimension.map { "\($0.label) Leads" } ?? "Still Building Your Profile"
        let summary = topDimension.map { "You tend to reward \($0.label.lowercased())." }
            ?? "Log a few more albums to surface a pattern."

        return CompactSummaryResult(headline: headline, summary: summary, bullets: [])
    }

    static func generatePersona(input: PersonaInput) -> PersonaResult {
        let strongestDimensions = input.dimensions
            .sorted {
                if $0.weight == $1.weight {
                    return $0.label < $1.label
                }

                return $0.weight > $1.weight
            }
        let positiveLogs = input.recentLogs.filter(\.isPositiveSignal)
        let favoriteLog = positiveLogs
            .sorted {
                if $0.rating == $1.rating {
                    return $0.albumTitle < $1.albumTitle
                }

                return $0.rating > $1.rating
            }
            .first

        let primaryDimension = strongestDimensions.first?.label
        let secondaryDimension = strongestDimensions.dropFirst().first?.label
        let primaryTag = input.topTags.first
        let reviewCue = positiveLogs
            .map(\.reviewSnippet)
            .first { !$0.isEmpty }?
            .firstSoundPrintPhrase
        let averageRatingText = input.averageRating.map {
            $0.formatted(.number.precision(.fractionLength(1)))
        } ?? "unrated"

        let draft = buildPersonaDraft(
            totalLogCount: input.totalLogCount,
            primaryDimension: primaryDimension,
            secondaryDimension: secondaryDimension,
            primaryTag: primaryTag,
            favoriteLog: favoriteLog,
            reviewCue: reviewCue,
            averageRatingText: averageRatingText
        )
        let concreteSignals = concreteSignals(
            dimensions: strongestDimensions,
            topTags: input.topTags,
            logs: input.recentLogs
        )

        if isValidPersona(draft, concreteSignals: concreteSignals) {
            return PersonaResult(text: draft)
        }

        return PersonaResult(
            text: fallbackPersona(
                totalLogCount: input.totalLogCount,
                primaryDimension: primaryDimension,
                primaryTag: primaryTag,
                favoriteLog: favoriteLog,
                averageRatingText: averageRatingText
            )
        )
    }

    private static func buildPersonaDraft(
        totalLogCount: Int,
        primaryDimension: String?,
        secondaryDimension: String?,
        primaryTag: String?,
        favoriteLog: PersonaLogInput?,
        reviewCue: String?,
        averageRatingText: String
    ) -> String {
        let dimensionText = joinedSignals([primaryDimension, secondaryDimension])
        let tagText = primaryTag.map { "especially when the notes drift toward \($0)" } ?? "when the record has a clear point of view"
        let albumText = favoriteLog.map { "\($0.albumTitle) by \($0.artistName)" } ?? "your highest-rated albums"
        let cueText = reviewCue.map { "Your own notes keep circling `\($0)`, which is the receipt, not a horoscope." } ?? "The ratings are doing the talking here, which is refreshingly hard to fake."

        if let dimensionText {
            return "Across \(totalLogCount) logs, your ear keeps rewarding \(dimensionText), \(tagText). \(albumText) looks like the current north star, and your \(averageRatingText) average says you are picky without being joyless. \(cueText)"
        }

        return "Across \(totalLogCount) logs, your ratings keep favoring \(albumText), \(tagText). Your \(averageRatingText) average says you are picky without being joyless. \(cueText)"
    }

    private static func fallbackPersona(
        totalLogCount: Int,
        primaryDimension: String?,
        primaryTag: String?,
        favoriteLog: PersonaLogInput?,
        averageRatingText: String
    ) -> String {
        let signal = primaryDimension ?? primaryTag ?? favoriteLog?.albumTitle ?? "your strongest logs"
        let albumText = favoriteLog.map { "\($0.albumTitle) by \($0.artistName)" } ?? "the albums you rate highest"

        return "Across \(totalLogCount) logs, your taste is currently anchored by \(signal) and by records like \(albumText). With a \(averageRatingText) average, you seem more interested in albums with a spine than pleasant background wallpaper."
    }

    static func isValidPersona(_ text: String, concreteSignals: [String]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 80 else {
            return false
        }

        let normalizedText = trimmed.normalizedSoundPrintText

        guard !bannedPersonaPhrases.contains(where: { normalizedText.contains($0) }) else {
            return false
        }

        return concreteSignals.contains { signal in
            let normalizedSignal = signal.normalizedSoundPrintText.trimmingCharacters(in: .whitespacesAndNewlines)
            return !normalizedSignal.isEmpty && normalizedText.contains(normalizedSignal)
        }
    }

    private static func concreteSignals(
        dimensions: [TasteDimension],
        topTags: [String],
        logs: [PersonaLogInput]
    ) -> [String] {
        let dimensionLabels = dimensions.map(\.label)
        let albumTitles = logs.map(\.albumTitle)
        let artists = logs.map(\.artistName)
        let reviewSnippets = logs.compactMap(\.reviewSnippet.firstSoundPrintPhrase)

        return dimensionLabels + topTags + albumTitles + artists + reviewSnippets
    }

    private static func joinedSignals(_ signals: [String?]) -> String? {
        let values = signals.compactMap { $0 }.filter { !$0.isEmpty }

        if values.isEmpty {
            return nil
        }

        if values.count == 1 {
            return values[0].lowercased()
        }

        return values.prefix(2).map { $0.lowercased() }.joined(separator: " and ")
    }

    private static let positiveKeywords: Set<String> = [
        "love",
        "loved",
        "great",
        "favorite",
        "beautiful",
        "amazing",
        "replay",
        "catchy",
        "incredible"
    ]

    private static let negativeKeywords: Set<String> = [
        "hate",
        "hated",
        "boring",
        "overrated",
        "bad",
        "weak",
        "annoying",
        "forgettable",
        "disappointing"
    ]

    private static let bannedPersonaPhrases = [
        "eclectic taste",
        "wide range of genres",
        "something for everyone",
        "diverse taste",
        "varied taste"
    ]

    private static let tasteRules: [TasteRule] = [
        TasteRule(dimensionName: "mood", label: "Emotional Temperature", keywords: ["dark", "sad", "moody", "melancholic"]),
        TasteRule(dimensionName: "energy", label: "Energy Bias", keywords: ["energetic", "intense", "aggressive"]),
        TasteRule(dimensionName: "productionStyle", label: "Production Taste", keywords: ["polished", "glossy", "clean", "raw", "rough", "lo-fi"]),
        TasteRule(dimensionName: "vocalFocus", label: "Vocal Gravity", keywords: ["vocals", "voice", "singer"]),
        TasteRule(dimensionName: "lyricFocus", label: "Lyric Attention", keywords: ["lyrics", "writing", "storytelling"]),
        TasteRule(dimensionName: "experimentation", label: "Experimental Tolerance", keywords: ["weird", "experimental", "unpredictable"]),
        TasteRule(dimensionName: "instrumentalRichness", label: "Arrangement Depth", keywords: ["dense", "layered", "lush"]),
        TasteRule(dimensionName: "genreOpenness", label: "Genre Flex", keywords: ["genre-bending", "fusion"]),
        TasteRule(dimensionName: "eraAffinity", label: "Era Pull", keywords: ["classic", "old-school", "90s", "2000s"]),
        TasteRule(dimensionName: "replayability", label: "Replay Pull", keywords: ["replay", "repeat", "addictive"]),
        TasteRule(dimensionName: "tracklistConsistency", label: "Tracklist Patience", keywords: ["consistent", "cohesive", "no filler", "tight tracklist"]),
        TasteRule(dimensionName: "emotionalDirectness", label: "Emotional Directness", keywords: ["raw emotion", "direct", "honest", "vulnerable"]),
        TasteRule(dimensionName: "texturePreference", label: "Texture Bias", keywords: ["textured", "grainy", "atmospheric", "warm tone"])
    ]

    private static let avoidanceRules: [AvoidanceRule] = [
        AvoidanceRule(signalName: "fillerSensitivity", label: "Filler Sensitivity", keywords: ["filler", "padded", "too long", "drags"]),
        AvoidanceRule(signalName: "sterileProduction", label: "Sterile Production", keywords: ["sterile", "overproduced", "lifeless", "clinical"]),
        AvoidanceRule(signalName: "weakWriting", label: "Weak Writing", keywords: ["weak lyrics", "lazy writing", "cliche", "generic lyrics"]),
        AvoidanceRule(signalName: "lowReplayValue", label: "Low Replay Value", keywords: ["one listen", "wont replay", "forgettable", "skip after"]),
        AvoidanceRule(signalName: "energyWithoutPayoff", label: "Energy Without Payoff", keywords: ["all buildup", "no payoff", "goes nowhere", "never arrives"]),
        AvoidanceRule(signalName: "moodMismatch", label: "Mood Mismatch", keywords: ["wrong mood", "tonally off", "mismatched"])
    ]

    private static let skipHeavyKeywords: [String] = [
        "filler", "pacing", "bloated", "too long", "weak middle", "inconsistent", "uneven", "front-loaded", "skip"
    ]
}

private struct AvoidanceRule {
    let signalName: String
    let label: String
    let keywords: [String]
}

private struct TasteRule {
    let dimensionName: String
    let label: String
    let keywords: [String]
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
