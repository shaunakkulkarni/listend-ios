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
    @Environment(\.soundPrintProvider) private var environmentSoundPrintProvider
    @Environment(\.tagSuggestionProvider) private var environmentTagSuggestionProvider
    @Environment(SoundPrintProfileRefreshCoordinator.self) private var soundPrintRefreshCoordinator
    @Query(sort: \Album.title) private var albums: [Album]

    private let log: LogEntry?
    private let preselectedAlbum: Album?
    private let injectedSoundPrintProvider: SoundPrintProvider?
    private let injectedTagSuggestionProvider: TagSuggestionProvider?

    @State private var selectedAlbumID: UUID?
    @State private var rating: Double?
    @State private var reviewText: String
    @State private var tagsText: String
    @State private var suggestedTags: [String] = []
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(
        log: LogEntry? = nil,
        preselectedAlbum: Album? = nil,
        soundPrintProvider: SoundPrintProvider? = nil,
        tagSuggestionProvider: TagSuggestionProvider? = nil
    ) {
        self.log = log
        self.preselectedAlbum = preselectedAlbum
        injectedSoundPrintProvider = soundPrintProvider
        injectedTagSuggestionProvider = tagSuggestionProvider
        _selectedAlbumID = State(initialValue: log?.album?.id ?? preselectedAlbum?.id)
        _rating = State(initialValue: log?.rating)
        _reviewText = State(initialValue: log?.reviewText ?? "")
        _tagsText = State(initialValue: log?.tags.joined(separator: ", ") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Album") {
                    if let selectedAlbum {
                        AlbumContextRow(album: selectedAlbum)
                    } else {
                        ContentUnavailableView(
                            "No Album Selected",
                            systemImage: "music.note",
                            description: Text("Choose an album before writing a log.")
                        )
                    }
                }

                Section("Rating") {
                    StarRatingControl(
                        rating: Binding(
                            get: { rating ?? 0.5 },
                            set: { rating = $0 }
                        ),
                        showsEmptyState: rating == nil
                    )
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

                    if !suggestedTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestedTags, id: \.self) { tag in
                                    Button {
                                        appendSuggestedTag(tag)
                                    } label: {
                                        Text(tag)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .accessibilityIdentifier("suggestedTag-\(accessibilityID(for: tag))")
                                }
                            }
                        }
                        .scrollClipDisabled()
                    }
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
            .task(id: tagSuggestionInput) {
                await refreshTagSuggestions()
            }
        }
    }

    private var canSave: Bool {
        selectedAlbum != nil && rating != nil
    }

    private var soundPrintProvider: SoundPrintProvider {
        injectedSoundPrintProvider ?? environmentSoundPrintProvider
    }

    private var tagSuggestionProvider: TagSuggestionProvider {
        injectedTagSuggestionProvider ?? environmentTagSuggestionProvider
    }

    private var availableAlbums: [Album] {
        guard let preselectedAlbum, !albums.contains(where: { $0.id == preselectedAlbum.id }) else {
            return albums
        }

        return ([preselectedAlbum] + albums).sorted { $0.title < $1.title }
    }

    private var selectedAlbum: Album? {
        guard let selectedAlbumID else {
            return nil
        }

        return availableAlbums.first { $0.id == selectedAlbumID }
    }

    private var parsedTags: [String] {
        TagSuggestionValidator.parsedTags(from: tagsText)
    }

    private var tagSuggestionInput: TagSuggestionInput? {
        guard let selectedAlbum else {
            return nil
        }

        return TagSuggestionInput(
            album: selectedAlbum,
            reviewText: reviewText,
            existingTags: parsedTags
        )
    }

    private func albumLabel(for album: Album) -> String {
        if let releaseYear = album.releaseYear {
            return "\(album.title) - \(album.artistName) (\(releaseYear))"
        }

        return "\(album.title) - \(album.artistName)"
    }

    @MainActor
    private func refreshTagSuggestions() async {
        guard let input = tagSuggestionInput else {
            suggestedTags = []
            return
        }

        let localTags = LocalTagSuggestionProvider.suggestedTags(for: input)
        suggestedTags = localTags

        do {
            try await Task.sleep(for: .milliseconds(350))
            let refinedTags = try await tagSuggestionProvider.suggestedTags(for: input)

            guard !Task.isCancelled else {
                return
            }

            suggestedTags = refinedTags.isEmpty ? localTags : refinedTags
        } catch is CancellationError {
            return
        } catch {
            suggestedTags = localTags
        }
    }

    private func appendSuggestedTag(_ tag: String) {
        let displayTag = TagSuggestionValidator.displayTag(from: tag)
        guard !displayTag.isEmpty else {
            return
        }

        let existingTags = parsedTags
        let existingNormalizedTags = Set(existingTags.map(TagSuggestionValidator.normalizedTag))
        guard !existingNormalizedTags.contains(TagSuggestionValidator.normalizedTag(displayTag)) else {
            return
        }

        let updatedTags = existingTags + [displayTag]
        tagsText = updatedTags.joined(separator: ", ")
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

    @MainActor
    private func saveLog() async {
        guard let album = selectedAlbum else {
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
        let tagsToSave = parsedTags

        do {
            let savedLog: LogEntry

            if let log {
                log.album = album
                log.rating = rating
                log.reviewText = trimmedReview
                log.tags = tagsToSave
                log.updatedAt = Date()
                savedLog = log
            } else {
                let now = Date()
                let newLog = LogEntry(
                    album: album,
                    rating: rating,
                    reviewText: trimmedReview,
                    tags: tagsToSave,
                    loggedAt: now,
                    updatedAt: now
                )
                modelContext.insert(newLog)
                savedLog = newLog
            }

            try modelContext.save()
            dismiss()
            Task { @MainActor in
                await soundPrintRefreshCoordinator.processSavedLog(
                    savedLog,
                    in: modelContext,
                    provider: soundPrintProvider
                )
            }
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

private struct AlbumContextRow: View {
    let album: Album

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(album.title)
                .font(.headline)

            Text(album.artistName)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if let releaseYear = album.releaseYear {
                    Text(String(releaseYear))
                }

                if let genreName = album.genreName {
                    Text(genreName)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("selectedAlbumSummary")
    }
}
