//
//  LogEntry.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import Foundation
import SwiftData

@Model
final class LogEntry {
    var id: UUID
    var album: Album?
    var rating: Double
    var reviewText: String
    // Legacy persisted field names retained for SwiftData compatibility.
    // Current writes store JSON-encoded string arrays in these raw values.
    var tagsRawValue: String
    var favoriteTracksRawValue: String?
    var skipTracksRawValue: String?
    var standoutMoment: String?
    var sentimentScore: Double?
    var sentimentConfidence: Double?
    var loggedAt: Date
    var updatedAt: Date

    var tags: [String] {
        get {
            ListTextNormalizer.decodedStringArrayOrLegacyCommaList(from: tagsRawValue, kind: .tags)
        }
        set {
            tagsRawValue = ListTextNormalizer.encodedStringArray(ListTextNormalizer.normalizedTags(newValue))
        }
    }

    var favoriteTracks: [String] {
        get {
            ListTextNormalizer.decodedStringArrayOrLegacyCommaList(from: favoriteTracksRawValue, kind: .trackNames)
        }
        set {
            favoriteTracksRawValue = Self.encodedOptionalTrackList(from: newValue)
        }
    }

    var skipTracks: [String] {
        get {
            ListTextNormalizer.decodedStringArrayOrLegacyCommaList(from: skipTracksRawValue, kind: .trackNames)
        }
        set {
            skipTracksRawValue = Self.encodedOptionalTrackList(from: newValue)
        }
    }

    var hasTrackHighlights: Bool {
        !favoriteTracks.isEmpty
            || !skipTracks.isEmpty
            || normalizedStandoutMoment != nil
    }

    var normalizedStandoutMoment: String? {
        ListTextNormalizer.normalizedOptionalText(standoutMoment)
    }

    var isPositiveSignal: Bool {
        (sentimentScore ?? ratingDerivedSentimentScore) >= 0.0
    }

    var isNegativeSignal: Bool {
        (sentimentScore ?? ratingDerivedSentimentScore) < -0.2
    }

    var canAnchorRecommendation: Bool {
        !isNegativeSignal
    }

    private var ratingDerivedSentimentScore: Double {
        if rating >= 4.0 {
            return 0.7
        }

        if rating >= 3.0 {
            return 0.2
        }

        return -0.5
    }

    init(
        id: UUID = UUID(),
        album: Album?,
        rating: Double,
        reviewText: String = "",
        tags: [String] = [],
        favoriteTracks: [String] = [],
        skipTracks: [String] = [],
        standoutMoment: String? = nil,
        sentimentScore: Double? = nil,
        sentimentConfidence: Double? = nil,
        loggedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.album = album
        self.rating = rating
        self.reviewText = reviewText
        self.tagsRawValue = ListTextNormalizer.encodedStringArray(ListTextNormalizer.normalizedTags(tags))
        self.favoriteTracksRawValue = Self.encodedOptionalTrackList(from: favoriteTracks)
        self.skipTracksRawValue = Self.encodedOptionalTrackList(from: skipTracks)
        self.standoutMoment = ListTextNormalizer.normalizedOptionalText(standoutMoment)
        self.sentimentScore = sentimentScore
        self.sentimentConfidence = sentimentConfidence
        self.loggedAt = loggedAt
        self.updatedAt = updatedAt
    }

    private static func encodedOptionalTrackList(from tracks: [String]) -> String? {
        let normalizedTracks = ListTextNormalizer.normalizedTrackNames(tracks)
        guard !normalizedTracks.isEmpty else {
            return nil
        }

        return ListTextNormalizer.encodedStringArray(normalizedTracks)
    }
}
