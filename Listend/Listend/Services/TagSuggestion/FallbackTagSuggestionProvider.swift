//
//  FallbackTagSuggestionProvider.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

struct FallbackTagSuggestionProvider: TagSuggestionProvider {
    let primary: TagSuggestionProvider
    let fallback: TagSuggestionProvider

    init(
        primary: TagSuggestionProvider = FoundationModelsTagSuggestionProvider(),
        fallback: TagSuggestionProvider = LocalTagSuggestionProvider()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func suggestedTags(for input: TagSuggestionInput) async throws -> [String] {
        let fallbackTags = (try? await fallback.suggestedTags(for: input)) ?? []

        do {
            let primaryTags = try await primary.suggestedTags(for: input)
            return TagSuggestionValidator.validatedTags(primaryTags + fallbackTags, input: input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return fallbackTags
        }
    }
}

