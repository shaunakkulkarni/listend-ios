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

/// iOS 26-safe FoundationModels path: uses the model for prose generation and
/// simple sentiment output, then parses and validates the text locally. Taste
/// signal extraction stays deterministic because the on-device model does not
/// reliably preserve its multi-field response schema.
///
/// Do not move this target to the newer structured generation convenience APIs.
/// Merely referencing them in the shipping binary has crashed iOS 26 TestFlight
/// builds at launch with unresolved symbols — even behind `#available` checks.
/// `scripts/check-foundationmodels-symbols.sh` guards against reintroduction.
struct FoundationModelsSoundPrintProvider: SoundPrintProvider {
    private static let logger = Logger(subsystem: "com.shaunakkulkarni.Listend", category: "SoundPrint")

    init() {}

    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let generated = try await Self.textResponse(
                instructions: """
                You analyze album log sentiment for Listend, a personal music diary.
                Return exactly one line: SENTIMENT | <score> | <confidence>
                score is -1.0 for strongly negative, 0.0 for neutral, 1.0 for strongly positive.
                confidence is 0.0 to 1.0.
                """,
                prompt: """
                Rating: \(input.rating) / 5
                Review: \(input.reviewText)
                Tags: \(input.tags.joined(separator: ", "))
                """
            )
            let sentiment = try FoundationModelsSoundPrintValidator.decodedSentiment(from: generated)
            return FoundationModelsSoundPrintValidator.validatedSentiment(
                score: sentiment.score,
                confidence: sentiment.confidence
            )
        }
        #endif

        throw FoundationModelsSoundPrintProviderError.unavailable
    }

    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult {
        MockSoundPrintProvider.extractTasteSignals(input: input)
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
            caseName = "decodingFailure — output could not be decoded"
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
            tone: .balanced,
            supportsReplayBehaviorClaims: FoundationModelsSoundPrintValidator.supportsReplayBehaviorClaims(from: input)
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
        let boundedDimensions = input.dimensions
            .sorted {
                if $0.weight == $1.weight {
                    return $0.label < $1.label
                }

                return $0.weight > $1.weight
            }
            .prefix(5)
        let boundedAvoidanceSignals = input.avoidanceSignals.prefix(3)
        let boundedTags = input.topTags.prefix(5)
        let boundedLogs = input.recentLogs.prefix(10)

        return try await textResponse(
            instructions: SoundPrintPromptTemplates.personaInstructions(tone: input.tone),
            prompt: SoundPrintPromptTemplates.personaPrompt(
                totalLogCount: input.totalLogCount,
                averageRating: input.averageRating,
                topTasteDimensions: boundedDimensions.map(\.label),
                avoidanceSignals: Array(boundedAvoidanceSignals),
                topTags: Array(boundedTags),
                recentLogSummary: boundedLogs
                    .map(personaLogSummary)
                    .joined(separator: " | "),
                evidenceSnippets: boundedLogs
                    .map(\.reviewSnippet)
                    .filter { !$0.isEmpty }
                    .map(\.trimmedForSoundPrint),
                tone: input.tone
            )
        )
    }

    static func personaLogSummary(_ log: PersonaLogInput) -> String {
        var fields = [
            "\(boundedPromptField(log.albumTitle, characterLimit: 80)) by \(boundedPromptField(log.artistName, characterLimit: 60))",
            "rating \(log.rating)"
        ]

        let reactions = log.tags.prefix(3).map { boundedPromptField($0, characterLimit: 40) }
        if !reactions.isEmpty {
            fields.append("reactions/tags: \(reactions.joined(separator: ", "))")
        }

        let review = boundedPromptField(log.reviewSnippet, characterLimit: 120)
        if !review.isEmpty {
            fields.append("thought: \(review)")
        }

        let favoriteTracks = log.favoriteTracks.prefix(2).map { boundedPromptField($0, characterLimit: 60) }
        if !favoriteTracks.isEmpty {
            fields.append("favorite tracks: \(favoriteTracks.joined(separator: ", "))")
        }

        if log.hasStandoutMoment {
            fields.append("standout moment recorded")
        }

        return fields.joined(separator: "; ")
    }

    static func boundedPromptField(_ value: String, characterLimit: Int) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard singleLine.count > characterLimit else {
            return singleLine
        }

        return String(singleLine.prefix(characterLimit)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func requestTasteExtractionPayload(input: TasteExtractionInput) async throws -> TasteExtractionPayload {
        let generated = try await textResponse(
            instructions: SoundPrintPromptTemplates.tasteExtractionInstructions(),
            prompt: """
            \(SoundPrintPromptTemplates.tasteExtractionPrompt(
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
            ))

            Return only pipe-delimited lines in this format:
            SENTIMENT | <score> | <confidence>
            POSITIVE | <dimensionKey> | <strength> | <confidence> | <summary> | <evidenceSnippet>
            AVOIDANCE | <signalKey> | <strength> | <confidence> | <summary> | <evidenceSnippet>

            Allowed dimensionKey values: \(FoundationModelsSoundPrintValidator.allowedDimensionNames.joined(separator: ", "))
            Allowed signalKey values: \(FoundationModelsSoundPrintValidator.allowedAvoidanceCategoryNames.joined(separator: ", "))
            Always include exactly one SENTIMENT line.
            Omit POSITIVE or AVOIDANCE lines when no signal of that type is supported.
            Do not use the | character inside summaries or evidence snippets.
            """
        )
        return try FoundationModelsSoundPrintValidator.decodedTasteExtractionPayload(from: generated)
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

    static func decodedSentiment(from text: String) throws -> TasteExtractionPayload.Sentiment {
        if let decoded = try? JSONDecoder().decode(TasteExtractionPayload.Sentiment.self, from: jsonData(from: text)) {
            return decoded
        }

        guard let line = protocolLines(from: text).first(where: { $0.first == "SENTIMENT" }),
              line.count == 3,
              let score = Double(line[1]),
              let confidence = Double(line[2]) else {
            throw FoundationModelsSoundPrintProviderError.malformedOutput
        }

        return TasteExtractionPayload.Sentiment(score: score, confidence: confidence)
    }

    static func decodedTasteExtractionPayload(from text: String) throws -> TasteExtractionPayload {
        if let decoded = try? JSONDecoder().decode(TasteExtractionPayload.self, from: jsonData(from: text)) {
            return decoded
        }

        var sentiment: TasteExtractionPayload.Sentiment?
        var positiveSignals: [FoundationModelsPositiveSignalPayload] = []
        var avoidanceSignals: [FoundationModelsAvoidanceSignalPayload] = []

        for fields in protocolLines(from: text) {
            switch fields.first {
            case "SENTIMENT":
                guard fields.count == 3,
                      let score = Double(fields[1]),
                      let confidence = Double(fields[2]) else {
                    throw FoundationModelsSoundPrintProviderError.malformedOutput
                }
                sentiment = TasteExtractionPayload.Sentiment(score: score, confidence: confidence)

            case "POSITIVE":
                guard fields.count == 6,
                      let strength = Double(fields[2]),
                      let confidence = Double(fields[3]) else {
                    throw FoundationModelsSoundPrintProviderError.malformedOutput
                }
                positiveSignals.append(
                    FoundationModelsPositiveSignalPayload(
                        dimensionKey: fields[1],
                        label: fields[1],
                        summary: fields[4],
                        strength: strength,
                        confidence: confidence,
                        evidenceSnippet: fields[5]
                    )
                )

            case "AVOIDANCE":
                guard fields.count == 6,
                      let strength = Double(fields[2]),
                      let confidence = Double(fields[3]) else {
                    throw FoundationModelsSoundPrintProviderError.malformedOutput
                }
                avoidanceSignals.append(
                    FoundationModelsAvoidanceSignalPayload(
                        signalKey: fields[1],
                        label: fields[1],
                        summary: fields[4],
                        strength: strength,
                        confidence: confidence,
                        evidenceSnippet: fields[5]
                    )
                )

            default:
                continue
            }
        }

        guard let sentiment else {
            throw FoundationModelsSoundPrintProviderError.malformedOutput
        }

        return TasteExtractionPayload(
            sentiment: sentiment,
            positiveSignals: positiveSignals,
            avoidanceSignals: avoidanceSignals
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
            tone: .balanced,
            supportsReplayBehaviorClaims: supportsReplayBehaviorClaims(from: input)
        ) else {
            throw FoundationModelsSoundPrintProviderError.validationFailed
        }

        return PersonaResult(text: trimmed, generationSource: .foundationModels)
    }

    static func userFacingSignals(from input: PersonaInput) -> [String] {
        let logs = Array(input.recentLogs.prefix(10))

        return Array(input.topTags.prefix(5))
            + logs.map(\.albumTitle)
            + logs.map(\.artistName)
            + logs.flatMap { $0.tags.prefix(3) }
            + logs.compactMap(\.reviewSnippet.firstSoundPrintPhrase)
    }

    static func supportsReplayBehaviorClaims(from input: PersonaInput) -> Bool {
        let explicitReplayPhrases = [
            "replay", "repeat", "on repeat", "in rotation", "come back", "return to", "revisit"
        ]

        return input.recentLogs.prefix(10).contains { log in
            let explicitText = ([log.reviewSnippet] + Array(log.tags.prefix(3)))
                .joined(separator: " ")
                .normalizedSoundPrintText
            return explicitReplayPhrases.contains(where: { explicitText.containsNormalizedSoundPrintPhrase($0) })
        }
    }

    static func internalAnalysisLabels(from input: PersonaInput) -> [String] {
        input.dimensions.map(\.label) + input.avoidanceSignals + internalKeyNames(input.dimensions.map(\.name))
    }

    static func concreteSignals(from input: PersonaInput) -> [String] {
        userFacingSignals(from: input)
    }

    static func userFacingSignals(from input: CompactSummaryInput) -> [String] {
        input.userFacingSignals
    }

    static func internalAnalysisLabels(from input: CompactSummaryInput) -> [String] {
        input.dimensions.map(\.label)
            + input.avoidanceSignals.map(\.label)
            + internalKeyNames(input.dimensions.map(\.name) + input.avoidanceSignals.map(\.name))
    }

    /// Raw internal key names must never surface in user-facing copy. Only
    /// camelCase compound keys (e.g. "tracklistConsistency", "skipHeavyAlbums")
    /// are flagged — single-word keys like "mood" or "energy" are ordinary
    /// English words and would false-positive on natural persona text.
    static func internalKeyNames(_ names: [String]) -> [String] {
        names.filter { $0.lowercased() != $0 }
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

    private static func jsonData(from text: String) -> Data {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("```") {
            var lines = trimmed.split(whereSeparator: \.isNewline).map(String.init)
            if lines.first?.hasPrefix("```") == true {
                lines.removeFirst()
            }
            if lines.last?.hasPrefix("```") == true {
                lines.removeLast()
            }
            trimmed = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}"),
           start <= end {
            trimmed = String(trimmed[start...end])
        }

        return Data(trimmed.utf8)
    }

    private static func protocolLines(from text: String) -> [[String]] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.contains("|") else {
                return nil
            }

            var fields = line.split(separator: "|", maxSplits: 5, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            fields[0] = fields[0]
                .trimmingCharacters(in: CharacterSet(charactersIn: "-* "))
                .uppercased()
            return fields
        }
    }
}

struct FoundationModelsPositiveSignalPayload: Codable {
    let dimensionKey: String
    let label: String
    let summary: String
    let strength: Double
    let confidence: Double
    let evidenceSnippet: String
}

struct FoundationModelsAvoidanceSignalPayload: Codable {
    let signalKey: String
    let label: String
    let summary: String
    let strength: Double
    let confidence: Double
    let evidenceSnippet: String
}

struct TasteExtractionPayload: Codable {
    struct Sentiment: Codable {
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
