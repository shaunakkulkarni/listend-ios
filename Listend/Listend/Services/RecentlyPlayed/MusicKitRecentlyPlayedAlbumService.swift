//
//  MusicKitRecentlyPlayedAlbumService.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

import Foundation

#if canImport(MusicKit)
import MusicKit
#endif

enum MusicKitRecentlyPlayedAlbumError: Error, Equatable {
    case unavailable
    case unauthorized
    case unusableResponse
}

struct MusicKitRecentlyPlayedAlbumMetadata: Equatable {
    let id: String
    let title: String
    let artistName: String
    let releaseDate: Date?
    let genreNames: [String]
    let artworkURL: URL?
}

struct MusicKitRecentlyPlayedAlbumMapper {
    static func albumSearchResult(from metadata: MusicKitRecentlyPlayedAlbumMetadata) -> AlbumSearchResult? {
        let trimmedTitle = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedArtistName = metadata.artistName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !metadata.id.isEmpty, !trimmedTitle.isEmpty, !trimmedArtistName.isEmpty else {
            return nil
        }

        return AlbumSearchResult(
            id: metadata.id,
            title: trimmedTitle,
            artistName: trimmedArtistName,
            releaseYear: metadata.releaseDate.map { Calendar.current.component(.year, from: $0) },
            genreName: metadata.genreNames.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            artworkURL: metadata.artworkURL?.absoluteString
        )
    }
}

#if canImport(MusicKit)
struct MusicKitRecentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol {
    private let limit: Int

    init(limit: Int = 10) {
        self.limit = limit
    }

    func recentlyPlayedAlbums() async throws -> [AlbumSearchResult] {
        try await ensureAuthorized()

        var request = MusicRecentlyPlayedContainerRequest()
        request.limit = limit

        let response = try await request.response()
        try Task.checkCancellation()

        let albums = response.items.compactMap { item in
            switch item {
            case .album(let album):
                return MusicKitRecentlyPlayedAlbumMapper.albumSearchResult(from: Self.metadata(from: album))
            default:
                return nil
            }
        }

        guard !albums.isEmpty else {
            throw MusicKitRecentlyPlayedAlbumError.unusableResponse
        }

        return albums.uniquedByCatalogID()
    }

    private func ensureAuthorized() async throws {
        switch MusicAuthorization.currentStatus {
        case .authorized:
            return
        case .notDetermined:
            let status = await MusicAuthorization.request()

            guard status == .authorized else {
                throw MusicKitRecentlyPlayedAlbumError.unauthorized
            }
        case .denied, .restricted:
            throw MusicKitRecentlyPlayedAlbumError.unauthorized
        @unknown default:
            throw MusicKitRecentlyPlayedAlbumError.unavailable
        }
    }

    private static func metadata(from album: MusicKit.Album) -> MusicKitRecentlyPlayedAlbumMetadata {
        MusicKitRecentlyPlayedAlbumMetadata(
            id: album.id.rawValue,
            title: album.title,
            artistName: album.artistName,
            releaseDate: album.releaseDate,
            genreNames: album.genreNames,
            artworkURL: album.artwork?.url(width: 300, height: 300)
        )
    }
}
#else
struct MusicKitRecentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol {
    func recentlyPlayedAlbums() async throws -> [AlbumSearchResult] {
        throw MusicKitRecentlyPlayedAlbumError.unavailable
    }
}
#endif

private extension Array where Element == AlbumSearchResult {
    func uniquedByCatalogID() -> [AlbumSearchResult] {
        var seenCatalogIDs: Set<String> = []

        return filter { album in
            seenCatalogIDs.insert(album.catalogID).inserted
        }
    }
}
