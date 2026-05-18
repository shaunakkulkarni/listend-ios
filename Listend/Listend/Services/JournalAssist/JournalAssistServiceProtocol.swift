//
//  JournalAssistServiceProtocol.swift
//  Listend
//
//  Created by Codex on 5/18/26.
//

import Foundation

struct JournalAssistPrompt: Equatable, Identifiable {
    let id: String
    let question: String

    static let defaults: [JournalAssistPrompt] = [
        JournalAssistPrompt(id: "standout", question: "What stood out most?"),
        JournalAssistPrompt(id: "mood", question: "What mood did it leave you in?"),
        JournalAssistPrompt(id: "replay", question: "Would you replay it?"),
        JournalAssistPrompt(id: "moment", question: "Any favorite or weaker moments?")
    ]
}

struct JournalAssistPromptAnswer: Equatable, Identifiable {
    let promptID: String
    let question: String
    var answer: String

    var id: String { promptID }
}

struct JournalAssistInput: Equatable {
    let albumTitle: String
    let artistName: String
    let genreName: String?
    let releaseYear: Int?
    let rating: Double?
    let notes: String
    let promptAnswers: [JournalAssistPromptAnswer]
    let existingReviewText: String
    let existingTags: [String]

    init(
        albumTitle: String,
        artistName: String,
        genreName: String? = nil,
        releaseYear: Int? = nil,
        rating: Double? = nil,
        notes: String = "",
        promptAnswers: [JournalAssistPromptAnswer] = [],
        existingReviewText: String = "",
        existingTags: [String] = []
    ) {
        self.albumTitle = albumTitle
        self.artistName = artistName
        self.genreName = genreName
        self.releaseYear = releaseYear
        self.rating = rating
        self.notes = notes
        self.promptAnswers = promptAnswers
        self.existingReviewText = existingReviewText
        self.existingTags = existingTags
    }

    init(
        album: Album,
        rating: Double?,
        notes: String = "",
        promptAnswers: [JournalAssistPromptAnswer] = [],
        existingReviewText: String = "",
        existingTags: [String] = []
    ) {
        self.init(
            albumTitle: album.title,
            artistName: album.artistName,
            genreName: album.genreName,
            releaseYear: album.releaseYear,
            rating: rating,
            notes: notes,
            promptAnswers: promptAnswers,
            existingReviewText: existingReviewText,
            existingTags: existingTags
        )
    }

    var hasMeaningfulUserInput: Bool {
        rating != nil
            || !notes.trimmedForJournalAssist.isEmpty
            || !existingReviewText.trimmedForJournalAssist.isEmpty
            || !existingTags.isEmpty
            || promptAnswers.contains { !$0.answer.trimmedForJournalAssist.isEmpty }
    }
}

struct JournalAssistDraftResult: Equatable {
    let draftReview: String?
    let prompts: [JournalAssistPrompt]

    static func needsInput(prompts: [JournalAssistPrompt] = JournalAssistPrompt.defaults) -> JournalAssistDraftResult {
        JournalAssistDraftResult(draftReview: nil, prompts: prompts)
    }

    static func draft(_ text: String) -> JournalAssistDraftResult {
        JournalAssistDraftResult(draftReview: text, prompts: [])
    }
}

protocol JournalAssistServiceProtocol {
    var reflectionPrompts: [JournalAssistPrompt] { get }

    func draftReview(for input: JournalAssistInput) async throws -> JournalAssistDraftResult
    func suggestedTags(for input: JournalAssistInput) async throws -> [String]
}

enum JournalAssistServiceError: Error, Equatable {
    case unavailable
    case emptyOutput
    case malformedOutput
    case validationFailed
}

extension String {
    var trimmedForJournalAssist: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
