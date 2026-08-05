//
//  String+SoundPrintText.swift
//  Listend
//

import Foundation

extension String {
    var trimmedForSoundPrint: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count > 96 else {
            return trimmed
        }

        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 96)
        return String(trimmed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    var normalizedSoundPrintText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
    }

    var normalizedSoundPrintWords: [String] {
        normalizedSoundPrintText
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func containsNormalizedSoundPrintPhrase(_ phrase: String) -> Bool {
        let normalizedPhrase = phrase.normalizedSoundPrintText
        return contains(normalizedPhrase)
    }

    var firstSoundPrintPhrase: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        let firstSentence = soundPrintSentences.first ?? trimmed

        guard firstSentence.count > 64 else {
            return firstSentence
        }

        let endIndex = firstSentence.index(firstSentence.startIndex, offsetBy: 64)
        return String(firstSentence[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Splits on `.`/`!`/`?` and drops empty fragments, giving a rough sentence count/list
    /// that's good enough for enforcing "exactly 2 sentences" style persona rules.
    var soundPrintSentences: [String] {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return []
        }

        let separators = CharacterSet(charactersIn: ".!?")
        return trimmed
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var soundPrintParagraphs: [String] {
        let normalizedNewlines = replacingOccurrences(of: "\r\n", with: "\n")

        return normalizedNewlines
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
