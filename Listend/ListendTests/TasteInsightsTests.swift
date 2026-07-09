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

    // MARK: - Dedupe

    @Test func topRatedAlbumsCollapseReLogsByAppleMusicID() {
        let logs = [
            LogEntry(album: Album(appleMusicID: "amid-1", title: "Blonde", artistName: "Frank Ocean"), rating: 3.0, loggedAt: date(10)),
            LogEntry(album: Album(appleMusicID: "amid-1", title: "Blonde", artistName: "Frank Ocean"), rating: 5.0, loggedAt: date(20)),
            LogEntry(album: Album(appleMusicID: "amid-1", title: "Blonde", artistName: "Frank Ocean"), rating: 4.0, loggedAt: date(30))
        ]

        let top = TasteInsightsBuilder.topRatedAlbums(from: logs)

        #expect(top.count == 1)
        #expect(top.first?.rating == 5.0) // best log represents the album
    }

    @Test func topRatedAlbumsCollapseReLogsByTitleArtistWhenNoAppleMusicID() {
        let logs = [
            LogEntry(album: Album(title: "Kind of Blue", artistName: "Miles Davis"), rating: 4.0, loggedAt: date(10)),
            LogEntry(album: Album(title: "  kind of BLUE ", artistName: "miles davis"), rating: 4.5, loggedAt: date(20))
        ]

        let top = TasteInsightsBuilder.topRatedAlbums(from: logs)

        #expect(top.count == 1)
        #expect(top.first?.rating == 4.5)
    }

    @Test func topRatedAlbumsKeepDistinctAlbumsSeparate() {
        let logs = [
            LogEntry(album: Album(appleMusicID: "a", title: "One", artistName: "X"), rating: 4.0),
            LogEntry(album: Album(appleMusicID: "b", title: "Two", artistName: "X"), rating: 4.0)
        ]

        #expect(TasteInsightsBuilder.topRatedAlbums(from: logs).count == 2)
    }

    // MARK: - Randomized invariants (fuzz)

    /// Throws lots of random logs (duplicate albums, mixed-case tags, half-stars, missing
    /// albums) at the builder and checks that the derived recap always holds its invariants.
    /// Seeded, so any failure is reproducible from the reported argument.
    @Test(arguments: 0..<60)
    func insightsHoldInvariantsForRandomData(seed: Int) {
        var rng = SeededGenerator(seed: UInt64(seed) &+ 1)
        let logs = Self.randomLogs(using: &rng)

        let insights = TasteInsightsBuilder.make(from: logs)

        // Totals + state gating.
        #expect(insights.totalLogs == logs.count)
        switch insights.state {
        case .empty:
            #expect(logs.isEmpty)
        case .early:
            #expect((1..<5).contains(logs.count))
        case .full:
            #expect(logs.count >= 5)
        }

        // Average rating.
        if logs.isEmpty {
            #expect(insights.averageRating == nil)
        } else if let average = insights.averageRating {
            #expect(average >= 0.5 && average <= 5.0)
        } else {
            Issue.record("averageRating unexpectedly nil for \(logs.count) logs")
        }

        // Rating distribution: 5 buckets high-to-low, counts cover every log exactly once.
        #expect(insights.ratingDistribution.map(\.star) == [5, 4, 3, 2, 1])
        #expect(insights.ratingDistribution.allSatisfy { $0.count >= 0 })
        #expect(insights.ratingDistribution.reduce(0) { $0 + $1.count } == logs.count)

        // Top tags: capped, lowercased, sorted count-desc / alpha, matching a brute-force recount.
        #expect(insights.topTags.count <= 8)
        #expect(insights.topTags.allSatisfy { $0.tag == $0.tag.lowercased() })
        for (lhs, rhs) in zip(insights.topTags, insights.topTags.dropFirst()) {
            #expect(lhs.count > rhs.count || (lhs.count == rhs.count && lhs.tag < rhs.tag))
        }
        let expectedTagCounts = Self.expectedTagCounts(from: logs)
        let expectedTopTags = expectedTagCounts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(8)
        #expect(insights.topTags.map(\.tag) == expectedTopTags.map(\.key))
        #expect(insights.topTags.map(\.count) == expectedTopTags.map(\.value))
        #expect(insights.topTag == insights.topTags.first?.tag)

        // Top rated albums: capped, deduped (unique titles), sorted, each rating == album's best.
        let top = insights.topRatedAlbums
        #expect(top.count <= 5)
        #expect(Set(top.map(\.title)).count == top.count)
        for (lhs, rhs) in zip(top, top.dropFirst()) {
            #expect(lhs.rating > rhs.rating || (lhs.rating == rhs.rating && lhs.loggedAt >= rhs.loggedAt))
        }
        let maxRatingByTitle = Self.maxRatingByAlbumTitle(from: logs)
        for item in top {
            #expect(item.rating == maxRatingByTitle[item.title])
        }
        let distinctLoggedAlbumTitles = Set(logs.compactMap { $0.album?.title })
        #expect(top.count == min(5, distinctLoggedAlbumTitles.count))
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

    // MARK: - Random data generation / oracles (fuzz support)

    /// Distinct albums with unique catalog ids and unique titles, so dedupe-by-key lines up
    /// with grouping-by-title in the oracles.
    private static let albumPool: [(appleMusicID: String, title: String, artist: String)] = [
        ("amid-1", "Blonde", "Frank Ocean"),
        ("amid-2", "In Rainbows", "Radiohead"),
        ("amid-3", "Blue", "Joni Mitchell"),
        ("amid-4", "To Pimp a Butterfly", "Kendrick Lamar"),
        ("amid-5", "Rumours", "Fleetwood Mac"),
        ("amid-6", "Kind of Blue", "Miles Davis")
    ]

    private static let tagPool = [
        "lush", "raw", "replayable", "moody", "warm", "bright", "dense", "sparse", "nostalgic", "danceable"
    ]

    private static let ratingSteps = Array(stride(from: 0.5, through: 5.0, by: 0.5))

    private static func randomLogs(using rng: inout SeededGenerator) -> [LogEntry] {
        let count = Int.random(in: 0...45, using: &rng)

        return (0..<count).map { _ in
            let album: Album?
            if Int.random(in: 0..<100, using: &rng) < 15 {
                album = nil // some logs have no album
            } else {
                let pick = albumPool.randomElement(using: &rng)!
                album = Album(appleMusicID: pick.appleMusicID, title: pick.title, artistName: pick.artist)
            }

            let rating = ratingSteps.randomElement(using: &rng)!

            var tags: [String] = []
            for _ in 0..<Int.random(in: 0...4, using: &rng) {
                var tag = tagPool.randomElement(using: &rng)!
                if Bool.random(using: &rng) {
                    tag = tag.uppercased() // exercise case-insensitive counting
                }
                tags.append(tag)
            }

            let loggedAt = Date(timeIntervalSince1970: Double(Int.random(in: 0...1_000_000, using: &rng)))
            return LogEntry(album: album, rating: rating, tags: tags, loggedAt: loggedAt)
        }
    }

    private static func expectedTagCounts(from logs: [LogEntry]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for log in logs {
            for tag in log.tags {
                let key = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !key.isEmpty else {
                    continue
                }
                counts[key, default: 0] += 1
            }
        }
        return counts
    }

    private static func maxRatingByAlbumTitle(from logs: [LogEntry]) -> [String: Double] {
        var maxByTitle: [String: Double] = [:]
        for log in logs {
            guard let title = log.album?.title else {
                continue
            }
            maxByTitle[title] = max(maxByTitle[title] ?? -.infinity, log.rating)
        }
        return maxByTitle
    }
}

/// Deterministic SplitMix64 generator so fuzz iterations are reproducible from their seed.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
