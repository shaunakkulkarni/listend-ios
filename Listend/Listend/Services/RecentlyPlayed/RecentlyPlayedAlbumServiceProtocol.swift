//
//  RecentlyPlayedAlbumServiceProtocol.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

protocol RecentlyPlayedAlbumServiceProtocol {
    func recentlyPlayedAlbums() async throws -> [AlbumSearchResult]
}
