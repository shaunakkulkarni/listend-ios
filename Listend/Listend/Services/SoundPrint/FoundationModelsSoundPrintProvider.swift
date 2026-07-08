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
        throw FoundationModelsSoundPrintProviderError.unavailable
    }

    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult {
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
            let generated = try await Self.requestCompactSummaryText(
                instructions: SoundPrintPromptTemplates.compactSummaryInstructions(tone: input.tone),
                prompt: """
                \(SoundPrintPromptTemplates.compactSummaryPrompt(
                    topTasteDimensions: topTasteDimensions,
                    avoidanceSignals: avoidanceLabels,
                    userFacingSignals: input.userFacingSignals,
                    recentChanges: input.recentChanges,
                    tone: input.tone
                ))

                Reply in exactly this format:
                Headline: <maximum 7 words>
                Summary: <one sentence, maximum 28 words>
                Bullet: <maximum 12 words>
                Bullet: <maximum 12 words>
                Bullet: <maximum 12 words>
                """
            )
            let outcome = SoundPrintOutputValidator.validateCompactSummary(
                headline: generated.headline,
                summary: generated.summary,
                bullets: generated.bullets,
                tone: input.tone,
                userFacingSignals: FoundationModelsSoundPrintValidator.userFacingSignals(from: input),
                internalAnalysisLabels: FoundationModelsSoundPrintValidator.internalAnalysisLabels(from: input)
            )

            guard outcome.isValid else {
                Self.logger.error("FoundationModels compact summary rejected: \(String(describing: outcome), privacy: .public)")
                throw FoundationModelsSoundPrintProviderError.validationFailed
            }

            return CompactSummaryResult(headline: generated.headline, summary: generated.summary, bullets: generated.bullets)
        }
        #endif

        throw FoundationModelsSoundPrintProviderError.unavailable
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private extension FoundationModelsSoundPrintProvider {
    static func textResponse(
        instructions: String,
        prompt: String
    ) async throws -> String {
        guard case .available = SystemLanguageModel.default.availability else {
            throw FoundationModelsSoundPrintProviderError.unavailable
        }

        var lastError: Error?

        for attempt in 1...2 {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    throw FoundationModelsSoundPrintProviderError.emptyOutput
                }
                return text
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                let description = describeGenerationFailure(error)

                guard attempt == 1, isTransientGenerationFailure(error) else {
                    logger.error("FoundationModels text generation failed: \(description, privacy: .public)")
                    break
                }

                logger.error("FoundationModels text generation failed; retrying once: \(description, privacy: .public)")
                try await Task.sleep(nanoseconds: 400_000_000)
            }
        }

        throw lastError ?? FoundationModelsSoundPrintProviderError.unavailable
    }

    static func describeGenerationFailure(_ error: Error) -> String {
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            return String(describing: error)
        }

        let caseName: String
        switch generationError {
        case .assetsUnavailable:
            caseName = "assetsUnavailable — model assets are not ready on this device"
        case .decodingFailure:
            caseName = "decodingFailure — output could not be decoded into the guided schema"
        case .exceededContextWindowSize:
            caseName = "exceededContextWindowSize — prompt is too long for the context window"
        case .guardrailViolation:
            caseName = "guardrailViolation — safety guardrails flagged the prompt or output"
        case .rateLimited:
            caseName = "rateLimited"
        case .concurrentRequests:
            caseName = "concurrentRequests"
        case .unsupportedGuide:
            caseName = "unsupportedGuide"
        case .unsupportedLanguageOrLocale:
            caseName = "unsupportedLanguageOrLocale"
        case .refusal:
            caseName = "refusal — the model declined this request"
        @unknown default:
            caseName = "unknown GenerationError case"
        }

        return "\(caseName) (\(String(describing: generationError)))"
    }

    static func isTransientGenerationFailure(_ error: Error) -> Bool {
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            // Opaque failures (e.g. beta ModelManagerServices errors) are worth one retry.
            return true
        }

        switch generationError {
        case .assetsUnavailable, .rateLimited, .concurrentRequests, .decodingFailure:
            return true
        default:
            return false
        }
    }

    /// Orchestrates persona generation: draft via FM, gate through the always-on local
    /// validator, retry once (a fresh sample often fixes a one-off formatting miss),
    /// then fall back to the deterministic Mock persona rather than surfacing an error.
    static func generatePersonaViaFoundationModels(input: PersonaInput) async throws -> PersonaResult {
        let context = SoundPrintOutputValidator.PersonaValidationContext(
            userFacingSignals: FoundationModelsSoundPrintValidator.userFacingSignals(from: input),
            internalAnalysisLabels: FoundationModelsSoundPrintValidator.internalAnalysisLabels(from: input),
            logCount: input.totalLogCount,
            tone: input.tone
        )

        let draftText = try await requestPersonaText(input: input)
        if SoundPrintOutputValidator.validatePersona(draftText, context: context).isValid {
            return PersonaResult(text: draftText, generationSource: .foundationModels)
        }

        FoundationModelsSoundPrintProvider.logger.error("FoundationModels persona rejected; retrying draft once: \(String(describing: SoundPrintOutputValidator.validatePersona(draftText, context: context)), privacy: .public)")

        let retryText = try await requestPersonaText(input: input)
        let retryOutcome = SoundPrintOutputValidator.validatePersona(retryText, context: context)
        if retryOutcome.isValid {
            return PersonaResult(text: retryText, generationSource: .foundationModels)
        }

        FoundationModelsSoundPrintProvider.logger.error("FoundationModels persona still invalid after retry; using local fallback: \(String(describing: retryOutcome), privacy: .public)")
        return MockSoundPrintProvider.generatePersona(input: input)
    }

    static func requestPersonaText(input: PersonaInput) async throws -> String {
        try await textResponse(
            instructions: SoundPrintPromptTemplates.personaInstructions(tone: input.tone),
            prompt: SoundPrintPromptTemplates.personaPrompt(
                totalLogCount: input.totalLogCount,
                averageRating: input.averageRating,
                topTasteDimensions: input.dimensions.map(\.label),
                avoidanceSignals: input.avoidanceSignals,
                recentLogSummary: input.recentLogs
                    .map { "\($0.albumTitle) by \($0.artistName), rating \($0.rating)" }
                    .joined(separator: " | "),
                evidenceSnippets: input.recentLogs.map(\.reviewSnippet).filter { !$0.isEmpty },
                tone: input.tone
            )
        )
    }

    static func requestCompactSummaryText(instructions: String, prompt: String) async throws -> CompactSummaryResult {
        let text = try await textResponse(instructions: instructions, prompt: prompt)
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let headline = value(from: lines, prefix: "Headline:")
        let summary = value(from: lines, prefix: "Summary:")
        let bullets = lines.compactMap { line in
            value(from: [line], prefix: "Bullet:")
        }

        guard let headline, let summary, bullets.count == 3 else {
            throw FoundationModelsSoundPrintProviderError.malformedOutput
        }

        return CompactSummaryResult(headline: headline, summary: summary, bullets: bullets)
    }

    static func value(from lines: [String], prefix: String) -> String? {
        let value = lines.first { $0.hasPrefix(prefix) }?
            .dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let value, !value.isEmpty else {
            return nil
        }

        return value
    }
}
#endif

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

    static let maxPositiveSignalCount = 4
    static let maxAvoidanceSignalCount = 3

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

        for payloadSignal in payload.positiveSignals {
            guard signals.count < maxPositiveSignalCount else {
                break
            }

            let rawDimensionName = payloadSignal.dimensionKey.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let dimensionName = allowedKey(rawDimensionName, in: allowedDimensions),
                  let label = allowedDimensions[dimensionName] else {
                throw FoundationModelsSoundPrintProviderError.validationFailed
            }

            // A duplicate dimension or a blank field is a per-signal defect; drop that
            // signal and keep the rest instead of failing the whole extraction.
            guard !seenDimensionNames.contains(dimensionName) else {
                continue
            }

            let summary = payloadSignal.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidenceSnippet = payloadSignal.evidenceSnippet.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !summary.isEmpty, !evidenceSnippet.isEmpty else {
                continue
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

        guard SoundPrintOutputValidator.isPersonaValid(
            trimmed,
            userFacingSignals: userFacingSignals(from: input),
            internalAnalysisLabels: internalAnalysisLabels(from: input),
            logCount: input.totalLogCount,
            tone: input.tone
        ) else {
            throw FoundationModelsSoundPrintProviderError.validationFailed
        }

        return PersonaResult(text: trimmed, generationSource: .foundationModels)
    }

    static func userFacingSignals(from input: PersonaInput) -> [String] {
        input.topTags
            + input.recentLogs.map(\.albumTitle)
            + input.recentLogs.map(\.artistName)
            + input.recentLogs.flatMap(\.favoriteTracks)
            + input.recentLogs.compactMap(\.reviewSnippet.firstSoundPrintPhrase)
    }

    static func internalAnalysisLabels(from input: PersonaInput) -> [String] {
        input.dimensions.map(\.label) + input.avoidanceSignals
    }

    static func concreteSignals(from input: PersonaInput) -> [String] {
        userFacingSignals(from: input)
    }

    static func userFacingSignals(from input: CompactSummaryInput) -> [String] {
        input.userFacingSignals
    }

    static func internalAnalysisLabels(from input: CompactSummaryInput) -> [String] {
        input.dimensions.map(\.label) + input.avoidanceSignals.map(\.label)
    }

    private static func validatedAvoidanceSignals(
        _ payloadSignals: [FoundationModelsAvoidanceSignalPayload]
    ) throws -> [AvoidanceSignal] {
        var seenSignalNames: Set<String> = []
        var signals: [AvoidanceSignal] = []

        for payloadSignal in payloadSignals {
            guard signals.count < maxAvoidanceSignalCount else {
                break
            }

            let rawSignalName = payloadSignal.signalKey.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let signalName = allowedKey(rawSignalName, in: allowedAvoidanceCategories),
                  let label = allowedAvoidanceCategories[signalName] else {
                throw FoundationModelsSoundPrintProviderError.validationFailed
            }

            guard !seenSignalNames.contains(signalName) else {
                continue
            }

            let summary = payloadSignal.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let evidenceSnippet = payloadSignal.evidenceSnippet.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !summary.isEmpty, !evidenceSnippet.isEmpty else {
                continue
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

struct FoundationModelsPositiveSignalPayload {
    let dimensionKey: String
    let label: String
    let summary: String
    let strength: Double
    let confidence: Double
    let evidenceSnippet: String
}

struct FoundationModelsAvoidanceSignalPayload {
    let signalKey: String
    let label: String
    let summary: String
    let strength: Double
    let confidence: Double
    let evidenceSnippet: String
}

struct TasteExtractionPayload {
    struct Sentiment {
        let score: Double
        let confidence: Double
    }

    let sentiment: Sentiment
    let positiveSignals: [FoundationModelsPositiveSignalPayload]
    let avoidanceSignals: [FoundationModelsAvoidanceSignalPayload]
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
