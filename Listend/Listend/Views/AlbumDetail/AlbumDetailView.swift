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
                VStack(alignment: .center, spacing: 16) {
                    AlbumArtworkView(artworkURL: album.artworkURL, size: 200, albumTitle: album.title)

                    VStack(alignment: .center, spacing: 6) {
                        Text(album.title)
                            .font(.system(.title2, design: .serif).weight(.semibold))
                            .multilineTextAlignment(.center)

                        Text(album.artistName)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        AlbumMetadataView(album: album)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Preview") {
                AlbumPreviewControl(lookup: AlbumPreviewLookup(album: album))
            }

            Section {
                if isAlreadyLogged {
                    Label("Already logged", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        startLog()
                    } label: {
                        Text("Log this album")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("logThisAlbumButton")
                }
            }
            .listRowBackground(Color.clear)

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.listendPaper)
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
    .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self, SoundPrintPersona.self, Recommendation.self, RecommendationReceipt.self, RecommendationFeedback.self, RecentlyPlayedAlbumSnapshot.self, AppleMusicRecentPlaySnapshot.self], inMemory: true)
}
