//
//  AlbumPreviewServiceProtocol.swift
//  Listend
//
//  Created by Codex on 5/5/26.
//

import Foundation

struct AlbumPreview: Equatable, Hashable {
    let albumCatalogID: String
    let trackTitle: String
    let previewURL: URL
}

struct AlbumPreviewLookup: Equatable, Hashable {
    let albumCatalogID: String?
    let title: String
    let artistName: String

    init(albumCatalogID: String?, title: String, artistName: String) {
        self.albumCatalogID = albumCatalogID
        self.title = title
        self.artistName = artistName
    }

    init(album: AlbumSearchResult) {
        self.init(
            albumCatalogID: album.catalogID,
            title: album.title,
            artistName: album.artistName
        )
    }

    init(album: Album) {
        self.init(
            albumCatalogID: album.appleMusicID,
            title: album.title,
            artistName: album.artistName
        )
    }
}

protocol AlbumPreviewServiceProtocol {
    func preview(for lookup: AlbumPreviewLookup) async throws -> AlbumPreview?
}
