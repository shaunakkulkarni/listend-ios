//
//  LogEntryEditorView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI
import SwiftData

struct LogEntryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SoundPrintProfileRefreshCoordinator.self) private var soundPrintRefreshCoordinator
    @Query(sort: \Album.title) private var albums: [Album]

    private let log: LogEntry?
    private let soundPrintProvider: SoundPrintProvider

    @State private var selectedAlbumID: UUID?
    @State private var rating: Double?
    @State private var reviewText: String
    @State private var tagsText: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(
        log: LogEntry? = nil,
        preselectedAlbum: Album? = nil,
        soundPrintProvider: SoundPrintProvider = MockSoundPrintProvider()
    ) {
        self.log = log
        self.soundPrintProvider = soundPrintProvider
        _selectedAlbumID = State(initialValue: log?.album?.id ?? preselectedAlbum?.id)
        _rating = State(initialValue: log?.rating)
        _reviewText = State(initialValue: log?.reviewText ?? "")
        _tagsText = State(initialValue: log?.tags.joined(separator: ", ") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Album") {
                    Picker("Album", selection: $selectedAlbumID) {
                        Text("Select album")
                            .tag(UUID?.none)

                        ForEach(albums) { album in
                            Text(albumLabel(for: album))
                                .tag(UUID?.some(album.id))
                        }
                    }
                    .disabled(log != nil)
                    .accessibilityIdentifier("albumPicker")
                }

                Section("Rating") {
                    RatingPickerView(rating: $rating)
                }

                Section("Review") {
                    TextEditor(text: $reviewText)
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("reviewTextEditor")
                }

                Section("Tags") {
                    TextField("warm, late night, repeat", text: $tagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("tagsTextField")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(log == nil ? "New Log" : "Edit Log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await saveLog()
                        }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("saveLogButton")
                }
            }
        }
    }

    private var canSave: Bool {
        selectedAlbumID != nil && rating != nil
    }

    private func albumLabel(for album: Album) -> String {
        if let releaseYear = album.releaseYear {
            return "\(album.title) - \(album.artistName) (\(releaseYear))"
        }

        return "\(album.title) - \(album.artistName)"
    }

    @MainActor
    private func saveLog() async {
        guard let selectedAlbumID, let album = albums.first(where: { $0.id == selectedAlbumID }) else {
            errorMessage = "Choose an album."
            return
        }

        guard let rating else {
            errorMessage = "Choose a rating."
            return
        }

        isSaving = true
        defer {
            isSaving = false
        }

        let trimmedReview = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedTags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        do {
            let savedLog: LogEntry

            if let log {
                log.album = album
                log.rating = rating
                log.reviewText = trimmedReview
                log.tags = parsedTags
                log.updatedAt = Date()
                savedLog = log
            } else {
                let now = Date()
                let newLog = LogEntry(
                    album: album,
                    rating: rating,
                    reviewText: trimmedReview,
                    tags: parsedTags,
                    loggedAt: now,
                    updatedAt: now
                )
                modelContext.insert(newLog)
                savedLog = newLog
            }

            try modelContext.save()
            try await LogSentimentUpdater(provider: soundPrintProvider).updateSentiment(for: savedLog, in: modelContext)
            await soundPrintRefreshCoordinator.refreshProfile(in: modelContext, provider: soundPrintProvider)
            dismiss()
        } catch {
            errorMessage = "Could not save log."
        }
    }
}

#Preview {
    LogEntryEditorView()
        .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self, SoundPrintPersona.self, Recommendation.self, RecommendationReceipt.self, RecommendationFeedback.self], inMemory: true)
        .environment(SoundPrintProfileRefreshCoordinator())
}
