//
//  RecentlyPlayedAlbumLogState.swift
//  Listend
//
//  Created by Codex on 5/28/26.
//

import Foundation

enum RecentlyPlayedAlbumLogState {
    static func isLogged(_ album: AlbumSearchResult, in logs: [LogEntry]) -> Bool {
        logs.contains { log in
            guard let loggedAlbum = log.album else {
                return false
            }

            return matchesCatalogID(album, loggedAlbum: loggedAlbum)
                || matchesTitleAndArtist(album, loggedAlbum: loggedAlbum)
        }
    }

    private static func matchesCatalogID(_ album: AlbumSearchResult, loggedAlbum: Album) -> Bool {
        loggedAlbum.appleMusicID == album.catalogID
    }

    private static func matchesTitleAndArtist(_ album: AlbumSearchResult, loggedAlbum: Album) -> Bool {
        loggedAlbum.title.normalizedAlbumMatchText == album.title.normalizedAlbumMatchText
            && loggedAlbum.artistName.normalizedAlbumMatchText == album.artistName.normalizedAlbumMatchText
    }
}

