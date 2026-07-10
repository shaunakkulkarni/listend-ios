//
//  FoundationModelsTagSuggestionProvider.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

/// iOS 26-safe FoundationModels path: plain text responses parsed and validated
/// locally, with `FallbackTagSuggestionProvider` merging in the local provider's
/// tags. Do not move this target to the newer structured generation convenience
/// APIs — referencing them in the shipping binary has crashed iOS 26 TestFlight
/// builds at launch with unresolved symbols, even behind `#available` checks.
struct FoundationModelsTagSuggestionProvider: TagSuggestionProvider {
    private static let logger = Logger(subsystem: "com.shaunakkulkarni.Listend", category: "TagSuggestion")

    init() {}

    func suggestedTags(for input: TagSuggestionInput) async throws -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let genreName = input.genreName ?? ""
            let releaseYear = input.releaseYear.map { String($0) } ?? ""
            let existingTags = input.existingTags.joined(separator: ", ")
            let generated = try await Self.textResponse(
                instructions: """
                You suggest concise music log tags for Listend, a personal music diary.
                Use only the supplied review, existing tags, and album metadata.
                """,
                prompt: """
                Suggest up to 6 short tags for this album log.
                Rules: lowercase tags; 1-3 words each; no commas; do not repeat existing tags; do not use only the album title or artist name.
                Album: \(input.albumTitle)
                Artist: \(input.artistName)
                Genre: \(genreName)
                Release year: \(releaseYear)
                Review: \(input.reviewText)
                Existing tags: \(existingTags)
                """
            )
            return try FoundationModelsTagSuggestionValidator.validatedTags(
                FoundationModelsTagSuggestionPayload(tags: Self.tags(from: generated)),
                input: input
            )
        }
        #endif

        throw TagSuggestionProviderError.unavailable
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private extension FoundationModelsTagSuggestionProvider {
    static func textResponse(
        instructions: String,
        prompt: String
    ) async throws -> String {
        guard case .available = SystemLanguageModel.default.availability else {
            throw TagSuggestionProviderError.unavailable
        }

        var lastError: Error?

        for attempt in 1...2 {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    throw TagSuggestionProviderError.validationFailed
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

        throw lastError ?? TagSuggestionProviderError.unavailable
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

    static func tags(from text: String) -> [String] {
        text
            .split { $0.isNewline || $0 == "," || $0 == ";" }
            .map { line in
                String(line)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-*0123456789. "))
            }
            .filter { !$0.isEmpty }
    }
}
#endif

enum FoundationModelsTagSuggestionValidator {
    static func validatedTags(_ payload: FoundationModelsTagSuggestionPayload, input: TagSuggestionInput) throws -> [String] {
        let tags = TagSuggestionValidator.validatedTags(payload.tags, input: input)

        guard !tags.isEmpty else {
            throw TagSuggestionProviderError.validationFailed
        }

        return tags
    }
}

struct FoundationModelsTagSuggestionPayload {
    let tags: [String]
}
