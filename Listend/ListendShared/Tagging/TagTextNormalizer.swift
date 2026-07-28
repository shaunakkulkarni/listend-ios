//
//  TagTextNormalizer.swift
//  Listend
//

import Foundation

nonisolated enum TagTextNormalizer {
    private nonisolated static let comparisonLocale = Locale(identifier: "en_US_POSIX")
    private nonisolated static let dashVariants = [
        "\u{2010}", // hyphen
        "\u{2011}", // non-breaking hyphen
        "\u{2012}", // figure dash
        "\u{2013}", // en dash
        "\u{2014}", // em dash
        "\u{2015}", // horizontal bar
        "\u{2212}"  // minus sign
    ]

    nonisolated static func displayValue(_ value: String) -> String {
        collapsedWhitespace(in: value)
    }

    nonisolated static func comparisonKey(_ value: String) -> String {
        var normalized = displayValue(value)
            .decomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: comparisonLocale
            )
            .lowercased(with: comparisonLocale)

        for dash in dashVariants {
            normalized = normalized.replacingOccurrences(of: dash, with: "-")
        }

        return collapsedWhitespace(in: normalized)
    }

    private nonisolated static func collapsedWhitespace(in value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
