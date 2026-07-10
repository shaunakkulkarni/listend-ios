//
//  AlbumCacheUpserter.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

import Foundation
import SwiftData

enum AlbumCacheUpserter {
    @MainActor
    static func upsertAlbum(
        from result: AlbumSearchResult,
        cachedAlbums: [Album],
        in modelContext: ModelContext
    ) throws -> Album {
        if let catalogMatch = cachedAlbums.first(where: { $0.appleMusicID == result.catalogID }) {
            update(catalogMatch, from: result)
            try modelContext.save()
            return catalogMatch
        }

        if let titleMatch = cachedAlbums.first(where: { album in
            album.title.normalizedAlbumMatchText == result.title.normalizedAlbumMatchText
                && album.artistName.normalizedAlbumMatchText == result.artistName.normalizedAlbumMatchText
        }) {
            update(titleMatch, from: result)
            try modelContext.save()
            return titleMatch
        }

        let cachedAlbum = Album(
            appleMusicID: result.catalogID,
            title: result.title,
            artistName: result.artistName,
            releaseYear: result.releaseYear,
            genreName: result.genreName,
            artworkURL: result.artworkURL,
            cachedAt: Date()
        )
        modelContext.insert(cachedAlbum)
        try modelContext.save()
        return cachedAlbum
    }

    private static func update(_ album: Album, from result: AlbumSearchResult) {
        if album.appleMusicID == nil {
            album.appleMusicID = result.catalogID
        }

        album.title = result.title
        album.artistName = result.artistName
        album.releaseYear = result.releaseYear
        album.genreName = result.genreName
        album.artworkURL = result.artworkURL
        album.cachedAt = Date()
    }
}

extension String {
    var normalizedAlbumMatchText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
