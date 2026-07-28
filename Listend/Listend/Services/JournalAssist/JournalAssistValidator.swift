//
//  JournalAssistValidator.swift
//  Listend
//
//  Created by Codex on 5/18/26.
//

import Foundation

enum JournalAssistValidator {
    nonisolated static func validatedDraft(_ draft: String, input: JournalAssistInput) throws -> String {
        let trimmed = draft.trimmedForJournalAssist

        guard !trimmed.isEmpty else {
            throw JournalAssistServiceError.emptyOutput
        }

        guard sentenceCount(in: trimmed) <= 4 else {
            throw JournalAssistServiceError.validationFailed
        }

        guard !containsUnsupportedGenericHype(trimmed, input: input) else {
            throw JournalAssistServiceError.validationFailed
        }

        guard !containsUnsupportedOpinion(in: trimmed, input: input) else {
            throw JournalAssistServiceError.validationFailed
        }

        return trimmed
    }

    nonisolated static func validatedTags(_ tags: [String], input: JournalAssistInput) -> [String] {
        let tagInput = TagSuggestionInput(
            albumTitle: input.albumTitle,
            artistName: input.artistName,
            genreName: input.genreName,
            releaseYear: input.releaseYear,
            reviewText: [input.existingReviewText, input.notes, input.promptAnswers.map(\.answer).joined(separator: " ")]
                .joined(separator: " "),
            existingTags: input.existingTags + input.selectedReactionDisplayNames
        )

        return TagSuggestionValidator.validatedTags(tags, input: tagInput)
            .filter { $0.split(separator: " ").count <= 3 }
    }

    nonisolated static func applyDraft(_ draft: String, to reviewText: String) -> String {
        draft.trimmedForJournalAssist
    }

    nonisolated static func dismissDraft(currentReviewText: String) -> String {
        currentReviewText
    }

    nonisolated static func hasMeaningfulInput(_ input: JournalAssistInput) -> Bool {
        input.hasMeaningfulUserInput
    }

    private nonisolated static func sentenceCount(in text: String) -> Int {
        let matches = text.matches(of: /[^.!?]+[.!?]*/)
        let count = matches
            .map { String(text[$0.range]).trimmedForJournalAssist }
            .filter { !$0.isEmpty }
            .count

        return max(count, text.isEmpty ? 0 : 1)
    }

    private nonisolated static func containsUnsupportedGenericHype(
        _ text: String,
        input: JournalAssistInput
    ) -> Bool {
        let normalized = TagSuggestionValidator.normalizedTag(text)
        let selectedReactionKeys = Set(
            input.selectedReactionDisplayNames.map {
                TagSuggestionValidator.normalizedTag($0)
            }
        )

        return genericHypePhrases.contains { phrase in
            normalized.contains(phrase) && !selectedReactionKeys.contains(phrase)
        }
    }

    private nonisolated static func containsUnsupportedOpinion(in draft: String, input: JournalAssistInput) -> Bool {
        let normalizedDraft = TagSuggestionValidator.normalizedTag(draft)
        let supportText = supportedSourceText(for: input)
        let normalizedSupport = TagSuggestionValidator.normalizedTag(supportText)

        return guardedOpinionWords.contains { word in
            normalizedDraft.contains(word) && !isOpinionSupported(word, supportText: normalizedSupport, rating: input.rating)
        }
    }

    private nonisolated static func supportedSourceText(for input: JournalAssistInput) -> String {
        let promptAnswerText = input.promptAnswers.map(\.answer).joined(separator: " ")
        return [
            input.notes,
            promptAnswerText,
            input.existingReviewText,
            input.existingTags.joined(separator: " "),
            input.selectedReactionDisplayNames.joined(separator: " "),
            input.genreName ?? "",
            input.releaseYear.map(String.init) ?? ""
        ]
        .joined(separator: " ")
    }

    private nonisolated static func isOpinionSupported(_ word: String, supportText: String, rating: Double?) -> Bool {
        if supportText.contains(word) {
            return true
        }

        if positiveOpinionWords.contains(word), let rating, rating >= 4.0 {
            return true
        }

        if negativeOpinionWords.contains(word), let rating, rating <= 2.0 {
            return true
        }

        return false
    }

    private static let genericHypePhrases = [
        "masterpiece",
        "instant classic",
        "must listen",
        "must-listen",
        "album of the year",
        "no skips",
        "flawless",
        "perfect album",
        "changed my life",
        "best album ever",
        "everyone should hear"
    ]

    private static let positiveOpinionWords = [
        "love",
        "loved",
        "favorite",
        "beautiful",
        "amazing",
        "incredible",
        "great",
        "catchy",
        "warm",
        "repeat",
        "replay"
    ]

    private static let negativeOpinionWords = [
        "hate",
        "hated",
        "boring",
        "weak",
        "annoying",
        "forgettable",
        "disappointing",
        "overrated"
    ]

    private static let guardedOpinionWords = positiveOpinionWords + negativeOpinionWords
}
