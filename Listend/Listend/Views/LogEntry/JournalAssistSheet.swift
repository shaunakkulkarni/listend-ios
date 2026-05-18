//
//  JournalAssistSheet.swift
//  Listend
//
//  Created by Codex on 5/18/26.
//

import SwiftUI

enum JournalAssistMode: String, Identifiable {
    case helpWrite
    case draftReview
    case suggestTags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .helpWrite:
            return "Help Me Write"
        case .draftReview:
            return "Draft Review"
        case .suggestTags:
            return "Suggest Tags"
        }
    }
}

struct JournalAssistSheet: View {
    @Environment(\.dismiss) private var dismiss

    let mode: JournalAssistMode
    let album: Album
    let rating: Double?
    let existingReviewText: String
    let existingTags: [String]
    let service: JournalAssistServiceProtocol
    let onAcceptDraft: (String) -> Void
    let onAcceptTag: (String) -> Void

    @State private var notes: String = ""
    @State private var promptAnswers: [JournalAssistPromptAnswer]
    @State private var draftReview: String?
    @State private var suggestedTags: [String] = []
    @State private var feedbackMessage: String?
    @State private var isWorking = false

    init(
        mode: JournalAssistMode,
        album: Album,
        rating: Double?,
        existingReviewText: String,
        existingTags: [String],
        service: JournalAssistServiceProtocol,
        onAcceptDraft: @escaping (String) -> Void,
        onAcceptTag: @escaping (String) -> Void
    ) {
        self.mode = mode
        self.album = album
        self.rating = rating
        self.existingReviewText = existingReviewText
        self.existingTags = existingTags
        self.service = service
        self.onAcceptDraft = onAcceptDraft
        self.onAcceptTag = onAcceptTag
        _promptAnswers = State(initialValue: service.reflectionPrompts.map {
            JournalAssistPromptAnswer(promptID: $0.id, question: $0.question, answer: "")
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                promptSection
                notesSection
                actionSection
                resultSection

                if let feedbackMessage {
                    Section {
                        Text(feedbackMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(mode.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var promptSection: some View {
        Section("Reflection Prompts") {
            ForEach($promptAnswers) { $answer in
                TextField(answer.question, text: $answer.answer, axis: .vertical)
                    .lineLimit(1...3)
                    .accessibilityIdentifier("journalAssistPrompt-\(answer.promptID)")
            }
        }
    }

    private var notesSection: some View {
        Section("Quick Notes") {
            TextEditor(text: $notes)
                .frame(minHeight: 90)
                .accessibilityIdentifier("journalAssistNotesEditor")
        }
    }

    private var actionSection: some View {
        Section {
            switch mode {
            case .helpWrite:
                Button {
                    Task {
                        await generateDraft()
                    }
                } label: {
                    Label("Generate Draft", systemImage: "text.bubble")
                }
                .disabled(isWorking)
                .accessibilityIdentifier("helpWriteGenerateJournalDraftButton")

                Button {
                    Task {
                        await generateTags()
                    }
                } label: {
                    Label("Suggest Tags", systemImage: "tag")
                }
                .disabled(isWorking)
                .accessibilityIdentifier("helpWriteGenerateJournalTagsButton")
            case .draftReview:
                Button {
                    Task {
                        await generateDraft()
                    }
                } label: {
                    Label("Generate Draft", systemImage: "text.bubble")
                }
                .disabled(isWorking)
                .accessibilityIdentifier("generateJournalDraftButton")
            case .suggestTags:
                Button {
                    Task {
                        await generateTags()
                    }
                } label: {
                    Label("Suggest Tags", systemImage: "tag")
                }
                .disabled(isWorking)
                .accessibilityIdentifier("generateJournalTagsButton")
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let draftReview {
            Section("Draft") {
                TextEditor(text: Binding(
                    get: { draftReview },
                    set: { self.draftReview = $0 }
                ))
                .frame(minHeight: 110)
                .accessibilityIdentifier("journalAssistDraftEditor")

                Button {
                    acceptDraft()
                } label: {
                    Label("Use Draft", systemImage: "checkmark.circle")
                }
                .accessibilityIdentifier("acceptJournalDraftButton")
            }
        }

        if !suggestedTags.isEmpty {
            Section("AI Tag Suggestions") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedTags, id: \.self) { tag in
                            Button {
                                onAcceptTag(tag)
                            } label: {
                                Text(tag)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("journalAssistTag-\(accessibilityID(for: tag))")
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    @MainActor
    private func generateDraft() async {
        isWorking = true
        feedbackMessage = nil
        defer {
            isWorking = false
        }

        do {
            let result = try await service.draftReview(for: input)
            if let draft = result.draftReview {
                draftReview = draft
                feedbackMessage = nil
            } else {
                draftReview = nil
                feedbackMessage = "Add a rating, notes, prompt answers, review text, or tags before generating a draft."
            }
        } catch {
            feedbackMessage = "Journal Assist could not draft this right now. You can keep writing manually."
        }
    }

    @MainActor
    private func generateTags() async {
        isWorking = true
        feedbackMessage = nil
        defer {
            isWorking = false
        }

        do {
            suggestedTags = try await service.suggestedTags(for: input)
            if suggestedTags.isEmpty {
                feedbackMessage = "Add a little more detail before asking for AI tag suggestions."
            }
        } catch {
            feedbackMessage = "Journal Assist could not suggest tags right now. Manual tags still work."
        }
    }

    private var input: JournalAssistInput {
        JournalAssistInput(
            album: album,
            rating: rating,
            notes: notes,
            promptAnswers: promptAnswers,
            existingReviewText: existingReviewText,
            existingTags: existingTags
        )
    }

    private func acceptDraft() {
        guard let draftReview else {
            return
        }

        onAcceptDraft(draftReview)
        dismiss()
    }

    private func accessibilityID(for tag: String) -> String {
        TagSuggestionValidator.normalizedTag(tag)
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" {
                    result.append(character)
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
