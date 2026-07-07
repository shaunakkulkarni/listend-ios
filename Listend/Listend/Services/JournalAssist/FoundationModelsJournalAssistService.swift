//
//  FoundationModelsJournalAssistService.swift
//  Listend
//
//  Created by Codex on 5/18/26.
//

import Foundation
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

struct FoundationModelsJournalAssistService: JournalAssistServiceProtocol {
    private static let logger = Logger(subsystem: "com.shaunakkulkarni.Listend", category: "JournalAssist")

    let reflectionPrompts: [JournalAssistPrompt]

    init(reflectionPrompts: [JournalAssistPrompt] = JournalAssistPrompt.defaults) {
        self.reflectionPrompts = reflectionPrompts
    }

    func draftReview(for input: JournalAssistInput) async throws -> JournalAssistDraftResult {
        guard input.hasMeaningfulUserInput else {
            return .needsInput(prompts: reflectionPrompts)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let generated = try await Self.guidedResponse(
                instructions: """
                You are a thoughtful music diarist helping a Listend user capture their honest
                listening experience. Write with emotional specificity and personal warmth.
                Synthesize the user's rating, notes, and prompt answers into a cohesive first-person
                reflection — not a list of facts. Anchor your response in concrete details the user
                shared: specific moments, sounds, lyrics, or feelings. Use the user's own language
                and phrasing where possible.
                """,
                prompt: """
                Write a first-person album journal draft.
                Rules: 2-4 sentences; conversational voice; synthesize the user's prompt answers
                and notes into one cohesive thought. Be specific — name what stood out and why it
                mattered. Use the user's own words and concrete details rather than vague praise.
                The entry should feel personal, like a real diary entry.
                Album: \(input.albumTitle)
                Artist: \(input.artistName)
                Genre: \(input.genreName ?? "")
                Release year: \(input.releaseYear.map(String.init) ?? "")
                Rating: \(input.rating.map { String($0) } ?? "")
                Existing review: \(input.existingReviewText)
                Existing tags: \(input.existingTags.joined(separator: ", "))
                Notes: \(input.notes)
                Prompt answers: \(Self.promptAnswerText(from: input.promptAnswers))
                """,
                generating: GeneratedJournalDraft.self
            )
            let draft = try JournalAssistValidator.validatedDraft(generated.review, input: input)
            return .draft(draft)
        }
        #endif

        throw JournalAssistServiceError.unavailable
    }

    func suggestedTags(for input: JournalAssistInput) async throws -> [String] {
        guard input.hasMeaningfulUserInput else {
            return []
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let generated = try await Self.guidedResponse(
                instructions: """
                You suggest concise music journal tags for Listend, a personal music diary.
                Use only the user's notes, review, prompt answers, rating, existing tags, and album metadata.
                """,
                prompt: """
                Suggest 3-6 tags for this album journal entry.
                Rules: 1-3 words each; lowercase; no commas; do not repeat existing tags; no album title or artist-only tags.
                Album: \(input.albumTitle)
                Artist: \(input.artistName)
                Genre: \(input.genreName ?? "")
                Release year: \(input.releaseYear.map(String.init) ?? "")
                Rating: \(input.rating.map { String($0) } ?? "")
                Existing review: \(input.existingReviewText)
                Existing tags: \(input.existingTags.joined(separator: ", "))
                Notes: \(input.notes)
                Prompt answers: \(Self.promptAnswerText(from: input.promptAnswers))
                """,
                generating: GeneratedJournalTags.self
            )
            let tags = JournalAssistValidator.validatedTags(generated.tags, input: input)

            guard !tags.isEmpty else {
                throw JournalAssistServiceError.validationFailed
            }

            return tags
        }
        #endif

        throw JournalAssistServiceError.unavailable
    }
}

#if canImport(FoundationModels)

// MARK: - Guided generation schemas

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A first-person album journal draft")
struct GeneratedJournalDraft {
    @Guide(description: "The draft review: 2-4 conversational first-person sentences grounded in the user's own words and concrete details")
    var review: String
}

@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Short tags for one album journal entry")
struct GeneratedJournalTags {
    @Guide(description: "Lowercase tags, 1-3 words each, no commas; never just the album title or artist name; never a repeat of an existing tag", .maximumCount(6))
    var tags: [String]
}

// MARK: - Generation plumbing

@available(iOS 26.0, macOS 26.0, *)
private extension FoundationModelsJournalAssistService {
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
            throw JournalAssistServiceError.unavailable
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

        throw lastError ?? JournalAssistServiceError.unavailable
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

private extension FoundationModelsJournalAssistService {
    static func promptAnswerText(from answers: [JournalAssistPromptAnswer]) -> String {
        answers
            .filter { !$0.answer.trimmedForJournalAssist.isEmpty }
            .map { "\($0.question): \($0.answer)" }
            .joined(separator: " | ")
    }
}
