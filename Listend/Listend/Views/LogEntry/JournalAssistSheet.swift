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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .helpWrite:
            return "Help Me Write"
        case .draftReview:
            return "Draft Review"
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

    @State private var notes: String = ""
    @State private var isShowingPrompts = false
    @State private var promptAnswers: [JournalAssistPromptAnswer]
    @State private var draftReview: String?
    @State private var feedbackMessage: String?
    @State private var isWorking = false

    init(
        mode: JournalAssistMode,
        album: Album,
        rating: Double?,
        existingReviewText: String,
        existingTags: [String],
        service: JournalAssistServiceProtocol,
        onAcceptDraft: @escaping (String) -> Void
    ) {
        self.mode = mode
        self.album = album
        self.rating = rating
        self.existingReviewText = existingReviewText
        self.existingTags = existingTags
        self.service = service
        self.onAcceptDraft = onAcceptDraft
        _promptAnswers = State(initialValue: service.reflectionPrompts.map {
            JournalAssistPromptAnswer(promptID: $0.id, question: $0.question, answer: "")
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                notesSection
                promptSection
                actionSection
                resultSection

                if let feedbackMessage {
                    Section {
                        Text(feedbackMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.listendPaper)
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
        Section {
            DisclosureGroup("Reflection Prompts (optional)", isExpanded: $isShowingPrompts) {
                ForEach($promptAnswers) { $answer in
                    TextField(answer.question, text: $answer.answer, axis: .vertical)
                        .lineLimit(1...3)
                        .accessibilityIdentifier("journalAssistPrompt-\(answer.promptID)")
                }
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
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("acceptJournalDraftButton")
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
                feedbackMessage = "Add a rating, notes, prompt answers, a thought, or reactions before generating a draft."
            }
        } catch {
            feedbackMessage = "Journal Assist could not draft this right now. You can keep writing manually."
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
}
