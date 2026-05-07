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
                    AlbumArtworkView(artworkURL: album.artworkURL, size: 120)

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

            Section("Preview") {
                AlbumPreviewControl(lookup: AlbumPreviewLookup(album: album))
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
                    .accessibilityIdentifier("logThisAlbumButton")
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
            albumForLog = try AlbumCacheUpserter.upsertAlbum(
                from: album,
                cachedAlbums: albums,
                in: modelContext
            )
        } catch {
            errorMessage = "Could not prepare this album for logging."
        }
    }

    private func matchesCatalogID(_ cachedAlbum: Album) -> Bool {
        cachedAlbum.appleMusicID == album.catalogID
    }

    private func matchesTitleAndArtist(_ cachedAlbum: Album) -> Bool {
        cachedAlbum.title.normalizedAlbumMatchText == album.title.normalizedAlbumMatchText
            && cachedAlbum.artistName.normalizedAlbumMatchText == album.artistName.normalizedAlbumMatchText
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

#Preview {
    NavigationStack {
        AlbumDetailView(album: MockAlbumCatalogService.defaultAlbums[0])
    }
    .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self, SoundPrintPersona.self, Recommendation.self, RecommendationReceipt.self, RecommendationFeedback.self], inMemory: true)
}
