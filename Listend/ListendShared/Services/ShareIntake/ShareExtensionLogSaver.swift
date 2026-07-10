//
//  ShareExtensionLogSaver.swift
//  Listend
//

import Foundation
import SwiftData

enum ShareExtensionAlbumDraft {
    case resolved(AlbumSearchResult)
    case manual(title: String, artistName: String, releaseYear: Int?, genreName: String?)
}

struct ShareExtensionLogDraft {
    let album: ShareExtensionAlbumDraft
    let rating: Double
    let reviewText: String
    let tagsText: String
    let favoriteTracksText: String
    let skipTracksText: String
    let standoutMomentText: String
}

enum ShareExtensionLogSaveError: Error {
    case missingAlbum
}

enum ShareExtensionLogSaver {
    @MainActor
    static func save(_ draft: ShareExtensionLogDraft, in modelContext: ModelContext) throws -> LogEntry {
        let album = try album(for: draft.album, in: modelContext)
        let now = Date()
        let log = LogEntry(
            album: album,
            rating: draft.rating,
            reviewText: draft.reviewText.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: ListTextNormalizer.parsedTags(from: draft.tagsText),
            favoriteTracks: ListTextNormalizer.parsedTrackNames(from: draft.favoriteTracksText),
            skipTracks: ListTextNormalizer.parsedTrackNames(from: draft.skipTracksText),
            standoutMoment: ListTextNormalizer.normalizedOptionalText(draft.standoutMomentText),
            loggedAt: now,
            updatedAt: now
        )

        modelContext.insert(log)
        try modelContext.save()
        return log
    }

    @MainActor
    private static func album(for draft: ShareExtensionAlbumDraft, in modelContext: ModelContext) throws -> Album {
        let albums = try modelContext.fetch(FetchDescriptor<Album>())

        switch draft {
        case .resolved(let result):
            return try AlbumCacheUpserter.upsertAlbum(from: result, cachedAlbums: albums, in: modelContext)
        case .manual(let title, let artistName, let releaseYear, let genreName):
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedArtist = artistName.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedTitle.isEmpty, !trimmedArtist.isEmpty else {
                throw ShareExtensionLogSaveError.missingAlbum
            }

            if let existing = albums.first(where: { album in
                album.title.normalizedAlbumMatchText == trimmedTitle.normalizedAlbumMatchText
                    && album.artistName.normalizedAlbumMatchText == trimmedArtist.normalizedAlbumMatchText
            }) {
                return existing
            }

            let album = Album(
                title: trimmedTitle,
                artistName: trimmedArtist,
                releaseYear: releaseYear,
                genreName: ListTextNormalizer.normalizedOptionalText(genreName)
            )
            modelContext.insert(album)
            try modelContext.save()
            return album
        }
    }
}
