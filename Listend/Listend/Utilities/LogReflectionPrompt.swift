//
//  LogReflectionPrompt.swift
//  Listend
//

import Foundation

struct LogReflectionPrompt: Identifiable, Equatable {
    let id: String
    let chipTitle: String
    let insertionText: String

    static let chips: [LogReflectionPrompt] = [
        LogReflectionPrompt(id: "standout", chipTitle: "What stood out?", insertionText: "What stood out: "),
        LogReflectionPrompt(id: "moment", chipTitle: "Favorite moment?", insertionText: "Favorite moment: "),
        LogReflectionPrompt(id: "feel", chipTitle: "How did it feel?", insertionText: "How it felt: "),
        LogReflectionPrompt(id: "didntWork", chipTitle: "What didn't work?", insertionText: "What didn't work: "),
        LogReflectionPrompt(id: "replay", chipTitle: "Would you replay it?", insertionText: "Replay value: ")
    ]
}

enum LogReflectionPromptInserter {
    nonisolated static func insert(_ insertionText: String, into reviewText: String) -> String {
        let trimmedStarter = insertionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedStarter.isEmpty else {
            return reviewText
        }

        if reviewText.range(of: trimmedStarter, options: .caseInsensitive) != nil {
            return reviewText
        }

        if reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return insertionText
        }

        if reviewText.hasSuffix("\n") {
            return reviewText + insertionText
        }

        return reviewText + "\n" + insertionText
    }
}
