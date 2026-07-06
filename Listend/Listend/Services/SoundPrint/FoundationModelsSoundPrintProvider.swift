//
//  FoundationModelsSoundPrintProvider.swift
//  Listend
//
//  Created by Codex on 5/3/26.
//

import Foundation
import os

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
    private static let logger = Logger(subsystem: "com.shaunakkulkarni.Listend", category: "SoundPrint")

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
            let content = try await Self.generatedContent(
                instructions: SoundPrintPromptTemplates.tasteExtractionInstructions(),
                prompt: SoundPrintPromptTemplates.tasteExtractionPrompt(
                    albumTitle: input.albumTitle,
                    artistName: input.artistName,
                    releaseYear: input.releaseYear,
                    genreName: input.genreName,
                    rating: input.rating,
                    reviewText: input.reviewText,
                    tags: input.tags,
                    favoriteTracks: input.favoriteTracks,
                    skipTracks: input.skipTracks,
                    standoutMoment: input.standoutMoment,
                    existingDimensions: input.existingDimensions
                )
            )
            let payload = try Self.decodedJSON(TasteExtractionPayload.self, from: content)
            return try FoundationModelsSoundPrintValidator.validatedTasteExtraction(payload: payload, input: input)
        }
        #endif

        throw FoundationModelsSoundPrintProviderError.unavailable
    }

    func generatePersona(input: PersonaInput) async throws -> PersonaResult {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await Self.generatePersonaViaFoundationModels(input: input)
        }
        #endif

        throw FoundationModelsSoundPrintProviderError.unavailable
    }

    func generateCompactSummary(input: CompactSummaryInput) async throws -> CompactSummaryResult {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let topTasteDimensions = input.dimensions.sorted { $0.weight > $1.weight }.map(\.label)
            let avoidanceLabels = input.avoidanceSignals.sorted { $0.strength > $1.strength }.map(\.label)
            let content = try await Self.generatedContent(
                instructions: SoundPrintPromptTemplates.compactSummaryInstructions(),
                prompt: SoundPrintPromptTemplates.compactSummaryPrompt(
                    topTasteDimensions: topTasteDimensions,
                    avoidanceSignals: avoidanceLabels,
                    recentChanges: input.recentChanges
                )
            )
            let payload = try Self.decodedJSON(CompactSummaryPayload.self, from: content)
            let outcome = SoundPrintOutputValidator.validateCompactSummary(
                headline: payload.headline,
                summary: payload.summary,
                bullets: payload.bullets
            )

            guard outcome.isValid else {
                throw FoundationModelsSoundPrintProviderError.validationFailed
            }

            return CompactSummaryResult(headline: payload.headline, summary: payload.summary, bullets: payload.bullets)
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

        let content = try await generatedResponseContent(instructions: instructions, prompt: prompt)

        guard !content.isEmpty else {
            throw FoundationModelsSoundPrintProviderError.emptyOutput
        }

        return content
    }

    static func generatedResponseContent(instructions: String, prompt: String) async throws -> String {
        var lastError: Error?

        for attempt in 1...2 {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                return String(describing: response.content).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt == 1 else {
                    break
                }

                FoundationModelsSoundPrintProvider.logger.error("FoundationModels response failed; retrying once: \(String(describing: error), privacy: .public)")
                try await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        throw lastError ?? FoundationModelsSoundPrintProviderError.unavailable
    }

    /// Orchestrates persona generation: draft via FM, gate through the always-on local
    /// validator, then optionally ask the critic prompt for a second opinion. The critic pass
    /// is best-effort — if it errors, times out, or produces an unusable rewrite, the pipeline
    /// still resolves to a valid persona (the already-valid draft, or the deterministic
    /// Mock fallback) rather than surfacing an error.
    static func generatePersonaViaFoundationModels(input: PersonaInput) async throws -> PersonaResult {
        let concreteSignals = FoundationModelsSoundPrintValidator.concreteSignals(from: input) + input.avoidanceSignals
        let context = SoundPrintOutputValidator.PersonaValidationContext(
            concreteSignals: concreteSignals,
            logCount: input.totalLogCount
        )

        let draftText = try await requestPersonaText(input: input)

        let draftOutcome = SoundPrintOutputValidator.validatePersona(draftText, context: context)
        if !draftOutcome.isValid {
            FoundationModelsSoundPrintProvider.logger.error("FoundationModels persona rejected; trying critic rewrite: \(String(describing: draftOutcome), privacy: .public)")
            if let rewrite = await validCriticRewrite(for: draftText, input: input, context: context) {
                return PersonaResult(text: rewrite, generationSource: .foundationModels)
            }

            FoundationModelsSoundPrintProvider.logger.error("FoundationModels critic could not repair persona; using local fallback")
            return MockSoundPrintProvider.generatePersona(input: input)
        }

        guard let critique = await critiquePersona(draftText, input: input) else {
            return PersonaResult(text: draftText, generationSource: .foundationModels)
        }

        if critique.passes {
            return PersonaResult(text: draftText, generationSource: .foundationModels)
        }

        if let rewrite = critique.suggestedRewrite?.trimmingCharacters(in: .whitespacesAndNewlines), !rewrite.isEmpty,
           SoundPrintOutputValidator.validatePersona(rewrite, context: context).isValid {
            return PersonaResult(text: rewrite, generationSource: .foundationModels)
        }

        FoundationModelsSoundPrintProvider.logger.error("FoundationModels persona critic rejected output; using local fallback. suggestedRewrite: \(String(describing: critique.suggestedRewrite), privacy: .public)")
        return MockSoundPrintProvider.generatePersona(input: input)
    }

    static func validCriticRewrite(
        for personaText: String,
        input: PersonaInput,
        context: SoundPrintOutputValidator.PersonaValidationContext
    ) async -> String? {
        guard let critique = await critiquePersona(personaText, input: input),
              let rewrite = critique.suggestedRewrite?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rewrite.isEmpty,
              SoundPrintOutputValidator.validatePersona(rewrite, context: context).isValid else {
            return nil
        }

        return rewrite
    }

    static func requestPersonaText(input: PersonaInput) async throws -> String {
        let content = try await generatedContent(
            instructions: SoundPrintPromptTemplates.personaInstructions(),
            prompt: SoundPrintPromptTemplates.personaPrompt(
                totalLogCount: input.totalLogCount,
                averageRating: input.averageRating,
                topTasteDimensions: input.dimensions.map(\.label),
                avoidanceSignals: input.avoidanceSignals,
                recentLogSummary: input.recentLogs
                    .map { "\($0.albumTitle) by \($0.artistName), rating \($0.rating)" }
                    .joined(separator: " | "),
                evidenceSnippets: input.recentLogs.map(\.reviewSnippet).filter { !$0.isEmpty }
            )
        )
        let payload = try decodedJSON(PersonaPayload.self, from: content)
        return payload.personaText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns nil (rather than throwing) on any failure so a broken/unavailable critic pass
    /// never blocks the persona update — it's a refinement layer on top of the mandatory local
    /// validator, not a required pipeline stage.
    static func critiquePersona(_ personaText: String, input: PersonaInput) async -> CriticPayload? {
        do {
            let evidenceSnippets = input.recentLogs.map(\.reviewSnippet).filter { !$0.isEmpty }
            let content = try await generatedContent(
                instructions: SoundPrintPromptTemplates.criticInstructions(),
                prompt: SoundPrintPromptTemplates.criticPrompt(personaText: personaText, evidenceSnippets: evidenceSnippets)
            )
            return try decodedJSON(CriticPayload.self, from: content)
        } catch {
            return nil
        }
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
        "mood": "Emotional Temperature",
        "energy": "Energy Bias",
        "productionStyle": "Production Taste",
        "vocalFocus": "Vocal Gravity",
        "lyricFocus": "Lyric Attention",
        "experimentation": "Experimental Tolerance",
        "instrumentalRichness": "Arrangement Depth",
        "genreOpenness": "Genre Flex",
        "eraAffinity": "Era Pull",
        "replayability": "Replay Pull",
        "tracklistConsistency": "Tracklist Patience",
        "emotionalDirectness": "Emotional Directness",
        "texturePreference": "Texture Bias"
    ]

    static let allowedAvoidanceCategories: [String: String] = [
        "fillerSensitivity": "Filler Sensitivity",
        "sterileProduction": "Sterile Production",
        "weakWriting": "Weak Writing",
        "lowReplayValue": "Low Replay Value",
        "energyWithoutPayoff": "Energy Without Payoff",
        "moodMismatch": "Mood Mismatch",
        "skipHeavyAlbums": "Skip-Heavy Albums"
    ]

    static var allowedDimensionNames: [String] {
        allowedDimensions.keys.sorted()
    }

    static var allowedAvoidanceCategoryNames: [String] {
        allowedAvoidanceCategories.keys.sorted()
    }

    static func validatedSentiment(score: Double, confidence: Double) -> SentimentResult {
        SentimentResult(
            score: score.clamped(to: -1.0...1.0),
            confidence: confidence.clamped(to: 0.0...1.0)
        )
    }

    static func validatedTasteExtraction(
        payload: TasteExtractionPayload,
        input: TasteExtractionInput
    ) throws -> TasteExtractionResult {
        let sentimentScore = input.sentimentScore ?? payload.sentiment.score
        let avoidanceSignals = try validatedAvoidanceSignals(payload.avoidanceSignals)

        guard sentimentScore >= 0.0 else {
            return TasteExtractionResult(signals: [], avoidanceSignals: avoidanceSignals)
        }

        guard !payload.positiveSignals.isEmpty else {
            throw FoundationModelsSoundPrintProviderError.emptyOutput
        }

        var seenDimensionNames: Set<String> = []
        var signals: [TasteSignal] = []

        for payloadSignal in payload.positiveSignals.prefix(4) {
            let rawDimensionName = payloadSignal.dimensionKey.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let dimensionName = allowedKey(rawDimensionName, in: allowedDimensions),
                  let label = allowedDimensions[dimensionName],
                  !seenDimensionNames.contains(dimensionName) else {
                throw FoundationModelsSoundPrintProviderError.validationFailed
            }

            let summary = payloadSignal.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidenceSnippet = payloadSignal.evidenceSnippet.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !summary.isEmpty, !evidenceSnippet.isEmpty else {
                throw FoundationModelsSoundPrintProviderError.validationFailed
            }

            seenDimensionNames.insert(dimensionName)
            signals.append(
                TasteSignal(
                    dimensionName: dimensionName,
                    label: label,
                    summary: summary,
                    weight: payloadSignal.strength.clamped(to: 0.0...1.0),
                    confidence: payloadSignal.confidence.clamped(to: 0.0...1.0),
                    evidenceSnippet: evidenceSnippet,
                    isPositiveEvidence: true
                )
            )
        }

        return TasteExtractionResult(signals: signals, avoidanceSignals: avoidanceSignals)
    }

    static func validatedPersona(text: String, input: PersonaInput) throws -> PersonaResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let concreteSignals = concreteSignals(from: input) + input.avoidanceSignals

        guard SoundPrintOutputValidator.isPersonaValid(trimmed, concreteSignals: concreteSignals, logCount: input.totalLogCount) else {
            throw FoundationModelsSoundPrintProviderError.validationFailed
        }

        return PersonaResult(text: trimmed, generationSource: .foundationModels)
    }

    static func concreteSignals(from input: PersonaInput) -> [String] {
        input.dimensions.map(\.label)
            + input.topTags
            + input.recentLogs.map(\.albumTitle)
            + input.recentLogs.map(\.artistName)
            + input.recentLogs.map(\.reviewSnippet)
    }

    private static func validatedAvoidanceSignals(
        _ payloadSignals: [FoundationModelsAvoidanceSignalPayload]
    ) throws -> [AvoidanceSignal] {
        var seenSignalNames: Set<String> = []
        var signals: [AvoidanceSignal] = []

        for payloadSignal in payloadSignals.prefix(3) {
            let rawSignalName = payloadSignal.signalKey.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let signalName = allowedKey(rawSignalName, in: allowedAvoidanceCategories),
                  let label = allowedAvoidanceCategories[signalName],
                  !seenSignalNames.contains(signalName) else {
                throw FoundationModelsSoundPrintProviderError.validationFailed
            }

            let summary = payloadSignal.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidenceSnippet = payloadSignal.evidenceSnippet.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !summary.isEmpty, !evidenceSnippet.isEmpty else {
                throw FoundationModelsSoundPrintProviderError.validationFailed
            }

            seenSignalNames.insert(signalName)
            signals.append(
                AvoidanceSignal(
                    signalName: signalName,
                    label: label,
                    summary: summary,
                    strength: payloadSignal.strength.clamped(to: 0.0...1.0),
                    confidence: payloadSignal.confidence.clamped(to: 0.0...1.0),
                    evidenceSnippet: evidenceSnippet
                )
            )
        }

        return signals
    }

    private static func allowedKey(_ value: String, in allowedValues: [String: String]) -> String? {
        if allowedValues[value] != nil {
            return value
        }

        let normalized = value.normalizedSoundPrintText
        return allowedValues.first { key, label in
            key.normalizedSoundPrintText == normalized || label.normalizedSoundPrintText == normalized
        }?.key
    }
}

private struct SentimentPayload: Decodable {
    let score: Double
    let confidence: Double
}

struct FoundationModelsPositiveSignalPayload: Decodable {
    let dimensionKey: String
    let label: String
    let summary: String
    let strength: Double
    let confidence: Double
    let evidenceSnippet: String
}

struct FoundationModelsAvoidanceSignalPayload: Decodable {
    let signalKey: String
    let label: String
    let summary: String
    let strength: Double
    let confidence: Double
    let evidenceSnippet: String
}

struct TasteExtractionPayload: Decodable {
    struct Sentiment: Decodable {
        let score: Double
        let confidence: Double
    }

    let sentiment: Sentiment
    let positiveSignals: [FoundationModelsPositiveSignalPayload]
    let avoidanceSignals: [FoundationModelsAvoidanceSignalPayload]
}

private struct PersonaPayload: Decodable {
    let personaText: String
}

private struct CompactSummaryPayload: Decodable {
    let headline: String
    let summary: String
    let bullets: [String]
}

private struct CriticPayload: Decodable {
    let passes: Bool
    let suggestedRewrite: String?
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
