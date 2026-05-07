//
//  MockTagSuggestionProvider.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

struct MockTagSuggestionProvider: TagSuggestionProvider {
    func suggestedTags(for input: TagSuggestionInput) async throws -> [String] {
        LocalTagSuggestionProvider.suggestedTags(for: input)
    }
}

