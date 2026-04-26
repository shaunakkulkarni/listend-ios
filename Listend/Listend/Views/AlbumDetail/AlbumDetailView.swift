//
//  AlbumDetailView.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

import SwiftUI
import SwiftData

struct AlbumDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Album.title) private var albums: [Album]
    @Query(sort: \LogEntry.loggedAt, order: .reverse) private var logs: [LogEntry]

    let album: AlbumSearchResult

    @State private var albumForLog: Album?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    ArtworkPlaceholder(size: 120)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(album.title)
                            .font(.title2.weight(.bold))

                        Text(album.artistName)
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        AlbumMetadataView(album: album)
                    }
                }
                .padding(.vertical, 8)
            }

            Section {
                if isAlreadyLogged {
                    Label("Already logged", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Log this album") {
                        startLog()
                    }
                    .fontWeight(.semibold)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Album")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $albumForLog) { album in
            LogEntryEditorView(preselectedAlbum: album)
        }
    }

    private var isAlreadyLogged: Bool {
        logs.contains { log in
            guard let loggedAlbum = log.album else {
                return false
            }

            return matchesCatalogID(loggedAlbum) || matchesTitleAndArtist(loggedAlbum)
        }
    }

    private func startLog() {
        do {
            albumForLog = try upsertAlbum()
        } catch {
            errorMessage = "Could not prepare this album for logging."
        }
    }

    private func upsertAlbum() throws -> Album {
        if let catalogMatch = albums.first(where: matchesCatalogID) {
            updateCachedAlbum(catalogMatch)
            try modelContext.save()
            return catalogMatch
        }

        if let titleMatch = albums.first(where: matchesTitleAndArtist) {
            updateCachedAlbum(titleMatch)
            try modelContext.save()
            return titleMatch
        }

        let cachedAlbum = Album(
            appleMusicID: album.catalogID,
            title: album.title,
            artistName: album.artistName,
            releaseYear: album.releaseYear,
            genreName: album.genreName,
            cachedAt: Date()
        )
        modelContext.insert(cachedAlbum)
        try modelContext.save()
        return cachedAlbum
    }

    private func updateCachedAlbum(_ cachedAlbum: Album) {
        if cachedAlbum.appleMusicID == nil {
            cachedAlbum.appleMusicID = album.catalogID
        }

        cachedAlbum.title = album.title
        cachedAlbum.artistName = album.artistName
        cachedAlbum.releaseYear = album.releaseYear
        cachedAlbum.genreName = album.genreName
        cachedAlbum.cachedAt = Date()
    }

    private func matchesCatalogID(_ cachedAlbum: Album) -> Bool {
        cachedAlbum.appleMusicID == album.catalogID
    }

    private func matchesTitleAndArtist(_ cachedAlbum: Album) -> Bool {
        cachedAlbum.title.normalizedAlbumMatchText == album.title.normalizedAlbumMatchText
            && cachedAlbum.artistName.normalizedAlbumMatchText == album.artistName.normalizedAlbumMatchText
    }
}

private struct ArtworkPlaceholder: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.14))

            Image(systemName: "record.circle")
                .font(.system(size: size * 0.42))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Album artwork placeholder")
    }
}

private struct AlbumMetadataView: View {
    let album: AlbumSearchResult

    var body: some View {
        HStack(spacing: 8) {
            if let releaseYear = album.releaseYear {
                Text(String(releaseYear))
            }

            if let genreName = album.genreName {
                Text(genreName)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

private extension String {
    var normalizedAlbumMatchText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    NavigationStack {
        AlbumDetailView(album: MockAlbumCatalogService.defaultAlbums[0])
    }
    .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self], inMemory: true)
}
