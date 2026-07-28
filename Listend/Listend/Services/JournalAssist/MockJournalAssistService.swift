//
//  MockJournalAssistService.swift
//  Listend
//
//  Created by Codex on 5/18/26.
//

import Foundation

struct MockJournalAssistService: JournalAssistServiceProtocol {
    let reflectionPrompts: [JournalAssistPrompt]

    init(reflectionPrompts: [JournalAssistPrompt] = JournalAssistPrompt.defaults) {
        self.reflectionPrompts = reflectionPrompts
    }

    func draftReview(for input: JournalAssistInput) async throws -> JournalAssistDraftResult {
        guard input.hasMeaningfulUserInput else {
            return .needsInput(prompts: reflectionPrompts)
        }

        let draft = Self.draftReviewText(for: input)
        return .draft(try JournalAssistValidator.validatedDraft(draft, input: input))
    }

    func suggestedTags(for input: JournalAssistInput) async throws -> [String] {
        Self.suggestedTags(for: input)
    }

    nonisolated static func draftReviewText(for input: JournalAssistInput) -> String {
        let ratingText = input.rating.map {
            "I rated \(input.albumTitle) by \(input.artistName) \($0.formatted(.number.precision(.fractionLength(1))))/5."
        } ?? "I spent time with \(input.albumTitle) by \(input.artistName)."
        let cues = strongestCues(for: input)
        let selectedReactions = selectedReactionDisplayNames(for: input)

        guard !cues.isEmpty || !selectedReactions.isEmpty else {
            return ratingText
        }

        guard !selectedReactions.isEmpty else {
            return "\(ratingText) My notes point to \(cues.joined(separator: ", "))."
        }

        let reactionText = selectedReactions.joined(separator: ", ")
        guard !cues.isEmpty else {
            return "\(ratingText) The reactions I chose were \(reactionText)."
        }

        return "\(ratingText) My notes point to \(cues.joined(separator: ", ")); the reactions I chose were \(reactionText)."
    }

    nonisolated static func suggestedTags(for input: JournalAssistInput) -> [String] {
        var candidates: [String] = []

        let text = [
            input.notes,
            input.existingReviewText,
            input.promptAnswers.map(\.answer).joined(separator: " ")
        ]
        .joined(separator: " ")
        let normalized = TagSuggestionValidator.normalizedTag(text)

        for rule in tagRules where rule.keywords.contains(where: { normalized.contains($0) }) {
            candidates.append(rule.tag)
        }

        if let genreName = input.genreName {
            candidates.append(genreName)
        }

        if let rating = input.rating {
            if rating >= 4.0 {
                candidates.append("repeat")
            } else if rating <= 2.0 {
                candidates.append("not for me")
            }
        }

        return JournalAssistValidator.validatedTags(candidates, input: input)
    }

    private nonisolated static func strongestCues(for input: JournalAssistInput) -> [String] {
        let selectedReactionKeys = Set(
            selectedReactionDisplayNames(for: input).map {
                TagSuggestionValidator.normalizedTag($0)
            }
        )
        let rawCues = [
            input.notes,
            input.promptAnswers.map(\.answer).joined(separator: " "),
            input.existingReviewText,
            input.existingTags.joined(separator: ", ")
        ]
        .flatMap { value in
            value
                .split(whereSeparator: { $0 == "." || $0 == "," || $0 == "\n" })
                .map { String($0).trimmedForJournalAssist }
        }
        .filter { cue in
            !cue.isEmpty
                && !selectedReactionKeys.contains(TagSuggestionValidator.normalizedTag(cue))
        }

        return Array(rawCues.prefix(2))
    }

    private nonisolated static func selectedReactionDisplayNames(for input: JournalAssistInput) -> [String] {
        var seen = Set<String>()

        return input.selectedReactionDisplayNames.compactMap { value in
            let displayValue = value.trimmedForJournalAssist
            let key = TagSuggestionValidator.normalizedTag(displayValue)
            guard !displayValue.isEmpty, seen.insert(key).inserted else {
                return nil
            }

            return displayValue
        }
    }

    private static let tagRules: [JournalAssistTagRule] = [
        JournalAssistTagRule(tag: "late night", keywords: ["late night", "night", "midnight"]),
        JournalAssistTagRule(tag: "vocals", keywords: ["vocal", "vocals", "voice"]),
        JournalAssistTagRule(tag: "lyrics", keywords: ["lyric", "lyrics", "writing"]),
        JournalAssistTagRule(tag: "warm", keywords: ["warm", "cozy", "gentle"]),
        JournalAssistTagRule(tag: "moody", keywords: ["moody", "dark", "melancholy"]),
        JournalAssistTagRule(tag: "energetic", keywords: ["energy", "energetic", "intense"]),
        JournalAssistTagRule(tag: "raw", keywords: ["raw", "rough", "lo-fi", "lo fi"]),
        JournalAssistTagRule(tag: "catchy", keywords: ["catchy", "hook", "hooks"]),
        JournalAssistTagRule(tag: "replay", keywords: ["replay", "repeat", "again"])
    ]
}

private struct JournalAssistTagRule {
    let tag: String
    let keywords: [String]
}
