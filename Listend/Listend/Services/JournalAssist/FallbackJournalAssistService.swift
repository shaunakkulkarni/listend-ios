//
//  FallbackJournalAssistService.swift
//  Listend
//
//  Created by Codex on 5/18/26.
//

struct FallbackJournalAssistService: JournalAssistServiceProtocol {
    let primary: JournalAssistServiceProtocol
    let fallback: JournalAssistServiceProtocol

    var reflectionPrompts: [JournalAssistPrompt] {
        fallback.reflectionPrompts
    }

    init(
        primary: JournalAssistServiceProtocol = FoundationModelsJournalAssistService(),
        fallback: JournalAssistServiceProtocol = MockJournalAssistService()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func draftReview(for input: JournalAssistInput) async throws -> JournalAssistDraftResult {
        guard input.hasMeaningfulUserInput else {
            return .needsInput(prompts: reflectionPrompts)
        }

        do {
            return try await primary.draftReview(for: input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.draftReview(for: input)
        }
    }

    func suggestedTags(for input: JournalAssistInput) async throws -> [String] {
        do {
            return try await primary.suggestedTags(for: input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.suggestedTags(for: input)
        }
    }
}
