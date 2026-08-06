//
//  AppleMusicRecommendationService.swift
//  Listend
//
//  Created by Codex on 5/28/26.
//

import Foundation

#if canImport(MusicKit)
import MusicKit
#endif

protocol AppleMusicRecommendationServiceProtocol: Sendable {
    func recommendedAlbums(limit: Int) async throws -> [AlbumSearchResult]
    func recentlyPlayedAlbums(limit: Int) async throws -> [AlbumSearchResult]
    func containsInLibrary(_ album: AlbumSearchResult) async throws -> Bool
    func relatedAlbums(for anchor: AlbumSearchResult, limit: Int) async throws -> [AlbumSearchResult]
    func similarArtistAlbums(for anchor: AlbumSearchResult, artistLimit: Int, albumLimit: Int) async throws -> [AlbumSearchResult]
    func containsArtistInLibrary(named artistName: String) async throws -> Bool
}

extension AppleMusicRecommendationServiceProtocol {
    // Defaults keep existing injectable mocks source-compatible while allowing the
    // real MusicKit implementation to opt into relationship discovery.
    func relatedAlbums(for anchor: AlbumSearchResult, limit: Int) async throws -> [AlbumSearchResult] {
        throw AppleMusicRecommendationError.unavailable
    }

    func similarArtistAlbums(for anchor: AlbumSearchResult, artistLimit: Int, albumLimit: Int) async throws -> [AlbumSearchResult] {
        throw AppleMusicRecommendationError.unavailable
    }

    func containsArtistInLibrary(named artistName: String) async throws -> Bool {
        throw AppleMusicRecommendationError.unavailable
    }
}

enum AppleMusicRecommendationError: Error, Equatable {
    case unavailable
    case unauthorized
    case unusableResponse
}

enum AppleMusicPersonalRecommendationKind {
    case album
    case playlist
    case station
}

struct AppleMusicPersonalRecommendationMetadata {
    let kind: AppleMusicPersonalRecommendationKind
    let id: String
    let title: String
    let artistName: String
    let releaseYear: Int?
    let genreName: String?
    let artworkURL: String?
}

enum AppleMusicPersonalRecommendationMapper {
    static func albumSearchResults(from metadataItems: [AppleMusicPersonalRecommendationMetadata]) -> [AlbumSearchResult] {
        metadataItems.compactMap { metadata in
            guard metadata.kind == .album else {
                return nil
            }

            let trimmedTitle = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedArtistName = metadata.artistName.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !metadata.id.isEmpty, !trimmedTitle.isEmpty, !trimmedArtistName.isEmpty else {
                return nil
            }

            return AlbumSearchResult(
                id: metadata.id,
                title: trimmedTitle,
                artistName: trimmedArtistName,
                releaseYear: metadata.releaseYear,
                genreName: metadata.genreName,
                artworkURL: metadata.artworkURL
            )
        }
        .uniquedAppleMusicRecommendations()
    }
}

#if canImport(MusicKit)
struct AppleMusicRecommendationService: AppleMusicRecommendationServiceProtocol {
    func recommendedAlbums(limit: Int = 20) async throws -> [AlbumSearchResult] {
        try await ensureAuthorized()

        var request = MusicPersonalRecommendationsRequest()
        request.limit = limit

        let response = try await request.response()
        try Task.checkCancellation()

        let metadataItems = response.recommendations.flatMap { recommendation in
            recommendation.albums.map { album in
                Self.metadata(from: album)
            }
        }
        let albums = AppleMusicPersonalRecommendationMapper.albumSearchResults(from: metadataItems)

        guard !albums.isEmpty else {
            throw AppleMusicRecommendationError.unusableResponse
        }

        return Array(albums.prefix(limit))
    }

    func recentlyPlayedAlbums(limit: Int = 20) async throws -> [AlbumSearchResult] {
        try await ensureAuthorized()

        var request = MusicRecentlyPlayedContainerRequest()
        request.limit = min(limit, 10)

        let response = try await request.response()
        try Task.checkCancellation()

        let albums = response.items.compactMap { item in
            switch item {
            case .album(let album):
                return MusicKitAlbumMapper.albumSearchResult(from: MusicKitAlbumMetadata(
                    id: album.id.rawValue,
                    title: album.title,
                    artistName: album.artistName,
                    releaseDate: album.releaseDate,
                    genreNames: album.genreNames,
                    artworkURL: album.artwork?.url(width: 300, height: 300)
                ))
            default:
                return nil
            }
        }

        return albums.uniquedAppleMusicRecommendations()
    }

    func containsInLibrary(_ album: AlbumSearchResult) async throws -> Bool {
        try await ensureAuthorized()

        var request = MusicLibrarySearchRequest(term: "\(album.title) \(album.artistName)", types: [MusicKit.Album.self])
        request.limit = 10

        let response = try await request.response()
        try Task.checkCancellation()

        return response.albums.contains { libraryAlbum in
            libraryAlbum.id.rawValue == album.catalogID
                || (libraryAlbum.title.normalizedAppleMusicFreshnessText == album.title.normalizedAppleMusicFreshnessText
                    && libraryAlbum.artistName.normalizedAppleMusicFreshnessText == album.artistName.normalizedAppleMusicFreshnessText)
        }
    }

    func relatedAlbums(for anchor: AlbumSearchResult, limit: Int) async throws -> [AlbumSearchResult] {
        try await ensureAuthorized()
        guard let album = try await catalogAlbum(for: anchor) else { return [] }
        let hydrated = try await album.with([.relatedAlbums])
        try Task.checkCancellation()
        return hydrated.relatedAlbums?.prefix(limit).compactMap { Self.searchResult(from: $0) } ?? []
    }

    func similarArtistAlbums(for anchor: AlbumSearchResult, artistLimit: Int, albumLimit: Int) async throws -> [AlbumSearchResult] {
        try await ensureAuthorized()
        guard let album = try await catalogAlbum(for: anchor) else { return [] }
        let hydratedAlbum = try await album.with([.artists])
        try Task.checkCancellation()
        guard let artist = hydratedAlbum.artists?.first(where: {
            $0.name.normalizedAppleMusicFreshnessText == anchor.artistName.normalizedAppleMusicFreshnessText
        }) else { return [] }
        let hydratedArtist = try await artist.with([.similarArtists])
        let similarArtists = Array((hydratedArtist.similarArtists ?? []).prefix(artistLimit))
        var albums: [AlbumSearchResult] = []
        for similarArtist in similarArtists {
            try Task.checkCancellation()
            let hydratedSimilarArtist = try await similarArtist.with([.fullAlbums])
            albums.append(contentsOf: (hydratedSimilarArtist.fullAlbums ?? []).prefix(albumLimit).compactMap(Self.searchResult(from:)))
        }
        return albums.uniquedAppleMusicRecommendations()
    }

    private func catalogAlbum(for anchor: AlbumSearchResult) async throws -> MusicKit.Album? {
        let request = MusicCatalogResourceRequest<MusicKit.Album>(matching: \.id, equalTo: MusicItemID(anchor.catalogID))
        let response = try await request.response()
        try Task.checkCancellation()
        return response.items.first
    }

    func containsArtistInLibrary(named artistName: String) async throws -> Bool {
        try await ensureAuthorized()
        var request = MusicLibrarySearchRequest(term: artistName, types: [MusicKit.Artist.self])
        request.limit = 10
        let response = try await request.response()
        try Task.checkCancellation()
        return response.artists.contains {
            $0.name.normalizedAppleMusicFreshnessText == artistName.normalizedAppleMusicFreshnessText
        }
    }

    private func ensureAuthorized() async throws {
        switch MusicAuthorization.currentStatus {
        case .authorized:
            return
        case .notDetermined:
            let status = await MusicAuthorization.request()

            guard status == .authorized else {
                throw AppleMusicRecommendationError.unauthorized
            }
        case .denied, .restricted:
            throw AppleMusicRecommendationError.unauthorized
        @unknown default:
            throw AppleMusicRecommendationError.unavailable
        }
    }

    private static func metadata(from album: MusicKit.Album) -> AppleMusicPersonalRecommendationMetadata {
        AppleMusicPersonalRecommendationMetadata(
            kind: .album,
            id: album.id.rawValue,
            title: album.title,
            artistName: album.artistName,
            releaseYear: album.releaseDate.map { Calendar.current.component(.year, from: $0) },
            genreName: album.genreNames.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            artworkURL: album.artwork?.url(width: 300, height: 300)?.absoluteString
        )
    }

    private static func searchResult(from album: MusicKit.Album) -> AlbumSearchResult? {
        MusicKitAlbumMapper.albumSearchResult(from: MusicKitAlbumMetadata(
            id: album.id.rawValue,
            title: album.title,
            artistName: album.artistName,
            releaseDate: album.releaseDate,
            genreNames: album.genreNames,
            artworkURL: album.artwork?.url(width: 300, height: 300)
        ))
    }
}
#else
struct AppleMusicRecommendationService: AppleMusicRecommendationServiceProtocol {
    func recommendedAlbums(limit: Int = 20) async throws -> [AlbumSearchResult] {
        throw AppleMusicRecommendationError.unavailable
    }

    func recentlyPlayedAlbums(limit: Int = 20) async throws -> [AlbumSearchResult] {
        throw AppleMusicRecommendationError.unavailable
    }

    func containsInLibrary(_ album: AlbumSearchResult) async throws -> Bool {
        throw AppleMusicRecommendationError.unavailable
    }
}
#endif

private extension Array where Element == AlbumSearchResult {
    func uniquedAppleMusicRecommendations() -> [AlbumSearchResult] {
        var seenCatalogIDs: Set<String> = []

        return filter { album in
            seenCatalogIDs.insert(album.catalogID).inserted
        }
    }
}
