//
//  TasteInsightsTests.swift
//  ListendTests
//
//  Focused unit tests for the pure "Your Taste So Far" calculation logic. Models are
//  constructed directly (no ModelContainer), following the existing pure-logic test
//  precedent (StarRatingCalculator / SoundPrintReceiptDisplay).
//

import Testing
import Foundation
@testable import Listend

@MainActor
struct TasteInsightsTests {

    // MARK: - Top rated albums

    @Test func topRatedAlbumsSortByRatingThenMostRecent() {
        let logA = LogEntry(album: Album(title: "Album A", artistName: "Artist A"), rating: 4.0, loggedAt: date(100))
        let logB = LogEntry(album: Album(title: "Album B", artistName: "Artist B"), rating: 5.0, loggedAt: date(50))
        let logC = LogEntry(album: Album(title: "Album C", artistName: "Artist C"), rating: 5.0, loggedAt: date(200))
        let logD = LogEntry(album: Album(title: "Album D", artistName: "Artist D"), rating: 3.0, loggedAt: date(300))
        let albumless = LogEntry(album: nil, rating: 5.0, loggedAt: date(400))

        let top = TasteInsightsBuilder.topRatedAlbums(from: [logA, logB, logC, logD, albumless])

        // 5.0s first (most recent of the tie leads), then 4.0, then 3.0; album-less excluded.
        #expect(top.map(\.title) == ["Album C", "Album B", "Album A", "Album D"])
        #expect(top.count == 4)
    }

    @Test func topRatedAlbumsCapAtFive() {
        let logs = (0..<6).map { index in
            LogEntry(album: Album(title: "Album \(index)", artistName: "Artist"), rating: 4.0, loggedAt: date(Double(index)))
        }

        #expect(TasteInsightsBuilder.topRatedAlbums(from: logs).count == 5)
    }

    // MARK: - Tags

    @Test func topTagsCountCaseInsensitivelyWithAlphabeticalTieBreak() {
        let logs = [
            LogEntry(album: nil, rating: 4.0, tags: ["Zeta"]),
            LogEntry(album: nil, rating: 4.0, tags: ["zeta"]),
            LogEntry(album: nil, rating: 4.0, tags: ["alpha"]),
            LogEntry(album: nil, rating: 4.0, tags: ["beta"])
        ]

        let insights = TasteInsightsBuilder.make(from: logs)

        #expect(insights.topTags.map(\.tag) == ["zeta", "alpha", "beta"])
        #expect(insights.topTags.first?.count == 2)
        #expect(insights.topTag == "zeta")
    }

    @Test func topTagsCapAtEight() {
        let logs = (0..<9).map { index in
            LogEntry(album: nil, rating: 4.0, tags: ["tag\(index)"])
        }

        #expect(TasteInsightsBuilder.make(from: logs).topTags.count == 8)
    }

    // MARK: - Rating distribution

    @Test func ratingBucketFoldsHalfStarsToNearestWholeStar() {
        #expect(TasteInsightsBuilder.bucket(for: 0.5) == 1)
        #expect(TasteInsightsBuilder.bucket(for: 1.0) == 1)
        #expect(TasteInsightsBuilder.bucket(for: 2.5) == 3)
        #expect(TasteInsightsBuilder.bucket(for: 3.5) == 4)
        #expect(TasteInsightsBuilder.bucket(for: 4.5) == 5)
        #expect(TasteInsightsBuilder.bucket(for: 5.0) == 5)
    }

    @Test func ratingDistributionCountsPerWholeStarBucket() {
        let logs = [0.5, 2.5, 4.5, 5.0, 4.5].map { rating in
            LogEntry(album: nil, rating: rating)
        }

        let distribution = TasteInsightsBuilder.ratingDistribution(from: logs)

        // Returned high-to-low.
        #expect(distribution.map(\.star) == [5, 4, 3, 2, 1])
        #expect(distribution.map(\.count) == [3, 0, 1, 0, 1])
    }

    @Test func ratingDistributionIsAllZeroWhenNoLogs() {
        let distribution = TasteInsightsBuilder.ratingDistribution(from: [])

        #expect(distribution.map(\.star) == [5, 4, 3, 2, 1])
        #expect(distribution.allSatisfy { $0.count == 0 })
    }

    // MARK: - Top artist

    @Test func topArtistRequiresAtLeastTwoLogs() {
        let singletons = [
            LogEntry(album: Album(title: "One", artistName: "Solo Artist"), rating: 4.0),
            LogEntry(album: Album(title: "Two", artistName: "Other Artist"), rating: 4.0)
        ]
        #expect(TasteInsightsBuilder.topArtist(from: singletons) == nil)

        let repeated = singletons + [
            LogEntry(album: Album(title: "Three", artistName: "Solo Artist"), rating: 4.0)
        ]
        #expect(TasteInsightsBuilder.topArtist(from: repeated) == "Solo Artist")
    }

    // MARK: - Taste note / states

    @Test func emptyStateHasNoTasteNote() {
        let insights = TasteInsightsBuilder.make(from: [])

        #expect(insights.state == .empty)
        #expect(insights.tasteNote == nil)
        #expect(insights.averageRating == nil)
    }

    @Test func earlyStateUsesGroundedColdCopy() {
        let logs = (0..<3).map { _ in LogEntry(album: nil, rating: 4.0, tags: ["lush"]) }

        let insights = TasteInsightsBuilder.make(from: logs)

        #expect(insights.state == .early)
        #expect(insights.tasteNote == "You're still early in your Listend history — a few more logs will make this sharper.")
    }

    @Test func fullStateNoteReflectsHighlyRatedTags() throws {
        let logs = [
            LogEntry(album: nil, rating: 5.0, tags: ["lush", "raw"]),
            LogEntry(album: nil, rating: 4.5, tags: ["lush"]),
            LogEntry(album: nil, rating: 4.0, tags: ["raw"]),
            LogEntry(album: nil, rating: 4.5, tags: ["replayable"]),
            LogEntry(album: nil, rating: 4.0, tags: ["lush"])
        ]

        let insights = TasteInsightsBuilder.make(from: logs)
        let note = try #require(insights.tasteNote)

        #expect(insights.state == .full)
        // Locale-robust: assert shape + grounded content rather than exact list punctuation.
        #expect(note.hasPrefix("Your highest ratings tend to go to albums tagged"))
        #expect(note.contains("lush"))
        #expect(note.contains("raw"))
        #expect(note.contains("replayable"))
        #expect(note.hasSuffix("."))
    }

    // MARK: - Helpers

    private func date(_ seconds: Double) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}
