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
        var candidates: [String] = []

        if let genreName = input.genreName {
            candidates.append(genreName)
        }

        let normalizedReview = TagSuggestionValidator.normalizedTag(input.reviewText)
        for rule in reviewRules where rule.keywords.contains(where: { normalizedReview.contains($0) }) {
            candidates.append(rule.tag)
        }

        let albumContext = TagSuggestionValidator.normalizedTag(
            [input.albumTitle, input.artistName, input.genreName ?? ""].joined(separator: " ")
        )
        for rule in albumRules where rule.keywords.contains(where: { albumContext.contains($0) }) {
            candidates.append(rule.tag)
        }

        if let releaseYear = input.releaseYear {
            if releaseYear < 1990 {
                candidates.append("classic")
            } else if releaseYear >= 2020 {
                candidates.append("modern")
            }
        }

        return TagSuggestionValidator.validatedTags(candidates, input: input)
    }

    private static let reviewRules: [TagSuggestionRule] = [
        TagSuggestionRule(tag: "late night", keywords: ["late night", "night", "midnight"]),
        TagSuggestionRule(tag: "vocals", keywords: ["vocal", "vocals", "voice", "singer"]),
        TagSuggestionRule(tag: "lyrics", keywords: ["lyric", "lyrics", "writing", "storytelling"]),
        TagSuggestionRule(tag: "repeat", keywords: ["repeat", "replay", "addictive", "again"]),
        TagSuggestionRule(tag: "warm", keywords: ["warm", "cozy", "gentle"]),
        TagSuggestionRule(tag: "moody", keywords: ["moody", "dark", "melancholy", "sad"]),
        TagSuggestionRule(tag: "energetic", keywords: ["energy", "energetic", "intense", "aggressive"]),
        TagSuggestionRule(tag: "polished", keywords: ["polished", "glossy", "clean"]),
        TagSuggestionRule(tag: "raw", keywords: ["raw", "rough", "lo-fi", "lo fi"]),
        TagSuggestionRule(tag: "experimental", keywords: ["experimental", "weird", "unpredictable"]),
        TagSuggestionRule(tag: "lush", keywords: ["lush", "layered", "dense"]),
        TagSuggestionRule(tag: "catchy", keywords: ["catchy", "hook", "hooks"])
    ]

    private static let albumRules: [TagSuggestionRule] = [
        TagSuggestionRule(tag: "r&b", keywords: ["r&b", "rnb", "soul"]),
        TagSuggestionRule(tag: "hip-hop", keywords: ["hip-hop", "hip hop", "rap"]),
        TagSuggestionRule(tag: "indie", keywords: ["indie", "alternative"]),
        TagSuggestionRule(tag: "electronic", keywords: ["electronic", "dance"]),
        TagSuggestionRule(tag: "rock", keywords: ["rock"]),
        TagSuggestionRule(tag: "pop", keywords: ["pop"]),
        TagSuggestionRule(tag: "folk", keywords: ["folk", "singer-songwriter"]),
        TagSuggestionRule(tag: "jazz", keywords: ["jazz"])
    ]
}

private struct TagSuggestionRule {
    let tag: String
    let keywords: [String]
}
