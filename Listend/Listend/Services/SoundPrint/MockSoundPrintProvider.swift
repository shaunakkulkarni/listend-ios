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
}
