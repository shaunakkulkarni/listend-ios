//
//  RecentlyPlayedAlbumCache.swift
//  Listend
//
//  Created by Codex on 5/24/26.
//

import Foundation
import SwiftData

enum RecentlyPlayedAlbumCache {
    @MainActor
    static func cachedAlbums(in modelContext: ModelContext) throws -> [AlbumSearchResult] {
        let descriptor = FetchDescriptor<RecentlyPlayedAlbumSnapshot>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )

        return try modelContext.fetch(descriptor).map(Self.albumSearchResult)
    }

    @MainActor
    static func replaceCachedAlbums(
        with albums: [AlbumSearchResult],
        in modelContext: ModelContext
    ) throws {
        let existingSnapshots = try modelContext.fetch(FetchDescriptor<RecentlyPlayedAlbumSnapshot>())
        existingSnapshots.forEach(modelContext.delete)

        let fetchedAt = Date()
        var seenCatalogIDs: Set<String> = []
        var sortOrder = 0

        for album in albums where seenCatalogIDs.insert(album.catalogID).inserted {
            modelContext.insert(
                RecentlyPlayedAlbumSnapshot(
                    catalogID: album.catalogID,
                    title: album.title,
                    artistName: album.artistName,
                    releaseYear: album.releaseYear,
                    genreName: album.genreName,
                    artworkURL: album.artworkURL,
                    sortOrder: sortOrder,
                    fetchedAt: fetchedAt
                )
            )
            sortOrder += 1
        }

        try modelContext.save()
    }

    static func albumSearchResult(from snapshot: RecentlyPlayedAlbumSnapshot) -> AlbumSearchResult {
        AlbumSearchResult(
            id: snapshot.catalogID,
            title: snapshot.title,
            artistName: snapshot.artistName,
            releaseYear: snapshot.releaseYear,
            genreName: snapshot.genreName,
            artworkURL: snapshot.artworkURL
        )
    }
}

