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

struct FoundationModelsTagSuggestionProvider: TagSuggestionProvider {
    private static let logger = Logger(subsystem: "com.shaunakkulkarni.Listend", category: "TagSuggestion")

    init() {}

    func suggestedTags(for input: TagSuggestionInput) async throws -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let genreName = input.genreName ?? ""
            let releaseYear = input.releaseYear.map { String($0) } ?? ""
            let existingTags = input.existingTags.joined(separator: ", ")
            let generated = try await Self.guidedResponse(
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
                """,
                generating: GeneratedTagSuggestions.self
            )
            return try FoundationModelsTagSuggestionValidator.validatedTags(
                FoundationModelsTagSuggestionPayload(tags: generated.tags),
                input: input
            )
        }
        #endif

        throw TagSuggestionProviderError.unavailable
    }
}

#if canImport(FoundationModels)

// MARK: - Guided generation schema

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Short tags for one album log")
struct GeneratedTagSuggestions {
    @Guide(description: "Lowercase tags, 1-3 words each, no commas; never just the album title or artist name; never a repeat of an existing tag", .maximumCount(6))
    var tags: [String]
}

// MARK: - Generation plumbing

@available(iOS 26.0, macOS 26.0, *)
private extension FoundationModelsTagSuggestionProvider {
    /// Runs one guided-generation request. Constrained decoding guarantees the result
    /// matches the schema, so there is no JSON parsing and no malformed-output path.
    /// Retries once, but only for failures that can plausibly succeed on a second
    /// attempt (asset loading, rate limits, beta ModelManagerServices flakes) — a
    /// guardrail violation or oversized prompt will fail identically every time.
    static func guidedResponse<Content: Generable>(
        instructions: String,
        prompt: String,
        generating type: Content.Type
    ) async throws -> Content {
        guard case .available = SystemLanguageModel.default.availability else {
            throw TagSuggestionProviderError.unavailable
        }

        var lastError: Error?

        for attempt in 1...2 {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt, generating: type)
                return response.content
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                let description = describeGenerationFailure(error)
                let contentName = String(describing: type)

                guard attempt == 1, isTransientGenerationFailure(error) else {
                    logger.error("FoundationModels \(contentName, privacy: .public) generation failed: \(description, privacy: .public)")
                    break
                }

                logger.error("FoundationModels \(contentName, privacy: .public) generation failed; retrying once: \(description, privacy: .public)")
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
