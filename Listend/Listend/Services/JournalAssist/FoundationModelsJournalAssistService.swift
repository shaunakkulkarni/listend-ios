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

/// iOS 26-safe FoundationModels path: plain text responses parsed and validated
/// locally, with `FallbackJournalAssistService` handling any failure. Do not move
/// this target to the newer structured generation convenience APIs — referencing
/// them in the shipping binary has crashed iOS 26 TestFlight builds at launch
/// with unresolved symbols, even behind `#available` checks.
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
            let generated = try await Self.textResponse(
                instructions: JournalAssistPromptBuilder.draftInstructions,
                prompt: JournalAssistPromptBuilder.draftPrompt(for: input)
            )
            let draft = try JournalAssistValidator.validatedDraft(generated, input: input)
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
            let generated = try await Self.textResponse(
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
                Prompt answers: \(JournalAssistPromptBuilder.promptAnswerText(from: input.promptAnswers))
                """
            )
            let tags = JournalAssistValidator.validatedTags(Self.tags(from: generated), input: input)

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
@available(iOS 26.0, macOS 26.0, *)
private extension FoundationModelsJournalAssistService {
    static func textResponse(
        instructions: String,
        prompt: String
    ) async throws -> String {
        guard case .available = SystemLanguageModel.default.availability else {
            throw JournalAssistServiceError.unavailable
        }

        var lastError: Error?

        for attempt in 1...2 {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    throw JournalAssistServiceError.validationFailed
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

enum JournalAssistPromptBuilder {
    static let draftInstructions = """
    You are a thoughtful music diarist helping a Listend user capture their honest listening
    experience. Use only evidence the user explicitly supplied. Treat selected reaction display
    names as user-authored evidence, and preserve the user's own language where possible.
    """

    static func draftPrompt(for input: JournalAssistInput) -> String {
        """
        Write a first-person album journal draft.
        Rules:
        - Write 1-2 concise, conversational sentences that feel like a personal journal entry.
        - Synthesize only the evidence supplied below.
        - Treat selected reactions as user-authored evidence.
        - Do not invent lyrics, sounds, production details, track moments, emotions, listening contexts, or reasons that the user did not supply.
        - If a detail was not supplied, omit it rather than inferring it.
        Album: \(input.albumTitle)
        Artist: \(input.artistName)
        Genre: \(input.genreName ?? "")
        Release year: \(input.releaseYear.map(String.init) ?? "")
        Rating: \(input.rating.map { String($0) } ?? "")
        Existing review: \(input.existingReviewText)
        Existing custom or legacy tags: \(input.existingTags.joined(separator: ", "))
        Selected reactions (user-authored evidence): \(input.selectedReactionDisplayNames.joined(separator: ", "))
        Notes: \(input.notes)
        Prompt answers: \(promptAnswerText(from: input.promptAnswers))
        """
    }

    static func promptAnswerText(from answers: [JournalAssistPromptAnswer]) -> String {
        answers
            .filter { !$0.answer.trimmedForJournalAssist.isEmpty }
            .map { "\($0.question): \($0.answer)" }
            .joined(separator: " | ")
    }
}
