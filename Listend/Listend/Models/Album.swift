//
//  Album.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import Foundation
import SwiftData

@Model
final class Album {
    var id: UUID
    var appleMusicID: String?
    var title: String
    var artistName: String
    var releaseYear: Int?
    var genreName: String?
    var artworkURL: String?
    var cachedAt: Date

    init(
        id: UUID = UUID(),
        appleMusicID: String? = nil,
        title: String,
        artistName: String,
        releaseYear: Int? = nil,
        genreName: String? = nil,
        artworkURL: String? = nil,
        cachedAt: Date = Date()
    ) {
        self.id = id
        self.appleMusicID = appleMusicID
        self.title = title
        self.artistName = artistName
        self.releaseYear = releaseYear
        self.genreName = genreName
        self.artworkURL = artworkURL
        self.cachedAt = cachedAt
    }
}
