//
//  AlbumSearchResult.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

import Foundation

struct AlbumSearchResult: Identifiable, Hashable {
    let id: String
    let title: String
    let artistName: String
    let releaseYear: Int?
    let genreName: String?
    let artworkURL: String?

    init(
        id: String,
        title: String,
        artistName: String,
        releaseYear: Int?,
        genreName: String?,
        artworkURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artistName = artistName
        self.releaseYear = releaseYear
        self.genreName = genreName
        self.artworkURL = artworkURL
    }

    var catalogID: String {
        id
    }
}
