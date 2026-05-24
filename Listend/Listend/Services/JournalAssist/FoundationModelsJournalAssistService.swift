//
//  FoundationModelsJournalAssistService.swift
//  Listend
//
//  Created by Codex on 5/18/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct FoundationModelsJournalAssistService: JournalAssistServiceProtocol {
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
            let content = try await Self.generatedContent(
                instructions: """
                You are a thoughtful music diarist helping a Listend user capture their honest
                listening experience. Write with emotional specificity and personal warmth.
                Synthesize the user's rating, notes, and prompt answers into a cohesive first-person
                reflection — not a list of facts. Anchor your response in concrete details the user
                shared: specific moments, sounds, lyrics, or feelings. Use the user's own language
                and phrasing where possible. Return only compact JSON.
                """,
                prompt: """
                Write a first-person album journal draft.
                JSON schema: {"review": String}
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
                """
            )
            let payload = try Self.decodedJSON(JournalAssistDraftPayload.self, from: content)
            let draft = try JournalAssistValidator.validatedDraft(payload.review, input: input)
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
            let content = try await Self.generatedContent(
                instructions: """
                You suggest concise music journal tags for Listend. Return only compact JSON.
                Use only the user's notes, review, prompt answers, rating, existing tags, and album metadata.
                """,
                prompt: """
                Suggest 3-6 tags for this album journal entry.
                JSON schema: {"tags":[String]}
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
                """
            )
            let payload = try Self.decodedJSON(JournalAssistTagsPayload.self, from: content)
            let tags = JournalAssistValidator.validatedTags(payload.tags, input: input)

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
    static func generatedContent(instructions: String, prompt: String) async throws -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        default:
            throw JournalAssistServiceError.unavailable
        }

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        let content = String(describing: response.content).trimmedForJournalAssist

        guard !content.isEmpty else {
            throw JournalAssistServiceError.emptyOutput
        }

        return content
    }
}
#endif

struct JournalAssistDraftPayload: Decodable {
    let review: String
}

struct JournalAssistTagsPayload: Decodable {
    let tags: [String]
}

private extension FoundationModelsJournalAssistService {
    static func promptAnswerText(from answers: [JournalAssistPromptAnswer]) -> String {
        answers
            .filter { !$0.answer.trimmedForJournalAssist.isEmpty }
            .map { "\($0.question): \($0.answer)" }
            .joined(separator: " | ")
    }

    static func decodedJSON<T: Decodable>(_ type: T.Type, from content: String) throws -> T {
        guard let data = content.journalAssistJSONData else {
            throw JournalAssistServiceError.malformedOutput
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw JournalAssistServiceError.malformedOutput
        }
    }
}

private extension String {
    var journalAssistJSONData: Data? {
        let trimmed = trimmedForJournalAssist

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
