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

        guard sentimentScore >= 0.0 else {
            return TasteExtractionResult(signals: [])
        }

        let searchableText = ([input.reviewText] + input.tags).joined(separator: " ")
        let normalizedText = searchableText.normalizedSoundPrintText
        let reviewSnippet = input.reviewText.trimmedForSoundPrint
        let fallbackSnippet = input.tags.isEmpty ? input.albumTitle : "Tags: \(input.tags.joined(separator: ", "))"
        let evidenceSnippet = reviewSnippet.isEmpty ? fallbackSnippet : reviewSnippet

        let signals = tasteRules.compactMap { rule -> TasteSignal? in
            let matchCount = rule.keywords.filter { normalizedText.containsNormalizedSoundPrintPhrase($0) }.count

            guard matchCount > 0 else {
                return nil
            }

            let weight = (0.55 + (sentimentScore * 0.35) + (Double(matchCount - 1) * 0.05)).clamped(to: 0.0...1.0)
            let confidenceBase = input.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 0.75
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

        return TasteExtractionResult(signals: signals)
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
        TasteRule(dimensionName: "mood", label: "Mood", keywords: ["dark", "sad", "moody", "melancholic"]),
        TasteRule(dimensionName: "energy", label: "Energy", keywords: ["energetic", "intense", "aggressive"]),
        TasteRule(dimensionName: "productionStyle", label: "Production Style", keywords: ["polished", "glossy", "clean", "raw", "rough", "lo-fi"]),
        TasteRule(dimensionName: "vocalFocus", label: "Vocal Focus", keywords: ["vocals", "voice", "singer"]),
        TasteRule(dimensionName: "lyricFocus", label: "Lyric Focus", keywords: ["lyrics", "writing", "storytelling"]),
        TasteRule(dimensionName: "experimentation", label: "Experimentation", keywords: ["weird", "experimental", "unpredictable"]),
        TasteRule(dimensionName: "instrumentalRichness", label: "Instrumental Richness", keywords: ["dense", "layered", "lush"]),
        TasteRule(dimensionName: "genreOpenness", label: "Genre Openness", keywords: ["genre-bending", "fusion"]),
        TasteRule(dimensionName: "eraAffinity", label: "Era Affinity", keywords: ["classic", "old-school", "90s", "2000s"]),
        TasteRule(dimensionName: "replayability", label: "Replayability", keywords: ["replay", "repeat", "addictive"])
    ]
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

private extension String {
    var trimmedForSoundPrint: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count > 96 else {
            return trimmed
        }

        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 96)
        return String(trimmed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    var normalizedSoundPrintText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
    }

    var normalizedSoundPrintWords: [String] {
        normalizedSoundPrintText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func containsNormalizedSoundPrintPhrase(_ phrase: String) -> Bool {
        let normalizedPhrase = phrase.normalizedSoundPrintText
        return contains(normalizedPhrase)
    }

    var firstSoundPrintPhrase: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        let separators = CharacterSet(charactersIn: ".!?")
        let firstSentence = trimmed
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? trimmed

        guard firstSentence.count > 64 else {
            return firstSentence
        }

        let endIndex = firstSentence.index(firstSentence.startIndex, offsetBy: 64)
        return String(firstSentence[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
