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
    @Environment(\.journalAssistService) private var environmentJournalAssistService
    @Environment(SoundPrintProfileRefreshCoordinator.self) private var soundPrintRefreshCoordinator
    @Query(sort: \Album.title) private var albums: [Album]

    private let log: LogEntry?
    private let preselectedAlbum: Album?
    private let injectedSoundPrintProvider: SoundPrintProvider?
    private let injectedJournalAssistService: JournalAssistServiceProtocol?

    @State private var selectedAlbumID: UUID?
    @State private var rating: Double?
    @State private var reviewText: String
    @State private var tagsText: String
    @State private var favoriteTracksText: String
    @State private var lessFavoriteTracksText: String
    @State private var standoutMomentText: String
    @State private var isTrackHighlightsExpanded: Bool
    @State private var suggestedTags: [String] = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var activeAssistMode: JournalAssistMode?

    init(
        log: LogEntry? = nil,
        preselectedAlbum: Album? = nil,
        soundPrintProvider: SoundPrintProvider? = nil,
        journalAssistService: JournalAssistServiceProtocol? = nil
    ) {
        self.log = log
        self.preselectedAlbum = preselectedAlbum
        injectedSoundPrintProvider = soundPrintProvider
        injectedJournalAssistService = journalAssistService
        _selectedAlbumID = State(initialValue: log?.album?.id ?? preselectedAlbum?.id)
        _rating = State(initialValue: log?.rating)
        _reviewText = State(initialValue: log?.reviewText ?? "")
        _tagsText = State(initialValue: log?.tags.joined(separator: ", ") ?? "")
        _favoriteTracksText = State(initialValue: log?.favoriteTracks.joined(separator: ", ") ?? "")
        _lessFavoriteTracksText = State(initialValue: log?.skipTracks.joined(separator: ", ") ?? "")
        _standoutMomentText = State(initialValue: log?.normalizedStandoutMoment ?? "")
        _isTrackHighlightsExpanded = State(initialValue: log?.hasTrackHighlights == true)
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
                    TextField("What did this album leave with you?", text: $reviewText, axis: .vertical)
                        .lineLimit(4...8)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityIdentifier("reviewTextEditor")
                }

                Section("Journal Assist") {
                    Button {
                        activeAssistMode = .helpWrite
                    } label: {
                        Label("Help me write", systemImage: "square.and.pencil")
                    }
                    .disabled(selectedAlbum == nil)
                    .accessibilityIdentifier("helpMeWriteButton")

                    Button {
                        activeAssistMode = .draftReview
                    } label: {
                        Label("Turn my notes into a review", systemImage: "text.bubble")
                    }
                    .disabled(selectedAlbum == nil)
                    .accessibilityIdentifier("draftReviewButton")

                    Button {
                        activeAssistMode = .suggestTags
                    } label: {
                        Label("Suggest tags", systemImage: "tag")
                    }
                    .disabled(selectedAlbum == nil)
                    .accessibilityIdentifier("journalSuggestTagsButton")
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

                Section {
                    Button {
                        withAnimation {
                            isTrackHighlightsExpanded.toggle()
                        }
                    } label: {
                        Label("Track Highlights", systemImage: "music.note.list")
                    }
                    .accessibilityIdentifier("trackHighlightsDisclosure")

                    if isTrackHighlightsExpanded {
                        TextField("Snooze, Good Days", text: $favoriteTracksText)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("favoriteTracksTextField")

                        TextField("Less favorite tracks", text: $lessFavoriteTracksText)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("lessFavoriteTracksTextField")

                        TextField("One short note", text: $standoutMomentText, axis: .vertical)
                            .lineLimit(1...3)
                            .accessibilityIdentifier("standoutMomentTextField")
                    }
                } footer: {
                    Text("Optional album-level notes. No song logging required.")
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
            .sheet(item: $activeAssistMode) { mode in
                if let selectedAlbum {
                    JournalAssistSheet(
                        mode: mode,
                        album: selectedAlbum,
                        rating: rating,
                        existingReviewText: reviewText,
                        existingTags: parsedTags,
                        service: journalAssistService,
                        onAcceptDraft: acceptJournalAssistDraft,
                        onAcceptTag: appendSuggestedTag
                    )
                }
            }
        }
    }

    private var canSave: Bool {
        selectedAlbum != nil && rating != nil
    }

    private var soundPrintProvider: SoundPrintProvider {
        injectedSoundPrintProvider ?? environmentSoundPrintProvider
    }

    private var journalAssistService: JournalAssistServiceProtocol {
        injectedJournalAssistService ?? environmentJournalAssistService
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

        suggestedTags = LocalTagSuggestionProvider.suggestedTags(for: input)
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

    private func acceptJournalAssistDraft(_ draft: String) {
        reviewText = JournalAssistValidator.applyDraft(draft, to: reviewText)
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
        let favoriteTracksToSave = parsedTrackList(from: favoriteTracksText)
        let lessFavoriteTracksToSave = parsedTrackList(from: lessFavoriteTracksText)
        let standoutMomentToSave = normalizedOptionalText(standoutMomentText)

        do {
            let savedLog: LogEntry

            if let log {
                log.album = album
                log.rating = rating
                log.reviewText = trimmedReview
                log.tags = tagsToSave
                log.favoriteTracks = favoriteTracksToSave
                log.skipTracks = lessFavoriteTracksToSave
                log.standoutMoment = standoutMomentToSave
                log.updatedAt = Date()
                savedLog = log
            } else {
                let now = Date()
                let newLog = LogEntry(
                    album: album,
                    rating: rating,
                    reviewText: trimmedReview,
                    tags: tagsToSave,
                    favoriteTracks: favoriteTracksToSave,
                    skipTracks: lessFavoriteTracksToSave,
                    standoutMoment: standoutMomentToSave,
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

    private func parsedTrackList(from text: String) -> [String] {
        text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizedOptionalText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    LogEntryEditorView()
        .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self, SoundPrintPersona.self, Recommendation.self, RecommendationReceipt.self, RecommendationFeedback.self, RecentlyPlayedAlbumSnapshot.self, AppleMusicRecentPlaySnapshot.self], inMemory: true)
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
