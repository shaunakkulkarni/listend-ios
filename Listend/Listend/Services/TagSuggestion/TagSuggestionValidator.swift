//
//  TagSuggestionValidator.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

import Foundation

enum TagSuggestionValidator {
    nonisolated static let maximumSuggestionCount = 6

    nonisolated static func validatedTags(_ tags: [String], input: TagSuggestionInput) -> [String] {
        var seen = Set(input.existingTags.map(normalizedTag))
        let blocked = [
            normalizedTag(input.albumTitle),
            normalizedTag(input.artistName)
        ]
        var suggestions: [String] = []

        for tag in tags {
            let displayTag = displayTag(from: tag)
            let normalized = normalizedTag(displayTag)

            guard isValid(displayTag, normalized: normalized, blockedTags: blocked) else {
                continue
            }

            guard !seen.contains(normalized) else {
                continue
            }

            seen.insert(normalized)
            suggestions.append(displayTag)

            if suggestions.count == maximumSuggestionCount {
                break
            }
        }

        return suggestions
    }

    nonisolated static func parsedTags(from text: String) -> [String] {
        text
            .split(separator: ",")
            .map { displayTag(from: String($0)) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func normalizedTag(_ tag: String) -> String {
        tag
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    nonisolated static func displayTag(from tag: String) -> String {
        normalizedTag(tag)
    }

    private nonisolated static func isValid(_ tag: String, normalized: String, blockedTags: [String]) -> Bool {
        guard !tag.isEmpty, tag.count <= 28 else {
            return false
        }

        guard !tag.contains(","), !tag.contains("\n") else {
            return false
        }

        guard !blockedTags.contains(normalized) else {
            return false
        }

        return normalized.rangeOfCharacter(from: .letters) != nil
    }
}
