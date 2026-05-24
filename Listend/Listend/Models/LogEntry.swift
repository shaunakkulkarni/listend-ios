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
            tagsRawValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsRawValue = newValue.joined(separator: ",")
        }
    }

    var favoriteTracks: [String] {
        get {
            Self.trackList(from: favoriteTracksRawValue)
        }
        set {
            favoriteTracksRawValue = Self.rawTrackList(from: newValue)
        }
    }

    var skipTracks: [String] {
        get {
            Self.trackList(from: skipTracksRawValue)
        }
        set {
            skipTracksRawValue = Self.rawTrackList(from: newValue)
        }
    }

    var hasTrackHighlights: Bool {
        !favoriteTracks.isEmpty
            || !skipTracks.isEmpty
            || normalizedStandoutMoment != nil
    }

    var normalizedStandoutMoment: String? {
        Self.normalizedOptionalText(standoutMoment)
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
        MockSoundPrintProvider.baseScore(for: rating)
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
        self.tagsRawValue = tags.joined(separator: ",")
        self.favoriteTracksRawValue = Self.rawTrackList(from: favoriteTracks)
        self.skipTracksRawValue = Self.rawTrackList(from: skipTracks)
        self.standoutMoment = Self.normalizedOptionalText(standoutMoment)
        self.sentimentScore = sentimentScore
        self.sentimentConfidence = sentimentConfidence
        self.loggedAt = loggedAt
        self.updatedAt = updatedAt
    }

    private static func trackList(from rawValue: String?) -> [String] {
        guard let rawValue else {
            return []
        }

        return rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func rawTrackList(from tracks: [String]) -> String? {
        let cleanedTracks = tracks
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedTracks.isEmpty else {
            return nil
        }

        return cleanedTracks.joined(separator: ",")
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
