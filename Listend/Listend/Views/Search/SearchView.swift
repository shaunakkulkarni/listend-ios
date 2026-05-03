//
//  SearchView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI

struct SearchView: View {
    private let catalogService: AlbumCatalogServiceProtocol

    @State private var query = ""
    @State private var results: [AlbumSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    init(catalogService: AlbumCatalogServiceProtocol = MockAlbumCatalogService()) {
        self.catalogService = catalogService
    }

    var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                ContentUnavailableView(
                    "Search Albums",
                    systemImage: "magnifyingglass",
                    description: Text("Search by album, artist, or genre.")
                )
            } else if isSearching {
                ProgressView("Searching")
            } else if let errorMessage {
                ContentUnavailableView(
                    "Search Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if results.isEmpty {
                ContentUnavailableView(
                    "No Albums Found",
                    systemImage: "magnifyingglass",
                    description: Text("Try another album, artist, or genre.")
                )
            } else {
                List(results) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                    } label: {
                        AlbumSearchResultRow(album: album)
                    }
                    .accessibilityIdentifier("albumSearchResult-\(album.catalogID)")
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Album, artist, or genre")
        .task(id: trimmedQuery) {
            await searchAlbums(for: trimmedQuery)
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func searchAlbums(for query: String) async {
        guard !query.isEmpty else {
            results = []
            isSearching = false
            errorMessage = nil
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            let searchResults = try await catalogService.searchAlbums(query: query)
            try Task.checkCancellation()
            guard query == trimmedQuery else {
                return
            }

            results = searchResults
            isSearching = false
        } catch is CancellationError {
            if query == trimmedQuery {
                isSearching = false
            }
        } catch {
            guard query == trimmedQuery else {
                return
            }

            results = []
            isSearching = false
            errorMessage = "Could not search albums right now. Try another search."
        }
    }
}

private struct AlbumSearchResultRow: View {
    let album: AlbumSearchResult

    var body: some View {
        HStack(spacing: 12) {
            ArtworkThumbnail(artworkURL: album.artworkURL)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(album.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                metadata
            }
        }
        .padding(.vertical, 4)
    }

    private var metadata: some View {
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

private struct ArtworkThumbnail: View {
    let artworkURL: String?

    var body: some View {
        AlbumArtworkView(artworkURL: artworkURL, size: 56)
        .frame(width: 56, height: 56)
    }
}

struct AlbumArtworkView: View {
    let artworkURL: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                            .overlay {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Album artwork")
    }

    private var url: URL? {
        artworkURL.flatMap(URL.init(string:))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.14))

            Image(systemName: "record.circle")
                .font(.system(size: size * 0.42))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
}
