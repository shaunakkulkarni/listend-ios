//
//  MockRecentlyPlayedAlbumService.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

struct MockRecentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol {
    private let albums: [AlbumSearchResult]

    init(albums: [AlbumSearchResult] = Self.defaultAlbums) {
        self.albums = albums
    }

    func recentlyPlayedAlbums() async throws -> [AlbumSearchResult] {
        albums
    }
}

extension MockRecentlyPlayedAlbumService {
    static let defaultAlbums: [AlbumSearchResult] = [
        MockAlbumCatalogService.defaultAlbums[1],
        MockAlbumCatalogService.defaultAlbums[4],
        MockAlbumCatalogService.defaultAlbums[7],
        MockAlbumCatalogService.defaultAlbums[9]
    ]
}
