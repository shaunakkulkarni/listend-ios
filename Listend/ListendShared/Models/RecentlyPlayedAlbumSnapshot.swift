//
//  RecentlyPlayedAlbumSnapshot.swift
//  Listend
//
//  Created by Codex on 5/24/26.
//

import Foundation
import SwiftData

@Model
final class RecentlyPlayedAlbumSnapshot {
    var catalogID: String
    var title: String
    var artistName: String
    var releaseYear: Int?
    var genreName: String?
    var artworkURL: String?
    var sortOrder: Int
    var fetchedAt: Date

    init(
        catalogID: String,
        title: String,
        artistName: String,
        releaseYear: Int? = nil,
        genreName: String? = nil,
        artworkURL: String? = nil,
        sortOrder: Int,
        fetchedAt: Date = Date()
    ) {
        self.catalogID = catalogID
        self.title = title
        self.artistName = artistName
        self.releaseYear = releaseYear
        self.genreName = genreName
        self.artworkURL = artworkURL
        self.sortOrder = sortOrder
        self.fetchedAt = fetchedAt
    }
}

