//
//  FoundationModelsTagSuggestionProvider.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct FoundationModelsTagSuggestionProvider: TagSuggestionProvider {
    init() {}

    func suggestedTags(for input: TagSuggestionInput) async throws -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let genreName = input.genreName ?? ""
            let releaseYear = input.releaseYear.map { String($0) } ?? ""
            let existingTags = input.existingTags.joined(separator: ", ")
            let content = try await Self.generatedContent(
                instructions: """
                You suggest concise music log tags for Listend. Return only compact JSON.
                Do not include markdown, prose, or extra keys.
                """,
                prompt: """
                Suggest up to 6 short tags for this album log.
                JSON schema: {"tags":[String]}
                Rules: lowercase tags; 1-3 words each; no commas; do not repeat existing tags; do not use only the album title or artist name.
                Album: \(input.albumTitle)
                Artist: \(input.artistName)
                Genre: \(genreName)
                Release year: \(releaseYear)
                Review: \(input.reviewText)
                Existing tags: \(existingTags)
                """
            )
            let payload = try Self.decodedJSON(TagSuggestionPayload.self, from: content)
            let tags = TagSuggestionValidator.validatedTags(payload.tags, input: input)

            guard !tags.isEmpty else {
                throw TagSuggestionProviderError.validationFailed
            }

            return tags
        }
        #endif

        throw TagSuggestionProviderError.unavailable
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
private extension FoundationModelsTagSuggestionProvider {
    static func generatedContent(instructions: String, prompt: String) async throws -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        default:
            throw TagSuggestionProviderError.unavailable
        }

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: prompt)
        let content = String(describing: response.content).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            throw TagSuggestionProviderError.emptyOutput
        }

        return content
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

struct FoundationModelsTagSuggestionPayload: Decodable {
    let tags: [String]
}

private typealias TagSuggestionPayload = FoundationModelsTagSuggestionPayload

private extension FoundationModelsTagSuggestionProvider {
    static func decodedJSON<T: Decodable>(_ type: T.Type, from content: String) throws -> T {
        guard let data = content.tagSuggestionJSONData else {
            throw TagSuggestionProviderError.malformedOutput
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw TagSuggestionProviderError.malformedOutput
        }
    }
}

private extension String {
    var tagSuggestionJSONData: Data? {
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

