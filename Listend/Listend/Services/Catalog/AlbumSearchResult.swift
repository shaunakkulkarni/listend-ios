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

    var catalogID: String {
        id
    }
}
