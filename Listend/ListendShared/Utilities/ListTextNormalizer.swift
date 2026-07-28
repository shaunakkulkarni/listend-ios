//
//  ListTextNormalizer.swift
//  Listend
//
//  Created by Codex on 6/30/26.
//

import Foundation

enum ListTextNormalizer {
    enum ListKind {
        case tags
        case trackNames
    }

    nonisolated static func normalizedTags(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var normalizedValues: [String] = []

        for value in values {
            let displayValue = displayTag(from: value)
            guard !displayValue.isEmpty else {
                continue
            }

            let key = normalizedTag(displayValue)
            guard !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            normalizedValues.append(displayValue)
        }

        return normalizedValues
    }

    nonisolated static func parsedTags(from text: String) -> [String] {
        normalizedTags(text.components(separatedBy: ","))
    }

    nonisolated static func normalizedTrackNames(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var normalizedValues: [String] = []

        for value in values {
            let displayValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayValue.isEmpty else {
                continue
            }

            let key = normalizedTrackNameKey(displayValue)
            guard !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            normalizedValues.append(displayValue)
        }

        return normalizedValues
    }

    nonisolated static func parsedTrackNames(from text: String) -> [String] {
        normalizedTrackNames(text.components(separatedBy: ","))
    }

    nonisolated static func normalizedOptionalText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func encodedStringArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return json
    }

    nonisolated static func decodedStringArray(from rawValue: String?) -> [String]? {
        guard let rawValue else {
            return nil
        }

        let trimmedRawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmedRawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }

        return decoded
    }

    nonisolated static func decodedStringArrayOrLegacyCommaList(from rawValue: String?, kind: ListKind) -> [String] {
        guard let rawValue else {
            return []
        }

        if let decoded = decodedStringArray(from: rawValue) {
            return normalizedValues(decoded, kind: kind)
        }

        if rawValue.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            return []
        }

        switch kind {
        case .tags:
            return parsedTags(from: rawValue)
        case .trackNames:
            return parsedTrackNames(from: rawValue)
        }
    }

    private nonisolated static func normalizedValues(_ values: [String], kind: ListKind) -> [String] {
        switch kind {
        case .tags:
            return normalizedTags(values)
        case .trackNames:
            return normalizedTrackNames(values)
        }
    }

    private nonisolated static func normalizedTag(_ tag: String) -> String {
        TagTextNormalizer.comparisonKey(tag)
    }

    private nonisolated static func displayTag(from tag: String) -> String {
        TagTextNormalizer.displayValue(tag)
    }

    private nonisolated static func normalizedTrackNameKey(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
