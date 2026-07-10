//
//  AlbumTrack.swift
//  Listend
//
//  Created by Codex on 6/30/26.
//

import Foundation
import SwiftData

@Model
final class AlbumTrack {
    var id: UUID
    var albumAppleMusicID: String
    var appleMusicTrackID: String?
    var title: String
    var artistName: String?
    var trackNumber: Int?
    var discNumber: Int?
    var durationMilliseconds: Int?
    var previewURL: String?
    var returnedOrder: Int
    var cachedAt: Date

    init(
        id: UUID = UUID(),
        albumAppleMusicID: String,
        appleMusicTrackID: String? = nil,
        title: String,
        artistName: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        durationMilliseconds: Int? = nil,
        previewURL: String? = nil,
        returnedOrder: Int = 0,
        cachedAt: Date = Date()
    ) {
        self.id = id
        self.albumAppleMusicID = albumAppleMusicID
        self.appleMusicTrackID = appleMusicTrackID
        self.title = title
        self.artistName = artistName
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.durationMilliseconds = durationMilliseconds
        self.previewURL = previewURL
        self.returnedOrder = returnedOrder
        self.cachedAt = cachedAt
    }
}
