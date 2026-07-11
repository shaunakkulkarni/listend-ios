//
//  LocalTagSuggestionProvider.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

import Foundation

struct LocalTagSuggestionProvider: TagSuggestionProvider {
    func suggestedTags(for input: TagSuggestionInput) async throws -> [String] {
        Self.suggestedTags(for: input)
    }

    nonisolated static func suggestedTags(for input: TagSuggestionInput) -> [String] {
        LocalTagSuggestionEngine.suggestions(
            albumTitle: input.albumTitle,
            artistName: input.artistName,
            genreName: input.genreName,
            releaseYear: input.releaseYear,
            reviewText: input.reviewText,
            existingTags: input.existingTags
        )
    }
}
