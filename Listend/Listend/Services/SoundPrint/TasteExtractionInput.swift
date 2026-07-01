//
//  TasteExtractionInput.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

import Foundation

struct TasteExtractionInput {
    let logID: UUID
    let albumTitle: String
    let artistName: String
    let genreName: String?
    let releaseYear: Int?
    let rating: Double
    let reviewText: String
    let tags: [String]
    let sentimentScore: Double?
    let favoriteTracks: [String]
    let skipTracks: [String]
    let standoutMoment: String?
    let existingDimensions: [String]

    init(
        logID: UUID,
        albumTitle: String,
        artistName: String,
        genreName: String?,
        releaseYear: Int?,
        rating: Double,
        reviewText: String,
        tags: [String],
        sentimentScore: Double?,
        favoriteTracks: [String] = [],
        skipTracks: [String] = [],
        standoutMoment: String? = nil,
        existingDimensions: [String] = []
    ) {
        self.logID = logID
        self.albumTitle = albumTitle
        self.artistName = artistName
        self.genreName = genreName
        self.releaseYear = releaseYear
        self.rating = rating
        self.reviewText = reviewText
        self.tags = tags
        self.sentimentScore = sentimentScore
        self.favoriteTracks = favoriteTracks
        self.skipTracks = skipTracks
        self.standoutMoment = standoutMoment
        self.existingDimensions = existingDimensions
    }
}
