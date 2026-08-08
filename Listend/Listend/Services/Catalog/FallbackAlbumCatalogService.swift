//
//  FallbackAlbumCatalogService.swift
//  Listend
//
//  Created by Codex on 5/3/26.
//

import Foundation

struct FallbackAlbumCatalogService: AlbumCatalogServiceProtocol {
    private let primary: AlbumCatalogServiceProtocol
    private let fallback: AlbumCatalogServiceProtocol

    init(primary: AlbumCatalogServiceProtocol, fallback: AlbumCatalogServiceProtocol = MockAlbumCatalogService()) {
        self.primary = primary
        self.fallback = fallback
    }

    func searchAlbums(query: String) async throws -> [AlbumSearchResult] {
        do {
            let results = try await primary.searchAlbums(query: query)

            guard !results.isEmpty else {
                return try await fallback.searchAlbums(query: query)
            }

            return results
        } catch is CancellationError {
            return try await fallback.searchAlbums(query: query)
        } catch {
            return try await fallback.searchAlbums(query: query)
        }
    }

    func albumDetails(id: String) async throws -> AlbumSearchResult? {
        do {
            if let album = try await primary.albumDetails(id: id) {
                return album
            }

            return try await fallback.albumDetails(id: id)
        } catch is CancellationError {
            return try await fallback.albumDetails(id: id)
        } catch {
            return try await fallback.albumDetails(id: id)
        }
    }

    func appleMusicURL(for id: String) async throws -> URL? {
        do {
            if let url = try await primary.appleMusicURL(for: id) {
                return url
            }

            return try await fallback.appleMusicURL(for: id)
        } catch is CancellationError {
            return try await fallback.appleMusicURL(for: id)
        } catch {
            return try await fallback.appleMusicURL(for: id)
        }
    }
}
