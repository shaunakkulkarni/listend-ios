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

    static func generateCompactSummary(input: CompactSummaryInput) -> CompactSummaryResult {
        let sortedDimensions = input.dimensions.sorted { $0.weight > $1.weight }
        let sortedAvoidance = input.avoidanceSignals.sorted { $0.strength > $1.strength }

        let result = CompactSummaryResult(
            headline: compactSummaryHeadline(topDimension: sortedDimensions.first),
            summary: compactSummarySentence(topDimension: sortedDimensions.first, topAvoidance: sortedAvoidance.first),
            bullets: compactSummaryBullets(dimensions: sortedDimensions, avoidanceSignals: sortedAvoidance)
        )

        guard SoundPrintOutputValidator.validateCompactSummary(
            headline: result.headline,
            summary: result.summary,
            bullets: result.bullets
        ).isValid else {
            return fallbackCompactSummary()
        }

        return result
    }

    private static func compactSummaryHeadline(topDimension: TasteDimension?) -> String {
        guard let topDimension else {
            return "Still Building The Pattern"
        }

        return "\(topDimension.label) Leads The Pattern"
    }

    private static func compactSummarySentence(topDimension: TasteDimension?, topAvoidance: TasteAvoidanceSignal?) -> String {
        guard let topDimension else {
            return "Log a few more albums to start seeing a pattern here."
        }

        guard let topAvoidance else {
            return "You tend to reward \(topDimension.label.lowercased())."
        }

        return "You tend to reward \(topDimension.label.lowercased()) and lose patience with \(topAvoidance.label.lowercased())."
    }

    private static func compactSummaryBullets(dimensions: [TasteDimension], avoidanceSignals: [TasteAvoidanceSignal]) -> [String] {
        var bullets: [String] = []

        for dimension in dimensions.prefix(2) {
            bullets.append("Rewards \(dimension.label)")
        }

        if let topAvoidance = avoidanceSignals.first {
            bullets.append("Loses patience with \(topAvoidance.label)")
        } else if let thirdDimension = dimensions.dropFirst(2).first {
            bullets.append("Also leans into \(thirdDimension.label)")
        }

        let modestFillers = ["Still gathering evidence", "More logs will sharpen this", "Pattern still forming"]
        var fillerIndex = 0
        while bullets.count < 3, fillerIndex < modestFillers.count {
            bullets.append(modestFillers[fillerIndex])
            fillerIndex += 1
        }

        return Array(bullets.prefix(3))
    }

    private static func fallbackCompactSummary() -> CompactSummaryResult {
        CompactSummaryResult(
            headline: "Still Building The Pattern",
            summary: "Log a few more albums to start seeing a pattern here.",
            bullets: ["Still gathering evidence", "More logs will sharpen this", "Pattern still forming"]
        )
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
        let topAvoidanceLabel = input.avoidanceSignals.first

        let draft = buildPersonaDraft(
            primaryDimension: primaryDimension,
            secondaryDimension: secondaryDimension,
            topAvoidanceLabel: topAvoidanceLabel,
            favoriteLog: favoriteLog
        )
        let concreteSignals = concreteSignals(
            dimensions: strongestDimensions,
            topTags: input.topTags,
            logs: input.recentLogs
        ) + input.avoidanceSignals

        if SoundPrintOutputValidator.isPersonaValid(draft, concreteSignals: concreteSignals, logCount: input.totalLogCount) {
            return PersonaResult(text: draft, generationSource: .localFallback)
        }

        return PersonaResult(
            text: fallbackPersona(primaryDimension: primaryDimension, favoriteLog: favoriteLog),
            generationSource: .localFallback
        )
    }

    /// Two sentences, at most 55 words: the first states what's rewarded (preferred phrasing
    /// per the tone spec), the second grounds it in either an avoidance signal (what's rejected)
    /// or the strongest available track-level/album evidence — never both, to stay within budget.
    private static func buildPersonaDraft(
        primaryDimension: String?,
        secondaryDimension: String?,
        topAvoidanceLabel: String?,
        favoriteLog: PersonaLogInput?
    ) -> String {
        "\(personaRewardClause(primaryDimension: primaryDimension, secondaryDimension: secondaryDimension)) \(personaEvidenceClause(topAvoidanceLabel: topAvoidanceLabel, favoriteLog: favoriteLog))"
    }

    private static func personaRewardClause(primaryDimension: String?, secondaryDimension: String?) -> String {
        guard let primaryDimension else {
            return "Your logs point toward records with real staying power."
        }

        if let secondaryDimension {
            return "You tend to reward \(primaryDimension.lowercased()) and \(secondaryDimension.lowercased())."
        }

        return "You tend to reward \(primaryDimension.lowercased())."
    }

    private static func personaEvidenceClause(topAvoidanceLabel: String?, favoriteLog: PersonaLogInput?) -> String {
        if let topAvoidanceLabel {
            return "You lose patience with \(topAvoidanceLabel.lowercased())."
        }

        guard let favoriteLog else {
            return "The pattern so far is still taking shape."
        }

        if favoriteLog.hasStandoutMoment {
            return "The moment you flagged in \(favoriteLog.albumTitle) says it best."
        }

        if let favoriteTrack = favoriteLog.favoriteTracks.first {
            return "\"\(favoriteTrack)\" off \(favoriteLog.albumTitle) is the clearest example so far."
        }

        return "\(favoriteLog.albumTitle) by \(favoriteLog.artistName) is the clearest example so far."
    }

    private static func fallbackPersona(primaryDimension: String?, favoriteLog: PersonaLogInput?) -> String {
        guard let primaryDimension else {
            let albumText = favoriteLog.map { "\($0.albumTitle) is the clearest example so far." } ?? "The ratings alone are doing the talking so far."
            return "Your logs point toward records with real staying power. \(albumText)"
        }

        return "Your logs point toward \(primaryDimension.lowercased()). That pattern is the clearest signal so far."
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
