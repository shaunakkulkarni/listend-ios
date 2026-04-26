//
//  AlbumCatalogServiceProtocol.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

protocol AlbumCatalogServiceProtocol {
    func searchAlbums(query: String) async throws -> [AlbumSearchResult]
    func albumDetails(id: String) async throws -> AlbumSearchResult?
}
