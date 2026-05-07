//
//  AlbumSelectionView.swift
//  Listend
//
//  Created by Codex on 5/7/26.
//

import SwiftUI
import SwiftData

enum AlbumSelectionUpserter {
    @MainActor
    static func cachedAlbum(
        from album: AlbumSearchResult,
        cachedAlbums: [Album],
        in modelContext: ModelContext
    ) throws -> Album {
        try AlbumCacheUpserter.upsertAlbum(
            from: album,
            cachedAlbums: cachedAlbums,
            in: modelContext
        )
    }
}

struct AlbumSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Album.title) private var cachedAlbums: [Album]

    private let catalogService: AlbumCatalogServiceProtocol
    private let recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol
    private let selectAlbum: (Album) -> Void

    @State private var query = ""
    @State private var searchResults: [AlbumSearchResult] = []
    @State private var recentlyPlayedAlbums: [AlbumSearchResult] = []
    @State private var isSearching = false
    @State private var isLoadingRecentlyPlayed = false
    @State private var didLoadRecentlyPlayed = false
    @State private var searchErrorMessage: String?
    @State private var recentlyPlayedErrorMessage: String?
    @State private var selectionErrorMessage: String?

    init(
        catalogService: AlbumCatalogServiceProtocol = MockAlbumCatalogService(),
        recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol = MockRecentlyPlayedAlbumService(),
        selectAlbum: @escaping (Album) -> Void
    ) {
        self.catalogService = catalogService
        self.recentlyPlayedAlbumService = recentlyPlayedAlbumService
        self.selectAlbum = selectAlbum
    }

    var body: some View {
        List {
            if let selectionErrorMessage {
                Section {
                    Text(selectionErrorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                recentlyPlayedContent
            } header: {
                HStack {
                    Text("Recently Played")
                    Spacer()
                    if didLoadRecentlyPlayed {
                        Button("Refresh") {
                            requestRecentlyPlayedAlbums()
                        }
                        .font(.caption.weight(.semibold))
                        .disabled(isLoadingRecentlyPlayed)
                    }
                }
            }

            Section(searchSectionTitle) {
                searchContent
            }
        }
        .navigationTitle("Choose Album")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .searchable(text: $query, prompt: "Album, artist, or genre")
        .task {
            await loadRecentlyPlayedAlbums()
        }
        .task(id: trimmedQuery) {
            await searchTask(for: trimmedQuery)
        }
        .accessibilityIdentifier("albumSelectionView")
    }

    @ViewBuilder
    private var recentlyPlayedContent: some View {
        if isLoadingRecentlyPlayed {
            ProgressView("Loading recently played")
        } else if let recentlyPlayedErrorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Label("Could not load recently played", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(recentlyPlayedErrorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    requestRecentlyPlayedAlbums()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("retryRecentlyPlayedAlbumsButton")
            }
            .padding(.vertical, 4)
        } else if recentlyPlayedAlbums.isEmpty {
            ContentUnavailableView(
                didLoadRecentlyPlayed ? "No Recent Albums" : "Loading Recent Albums",
                systemImage: "music.note",
                description: Text(didLoadRecentlyPlayed ? "Search Apple Music to choose an album." : "Checking Apple Music for recent albums.")
            )
        } else {
            ForEach(recentlyPlayedAlbums) { album in
                Button {
                    choose(album)
                } label: {
                    AlbumSelectionResultRow(album: album)
                }
                .accessibilityIdentifier("albumSelectionRecent-\(album.catalogID)")
            }
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if trimmedQuery.isEmpty {
            ContentUnavailableView(
                "Search Apple Music",
                systemImage: "magnifyingglass",
                description: Text("Find any album by title, artist, or genre.")
            )
        } else if isSearching {
            ProgressView("Searching")
        } else if let searchErrorMessage {
            ContentUnavailableView(
                "Search Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(searchErrorMessage)
            )
        } else if searchResults.isEmpty {
            ContentUnavailableView(
                "No Albums Found",
                systemImage: "magnifyingglass",
                description: Text("Try another album, artist, or genre.")
            )
        } else {
            ForEach(searchResults) { album in
                Button {
                    choose(album)
                } label: {
                    AlbumSelectionResultRow(album: album)
                }
                .accessibilityIdentifier("albumSelectionSearchResult-\(album.catalogID)")
            }
        }
    }

    private var searchSectionTitle: String {
        trimmedQuery.isEmpty ? "Search" : "Search Results"
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestRecentlyPlayedAlbums() {
        Task {
            await loadRecentlyPlayedAlbums()
        }
    }

    @MainActor
    private func loadRecentlyPlayedAlbums() async {
        guard !isLoadingRecentlyPlayed else {
            return
        }

        isLoadingRecentlyPlayed = true
        recentlyPlayedErrorMessage = nil

        do {
            let albums = try await recentlyPlayedAlbumService.recentlyPlayedAlbums()
            recentlyPlayedAlbums = albums
            didLoadRecentlyPlayed = true
        } catch {
            recentlyPlayedAlbums = []
            didLoadRecentlyPlayed = true
            recentlyPlayedErrorMessage = "Check Apple Music access and try again."
        }

        isLoadingRecentlyPlayed = false
    }

    private func searchTask(for query: String) async {
        guard !query.isEmpty else {
            clearSearch()
            return
        }

        prepareForDebouncedSearch()
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else {
            return
        }

        await searchAlbums(for: query)
    }

    @MainActor
    private func clearSearch() {
        searchResults = []
        isSearching = false
        searchErrorMessage = nil
    }

    @MainActor
    private func prepareForDebouncedSearch() {
        isSearching = false
        searchErrorMessage = nil
    }

    @MainActor
    private func searchAlbums(for query: String) async {
        guard query == trimmedQuery else {
            return
        }

        isSearching = true
        searchErrorMessage = nil

        do {
            try Task.checkCancellation()
            let albums = try await catalogService.searchAlbums(query: query)
            try Task.checkCancellation()
            guard query == trimmedQuery else {
                return
            }

            searchResults = albums
            isSearching = false
        } catch is CancellationError {
            if query == trimmedQuery {
                isSearching = false
            }
        } catch {
            guard query == trimmedQuery else {
                return
            }

            searchResults = []
            isSearching = false
            searchErrorMessage = "Could not search albums right now. Try another search."
        }
    }

    private func choose(_ album: AlbumSearchResult) {
        do {
            let cachedAlbum = try AlbumSelectionUpserter.cachedAlbum(
                from: album,
                cachedAlbums: cachedAlbums,
                in: modelContext
            )
            selectAlbum(cachedAlbum)
        } catch {
            selectionErrorMessage = "Could not prepare this album for logging."
        }
    }
}

private struct AlbumSelectionResultRow: View {
    let album: AlbumSearchResult

    var body: some View {
        HStack(spacing: 12) {
            AlbumArtworkView(artworkURL: album.artworkURL, size: 52)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(album.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

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
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        AlbumSelectionView { _ in }
    }
    .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self, SoundPrintPersona.self, Recommendation.self, RecommendationReceipt.self, RecommendationFeedback.self], inMemory: true)
}
