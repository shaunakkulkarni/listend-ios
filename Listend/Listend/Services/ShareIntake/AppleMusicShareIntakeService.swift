//
//  AppleMusicShareIntakeService.swift
//  Listend
//

import Foundation

enum ShareIntakeResult: Equatable {
    case resolved(AlbumSearchResult)
    case needsManualSearch(suggestedQuery: String)
}

/// Resolves a pasted Apple Music album link into the app's catalog representation.
/// Never throws: any parse or catalog failure degrades to a manual-search suggestion
/// so logging is never blocked by MusicKit or URL parsing.
struct AppleMusicShareIntakeService {
    let catalogService: AlbumCatalogServiceProtocol

    func resolve(_ input: String) async -> ShareIntakeResult {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let link = AppleMusicAlbumLinkParser.parse(trimmedInput) else {
            return .needsManualSearch(suggestedQuery: trimmedInput)
        }

        if let albumID = link.albumID,
           let album = try? await catalogService.albumDetails(id: albumID) {
            return .resolved(album)
        }

        return .needsManualSearch(suggestedQuery: link.titleHint ?? trimmedInput)
    }
}
