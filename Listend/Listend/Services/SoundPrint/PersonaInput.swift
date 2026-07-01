//
//  PersonaInput.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

struct PersonaInput {
    let dimensions: [TasteDimension]
    let recentLogs: [PersonaLogInput]
    let totalLogCount: Int
    let topTags: [String]
    let averageRating: Double?
    let avoidanceSignals: [String]

    init(
        dimensions: [TasteDimension],
        recentLogs: [PersonaLogInput],
        totalLogCount: Int,
        topTags: [String],
        averageRating: Double?,
        avoidanceSignals: [String] = []
    ) {
        self.dimensions = dimensions
        self.recentLogs = recentLogs
        self.totalLogCount = totalLogCount
        self.topTags = topTags
        self.averageRating = averageRating
        self.avoidanceSignals = avoidanceSignals
    }
}

struct PersonaLogInput {
    let albumTitle: String
    let artistName: String
    let rating: Double
    let reviewSnippet: String
    let tags: [String]
    let isPositiveSignal: Bool
    let favoriteTracks: [String]
    let hasStandoutMoment: Bool

    init(
        albumTitle: String,
        artistName: String,
        rating: Double,
        reviewSnippet: String,
        tags: [String],
        isPositiveSignal: Bool,
        favoriteTracks: [String] = [],
        hasStandoutMoment: Bool = false
    ) {
        self.albumTitle = albumTitle
        self.artistName = artistName
        self.rating = rating
        self.reviewSnippet = reviewSnippet
        self.tags = tags
        self.isPositiveSignal = isPositiveSignal
        self.favoriteTracks = favoriteTracks
        self.hasStandoutMoment = hasStandoutMoment
    }
}
