//
//  FoundationModelsSoundPrintProvider.swift
//  Listend
//
//  Created by Codex on 5/3/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum FoundationModelsSoundPrintProviderError: Error, Equatable {
    case unavailable
    case emptyOutput
    case malformedOutput
    case validationFailed
}

struct FoundationModelsSoundPrintProvider: SoundPrintProvider {
    init() {}

    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let content = try await Self.generatedContent(
                instructions: """
                You analyze album log sentiment for Listend. Return only compact JSON.
                Do not include markdown, prose, or extra keys.
                """,
                prompt: """
                Rate this listener log sentiment.
                JSON schema: {"score": Double from -1.0 to 1.0, "confidence": Double from 0.0 to 1.0}
                Rating: \(input.rating)
                Review: \(input.reviewText)
                Tags: \(input.tags.joined(separator: ", "))
                """
            )
            let payload = try Self.decodedJSON(SentimentPayload.self, from: content)
            return FoundationModelsSoundPrintValidator.validatedSentiment(
                score: payload.score,
                confidence: payload.confidence
            )
        }
        #endif

        throw FoundationModelsSoundPrintProviderError.unavailable
    }

    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let allowedDimensionNames = FoundationModelsSoundPrintValidator.allowedDimensionNames.joined(separator: ", ")
            let genreName = input.genreName ?? ""
            let releaseYear = input.releaseYear.map { String($0) } ?? ""
            let sentimentScore = input.sentimentScore.map { String($0) } ?? ""
            let tags = input.tags.joined(separator: ", ")
            let prompt = """
            Extract positive taste signals from this album log.
            Allowed dimensionName values: \(allowedDimensionNames)
            JSON schema: {"signals":[{"dimensionName": String, "summary": String, "weight": Double 0.0-1.0, "confidence": Double 0.0-1.0, "evidenceSnippet": String}]}
            If sentiment is negative, return {"signals":[]}.
            Album: \(input.albumTitle)
            Artist: \(input.artistName)
            Genre: \(genreName)
            Release year: \(releaseYear)
            Rating: \(input.rating)
            Sentiment score: \(sentimentScore)
            Review: \(input.reviewText)
            Tags: \(tags)
            """
            let content = try await Self.generatedContent(
                instructions: """
                You extract concrete taste signals from album logs for Listend. Return only compact JSON.
                Only use allowed dimensionName values exactly as given. Do not invent dimensions.
                """,
                prompt: prompt
            )
            let payload = try Self.decodedJSON(TastePayload.self, from: content)
            return try FoundationModelsSoundPrintValidator.validatedTasteExtraction(
                payloadSignals: payload.signals,
                input: input
            )
        }
        #endif

        throw FoundationModelsSoundPrintProviderError.unavailable
    }

    func generatePersona(input: PersonaInput) async throws -> PersonaResult {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let averageRating = input.averageRating.map { String($0) } ?? ""
            let dimensions = input.dimensions
                .map { dimension in "\(dimension.label)=\(dimension.weight)" }
                .joined(separator: "; ")
            let topTags = input.topTags.joined(separator: ", ")
            let recentLogs = input.recentLogs
                .map { log in
                    let tags = log.tags.joined(separator: "/")
                    return "\(log.albumTitle) by \(log.artistName), rating \(log.rating), tags \(tags), note \(log.reviewSnippet)"
                }
                .joined(separator: " | ")
            let prompt = """
            Write a listener persona.
            JSON schema: {"text": String}
            Requirements: 80-360 characters; specific; no generic phrases like eclectic taste or wide range of genres.
            Total logs: \(input.totalLogCount)
            Average rating: \(averageRating)
            Dimensions: \(dimensions)
            Top tags: \(topTags)
            Recent logs: \(recentLogs)
            """
            let content = try await Self.generatedContent(
                instructions: """
                You write concise, specific music taste persona text for Listend. Return only compact JSON.
                Ground every claim in the provided dimensions, tags, albums, artists, or review snippets.
                """,
                prompt: prompt
            )
            let payload = try Self.decodedJSON(PersonaPayload.self, from: content)
            return try FoundationModelsSoundPrintValidator.validatedPersona(
                text: payload.text,
                input: input
            )
        }
        #endif

        throw FoundationModelsSoundPrintProviderError.unavailable
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private extension FoundationModelsSoundPrintProvider {
    static func generatedContent(instructions: String, prompt: String) async throws -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        default:
            throw FoundationModelsSoundPrintProviderError.unavailable
        }

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        let content = String(describing: response.content).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            throw FoundationModelsSoundPrintProviderError.emptyOutput
        }

        return content
    }
}
#endif

private extension FoundationModelsSoundPrintProvider {
    static func decodedJSON<T: Decodable>(_ type: T.Type, from content: String) throws -> T {
        guard let data = content.soundPrintJSONData else {
            throw FoundationModelsSoundPrintProviderError.malformedOutput
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw FoundationModelsSoundPrintProviderError.malformedOutput
        }
    }
}

struct FoundationModelsSoundPrintValidator {
    static let allowedDimensions: [String: String] = [
        "mood": "Mood",
        "energy": "Energy",
        "productionStyle": "Production Style",
        "vocalFocus": "Vocal Focus",
        "lyricFocus": "Lyric Focus",
        "experimentation": "Experimentation",
        "instrumentalRichness": "Instrumental Richness",
        "genreOpenness": "Genre Openness",
        "eraAffinity": "Era Affinity",
        "replayability": "Replayability"
    ]

    static var allowedDimensionNames: [String] {
        allowedDimensions.keys.sorted()
    }

    static func validatedSentiment(score: Double, confidence: Double) -> SentimentResult {
        SentimentResult(
            score: score.clamped(to: -1.0...1.0),
            confidence: confidence.clamped(to: 0.0...1.0)
        )
    }

    static func validatedTasteExtraction(
        payloadSignals: [FoundationModelsTasteSignalPayload],
        input: TasteExtractionInput
    ) throws -> TasteExtractionResult {
        let sentimentScore = input.sentimentScore ?? MockSoundPrintProvider.baseScore(for: input.rating)

        guard sentimentScore >= 0.0 else {
            return TasteExtractionResult(signals: [])
        }

        guard !payloadSignals.isEmpty else {
            throw FoundationModelsSoundPrintProviderError.emptyOutput
        }

        var seenDimensionNames: Set<String> = []
        var signals: [TasteSignal] = []

        for payload in payloadSignals {
            let dimensionName = payload.dimensionName.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let label = allowedDimensions[dimensionName], !seenDimensionNames.contains(dimensionName) else {
                throw FoundationModelsSoundPrintProviderError.validationFailed
            }

            let summary = payload.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidenceSnippet = payload.evidenceSnippet.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !summary.isEmpty, !evidenceSnippet.isEmpty else {
                throw FoundationModelsSoundPrintProviderError.validationFailed
            }

            seenDimensionNames.insert(dimensionName)
            signals.append(
                TasteSignal(
                    dimensionName: dimensionName,
                    label: label,
                    summary: summary,
                    weight: payload.weight.clamped(to: 0.0...1.0),
                    confidence: payload.confidence.clamped(to: 0.0...1.0),
                    evidenceSnippet: evidenceSnippet,
                    isPositiveEvidence: true
                )
            )
        }

        return TasteExtractionResult(signals: signals)
    }

    static func validatedPersona(text: String, input: PersonaInput) throws -> PersonaResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let concreteSignals = concreteSignals(from: input)

        guard MockSoundPrintProvider.isValidPersona(trimmed, concreteSignals: concreteSignals) else {
            throw FoundationModelsSoundPrintProviderError.validationFailed
        }

        return PersonaResult(text: trimmed)
    }

    private static func concreteSignals(from input: PersonaInput) -> [String] {
        input.dimensions.map(\.label)
            + input.topTags
            + input.recentLogs.map(\.albumTitle)
            + input.recentLogs.map(\.artistName)
            + input.recentLogs.map(\.reviewSnippet)
    }
}

private struct SentimentPayload: Decodable {
    let score: Double
    let confidence: Double
}

struct FoundationModelsTasteSignalPayload: Decodable {
    let dimensionName: String
    let summary: String
    let weight: Double
    let confidence: Double
    let evidenceSnippet: String
}

private struct TastePayload: Decodable {
    let signals: [FoundationModelsTasteSignalPayload]
}

private struct PersonaPayload: Decodable {
    let text: String
}

private extension String {
    var soundPrintJSONData: Data? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = trimmed.data(using: .utf8), isLikelyJSONObject(trimmed) {
            return data
        }

        guard
            let startIndex = trimmed.firstIndex(of: "{"),
            let endIndex = trimmed.lastIndex(of: "}"),
            startIndex <= endIndex
        else {
            return nil
        }

        return String(trimmed[startIndex...endIndex]).data(using: .utf8)
    }

    private func isLikelyJSONObject(_ value: String) -> Bool {
        value.first == "{" && value.last == "}"
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
