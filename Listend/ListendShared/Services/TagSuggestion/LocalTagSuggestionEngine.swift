//
//  LocalTagSuggestionEngine.swift
//  Listend
//

import Foundation

struct LocalTagSuggestionEngine {
    nonisolated static func suggestions(
        albumTitle: String,
        artistName: String,
        genreName: String?,
        releaseYear: Int?,
        reviewText: String,
        existingTags: [String]
    ) -> [String] {
        var candidates: [String] = []

        if let genreName {
            candidates.append(genreName)
        }

        let normalizedReview = normalized(reviewText)
        for rule in reviewRules where rule.keywords.contains(where: normalizedReview.contains) {
            candidates.append(rule.tag)
        }

        let albumContext = normalized([albumTitle, artistName, genreName ?? ""].joined(separator: " "))
        for rule in albumRules where rule.keywords.contains(where: albumContext.contains) {
            candidates.append(rule.tag)
        }

        if let releaseYear {
            if releaseYear < 1990 {
                candidates.append("classic")
            } else if releaseYear >= 2020 {
                candidates.append("modern")
            }
        }

        let blocked = Set([normalized(albumTitle), normalized(artistName)])
        var seen = Set(existingTags.map(normalized))
        var result: [String] = []

        for candidate in candidates {
            let tag = normalized(candidate)
            guard !tag.isEmpty,
                  tag.count <= 28,
                  tag.rangeOfCharacter(from: .letters) != nil,
                  !blocked.contains(tag),
                  !seen.contains(tag) else {
                continue
            }

            seen.insert(tag)
            result.append(tag)
            if result.count == 6 { break }
        }

        return result
    }

    nonisolated static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static let reviewRules = [
        Rule(tag: "late night", keywords: ["late night", "night", "midnight"]),
        Rule(tag: "vocals", keywords: ["vocal", "vocals", "voice", "singer"]),
        Rule(tag: "lyrics", keywords: ["lyric", "lyrics", "writing", "storytelling"]),
        Rule(tag: "repeat", keywords: ["repeat", "replay", "addictive", "again"]),
        Rule(tag: "warm", keywords: ["warm", "cozy", "gentle"]),
        Rule(tag: "moody", keywords: ["moody", "dark", "melancholy", "sad"]),
        Rule(tag: "energetic", keywords: ["energy", "energetic", "intense", "aggressive"]),
        Rule(tag: "polished", keywords: ["polished", "glossy", "clean"]),
        Rule(tag: "raw", keywords: ["raw", "rough", "lo-fi", "lo fi"]),
        Rule(tag: "experimental", keywords: ["experimental", "weird", "unpredictable"]),
        Rule(tag: "lush", keywords: ["lush", "layered", "dense"]),
        Rule(tag: "catchy", keywords: ["catchy", "hook", "hooks"])
    ]

    private static let albumRules = [
        Rule(tag: "r&b", keywords: ["r&b", "rnb", "soul"]),
        Rule(tag: "hip-hop", keywords: ["hip-hop", "hip hop", "rap"]),
        Rule(tag: "indie", keywords: ["indie", "alternative"]),
        Rule(tag: "electronic", keywords: ["electronic", "dance"]),
        Rule(tag: "rock", keywords: ["rock"]),
        Rule(tag: "pop", keywords: ["pop"]),
        Rule(tag: "folk", keywords: ["folk", "singer-songwriter"]),
        Rule(tag: "jazz", keywords: ["jazz"])
    ]
}

private struct Rule {
    let tag: String
    let keywords: [String]
}
