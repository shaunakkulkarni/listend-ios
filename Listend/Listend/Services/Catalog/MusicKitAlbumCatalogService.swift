//
//  MusicKitAlbumCatalogService.swift
//  Listend
//
//  Created by Codex on 5/3/26.
//

import Foundation

#if canImport(MusicKit)
import MusicKit
#endif

enum MusicKitAlbumCatalogError: Error, Equatable {
    case unavailable
    case unauthorized
    case unusableResponse
}

struct MusicKitAlbumMetadata: Equatable {
    let id: String
    let title: String
    let artistName: String
    let releaseDate: Date?
    let genreNames: [String]
    let artworkURL: URL?
}

struct MusicKitAlbumMapper {
    static func albumSearchResult(from metadata: MusicKitAlbumMetadata) -> AlbumSearchResult? {
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
struct MusicKitAlbumCatalogService: AlbumCatalogServiceProtocol {
    private let limit: Int

    init(limit: Int = 25) {
        self.limit = limit
    }

    func searchAlbums(query: String) async throws -> [AlbumSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            return []
        }

        try await ensureAuthorized()

        var request = MusicCatalogSearchRequest(term: trimmedQuery, types: [MusicKit.Album.self])
        request.limit = limit

        let response = try await request.response()
        try Task.checkCancellation()

        let albums = response.albums.compactMap { album in
            MusicKitAlbumMapper.albumSearchResult(from: Self.metadata(from: album))
        }

        guard !albums.isEmpty else {
            throw MusicKitAlbumCatalogError.unusableResponse
        }

        return albums
    }

    func albumDetails(id: String) async throws -> AlbumSearchResult? {
        try await ensureAuthorized()

        let request = MusicCatalogResourceRequest<MusicKit.Album>(matching: \.id, equalTo: MusicItemID(id))
        let response = try await request.response()
        try Task.checkCancellation()

        return response.items.first.flatMap { album in
            MusicKitAlbumMapper.albumSearchResult(from: Self.metadata(from: album))
        }
    }

    private func ensureAuthorized() async throws {
        switch MusicAuthorization.currentStatus {
        case .authorized:
            return
        case .notDetermined:
            let status = await MusicAuthorization.request()

            guard status == .authorized else {
                throw MusicKitAlbumCatalogError.unauthorized
            }
        case .denied, .restricted:
            throw MusicKitAlbumCatalogError.unauthorized
        @unknown default:
            throw MusicKitAlbumCatalogError.unavailable
        }
    }

    private static func metadata(from album: MusicKit.Album) -> MusicKitAlbumMetadata {
        MusicKitAlbumMetadata(
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
struct MusicKitAlbumCatalogService: AlbumCatalogServiceProtocol {
    func searchAlbums(query: String) async throws -> [AlbumSearchResult] {
        throw MusicKitAlbumCatalogError.unavailable
    }

    func albumDetails(id: String) async throws -> AlbumSearchResult? {
        throw MusicKitAlbumCatalogError.unavailable
    }
}
#endif
