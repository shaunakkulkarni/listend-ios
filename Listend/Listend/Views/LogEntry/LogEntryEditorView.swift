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
    @Environment(\.albumTrackService) private var environmentAlbumTrackService
    @Environment(SoundPrintProfileRefreshCoordinator.self) private var soundPrintRefreshCoordinator
    @Query(sort: \Album.title) private var albums: [Album]

    private let log: LogEntry?
    private let preselectedAlbum: Album?
    private let injectedSoundPrintProvider: SoundPrintProvider?
    private let injectedJournalAssistService: JournalAssistServiceProtocol?
    private let injectedAlbumTrackService: AlbumTrackServiceProtocol?

    @State private var selectedAlbumID: UUID?
    @State private var rating: Double?
    @State private var reviewText: String
    @State private var tagsText: String
    @State private var favoriteTracksText: String
    @State private var lessFavoriteTracksText: String
    @State private var standoutMomentText: String
    @State private var isTrackHighlightsExpanded: Bool
    @State private var trackCandidates: [AlbumTrackCandidate] = []
    @State private var trackSelection = AlbumTrackSelectionState()
    @State private var isLoadingTracklist = false
    @State private var hasLoadedTracklist = false
    @State private var loadedTracklistAlbumID: UUID?
    @State private var suggestedTags: [String] = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var activeAssistMode: JournalAssistMode?
    @FocusState private var focusedField: EditorField?

    init(
        log: LogEntry? = nil,
        preselectedAlbum: Album? = nil,
        soundPrintProvider: SoundPrintProvider? = nil,
        journalAssistService: JournalAssistServiceProtocol? = nil,
        albumTrackService: AlbumTrackServiceProtocol? = nil
    ) {
        self.log = log
        self.preselectedAlbum = preselectedAlbum
        injectedSoundPrintProvider = soundPrintProvider
        injectedJournalAssistService = journalAssistService
        injectedAlbumTrackService = albumTrackService
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
                        .focused($focusedField, equals: .review)
                        .accessibilityIdentifier("reviewTextEditor")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Need a nudge?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(LogReflectionPrompt.chips) { prompt in
                                    Button {
                                        insertReflectionPrompt(prompt)
                                    } label: {
                                        Text(prompt.chipTitle)
                                    }
                                    .accessibilityLabel(prompt.chipTitle)
                                    .accessibilityHint("Inserts a reflection starter into your review")
                                    .accessibilityIdentifier("reflectionPromptChip-\(prompt.id)")
                                }

                                Button {
                                    activeAssistMode = .helpWrite
                                } label: {
                                    Label("Help me write", systemImage: "sparkles")
                                }
                                .accessibilityIdentifier("helpMeWriteButton")
                                .disabled(selectedAlbum == nil)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .scrollClipDisabled()
                    }
                }

                Section("Tags") {
                    TextField("warm, late night, repeat", text: $tagsText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .tags)
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

                    Button {
                        activeAssistMode = .suggestTags
                    } label: {
                        Label("Suggest tags", systemImage: "tag")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("journalSuggestTagsButton")
                    .disabled(selectedAlbum == nil)
                }

                Section {
                    Button {
                        withAnimation {
                            isTrackHighlightsExpanded.toggle()
                        }
                        if isTrackHighlightsExpanded {
                            Task {
                                await loadTracklistIfNeeded()
                            }
                        }
                    } label: {
                        Label("Track Highlights", systemImage: "music.note.list")
                    }
                    .accessibilityIdentifier("trackHighlightsDisclosure")

                    if isTrackHighlightsExpanded {
                        if isLoadingTracklist {
                            Label("Loading tracklist...", systemImage: "music.note")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("tracklistLoadingText")
                        }

                        if !trackCandidates.isEmpty {
                            AlbumTrackSelectionView(
                                title: "Favorite tracks",
                                systemImage: "star",
                                tracks: trackCandidates,
                                selection: $trackSelection,
                                kind: .favorite
                            )

                            AlbumTrackSelectionView(
                                title: "Skips / weaker tracks",
                                systemImage: "minus.circle",
                                tracks: trackCandidates,
                                selection: $trackSelection,
                                kind: .skip
                            )
                        }

                        if shouldShowManualTrackFields {
                            if hasLoadedTracklist && trackCandidates.isEmpty {
                                Text("Tracklist unavailable. You can still add tracks manually.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("tracklistUnavailableText")
                            }

                            TextField("Snooze, Good Days", text: $favoriteTracksText)
                                .textInputAutocapitalization(.words)
                                .focused($focusedField, equals: .favoriteTracks)
                                .accessibilityIdentifier("favoriteTracksTextField")

                            TextField("Less favorite tracks", text: $lessFavoriteTracksText)
                                .textInputAutocapitalization(.words)
                                .focused($focusedField, equals: .lessFavoriteTracks)
                                .accessibilityIdentifier("lessFavoriteTracksTextField")
                        }

                        TextField("One short note", text: $standoutMomentText, axis: .vertical)
                            .lineLimit(1...3)
                            .focused($focusedField, equals: .standoutMoment)
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
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Color.listendPaper)
            .safeAreaInset(edge: .bottom) {
                if focusedField != nil {
                    Color.clear
                        .frame(height: 72)
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

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .task(id: tagSuggestionInput) {
                await refreshTagSuggestions()
            }
            .task(id: trackListTaskID) {
                await loadTracklistIfNeeded()
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

    private var albumTrackService: AlbumTrackServiceProtocol {
        injectedAlbumTrackService ?? environmentAlbumTrackService
    }

    private var trackListTaskID: String {
        "\(selectedAlbum?.id.uuidString ?? "none")-\(isTrackHighlightsExpanded)"
    }

    private var shouldShowManualTrackFields: Bool {
        trackCandidates.isEmpty
            || !favoriteTracksText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !lessFavoriteTracksText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        ListTextNormalizer.parsedTags(from: tagsText)
    }

    private enum EditorField: Hashable {
        case review
        case tags
        case favoriteTracks
        case lessFavoriteTracks
        case standoutMoment
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

    @MainActor
    private func loadTracklistIfNeeded() async {
        guard isTrackHighlightsExpanded, let selectedAlbum else {
            return
        }

        guard loadedTracklistAlbumID != selectedAlbum.id else {
            return
        }

        isLoadingTracklist = true
        hasLoadedTracklist = false
        defer {
            isLoadingTracklist = false
            hasLoadedTracklist = true
            loadedTracklistAlbumID = selectedAlbum.id
        }

        do {
            let tracks = try await albumTrackService.tracks(for: selectedAlbum, in: modelContext)
            trackCandidates = tracks.sortedForAlbumDisplay()
            applySavedTrackSelectionIfNeeded()
        } catch {
            trackCandidates = []
        }
    }

    private func applySavedTrackSelectionIfNeeded() {
        guard !trackCandidates.isEmpty else {
            return
        }

        let unmatched = trackSelection.applySavedTracks(
            favorites: ListTextNormalizer.parsedTrackNames(from: favoriteTracksText),
            skips: ListTextNormalizer.parsedTrackNames(from: lessFavoriteTracksText),
            candidates: trackCandidates
        )
        favoriteTracksText = unmatched.favoriteManual.joined(separator: ", ")
        lessFavoriteTracksText = unmatched.skipManual.joined(separator: ", ")
    }

    private func insertReflectionPrompt(_ prompt: LogReflectionPrompt) {
        reviewText = LogReflectionPromptInserter.insert(prompt.insertionText, into: reviewText)
        focusedField = .review
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
        let favoriteTracksToSave = trackCandidates.isEmpty
            ? ListTextNormalizer.parsedTrackNames(from: favoriteTracksText)
            : trackSelection.savedFavoriteTrackTitles(from: trackCandidates, manualText: favoriteTracksText)
        let lessFavoriteTracksToSave = trackCandidates.isEmpty
            ? ListTextNormalizer.parsedTrackNames(from: lessFavoriteTracksText)
            : trackSelection.savedSkipTrackTitles(from: trackCandidates, manualText: lessFavoriteTracksText)
        let standoutMomentToSave = ListTextNormalizer.normalizedOptionalText(standoutMomentText)

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

}

#Preview {
    LogEntryEditorView()
        .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self, SoundPrintPersona.self, Recommendation.self, RecommendationReceipt.self, RecommendationFeedback.self, RecentlyPlayedAlbumSnapshot.self, AppleMusicRecentPlaySnapshot.self, AlbumTrack.self, TasteAvoidanceSignal.self], inMemory: true)
        .environment(SoundPrintProfileRefreshCoordinator())
}

private struct AlbumContextRow: View {
    let album: Album

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AlbumArtworkView(artworkURL: album.artworkURL, size: 56, albumTitle: album.title)

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
        }
        .accessibilityIdentifier("selectedAlbumSummary")
    }
}

private enum AlbumTrackSelectionKind {
    case favorite
    case skip
}

private struct AlbumTrackSelectionView: View {
    let title: String
    let systemImage: String
    let tracks: [AlbumTrackCandidate]
    @Binding var selection: AlbumTrackSelectionState
    let kind: AlbumTrackSelectionKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))

            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(tracks.sortedForAlbumDisplay()) { track in
                    Button {
                        toggle(track)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isSelected(track) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected(track) ? Color.listendAccent : .secondary)

                            Text(trackLabel(track))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel(for: track))
                    .accessibilityValue(isSelected(track) ? "Selected" : "Not selected")
                    .accessibilityIdentifier("\(accessibilityPrefix)-\(track.accessibilityID)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var accessibilityPrefix: String {
        switch kind {
        case .favorite:
            return "favoriteTrackOption"
        case .skip:
            return "skipTrackOption"
        }
    }

    private func isSelected(_ track: AlbumTrackCandidate) -> Bool {
        switch kind {
        case .favorite:
            return selection.isFavorite(track)
        case .skip:
            return selection.isSkip(track)
        }
    }

    private func toggle(_ track: AlbumTrackCandidate) {
        switch kind {
        case .favorite:
            selection.toggleFavorite(track)
        case .skip:
            selection.toggleSkip(track)
        }
    }

    private func trackLabel(_ track: AlbumTrackCandidate) -> String {
        if let trackNumber = track.trackNumber {
            return "\(trackNumber). \(track.title)"
        }

        return track.title
    }

    private func accessibilityLabel(for track: AlbumTrackCandidate) -> String {
        switch kind {
        case .favorite:
            return "Favorite track \(track.title)"
        case .skip:
            return "Skip track \(track.title)"
        }
    }
}
