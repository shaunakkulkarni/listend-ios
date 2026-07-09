//
//  TasteInsights.swift
//  Listend
//
//  Local-first "Your Taste So Far" recap. Pure value types plus a deterministic
//  builder over already-fetched logs — no SwiftUI, no SwiftData fetching, no AI,
//  no networking. Kept pure so the calculation logic is unit-testable without a
//  ModelContainer (mirrors StarRatingCalculator / SoundPrintReceiptDisplay).
//

import Foundation

/// Which version of the recap to show, gated on how many logs exist. Reuses the
/// same `personaMinimumLogCount` threshold that SoundPrint uses for its full state
/// so the two screens agree on when a user has "enough" history.
enum TasteInsightsState {
    /// No logs yet — show an invitation to log an album.
    case empty
    /// 1..<5 logs — show what stats we can, but temper them: patterns are still forming.
    case early
    /// 5+ logs — show the full recap.
    case full

    init(logCount: Int) {
        if logCount <= 0 {
            self = .empty
        } else if logCount < SoundPrintProfileThresholds.personaMinimumLogCount {
            self = .early
        } else {
            self = .full
        }
    }
}

/// One entry in the Top Rated Albums list. Backed by a log (a re-logged album can
/// appear more than once by design), so `id` is the log's id.
struct TopRatedAlbumItem: Identifiable {
    let id: UUID
    let title: String
    let artist: String
    let rating: Double
    let loggedAt: Date
}

/// A tag paired with how many logs carry it. Tags are already normalized (lowercase).
struct TagCount: Identifiable {
    let tag: String
    let count: Int

    var id: String { tag }
}

/// One whole-star bucket (1...5) in the rating distribution.
struct RatingBucket: Identifiable {
    let star: Int
    let count: Int

    var id: Int { star }
}

/// The fully-derived recap the screen renders. Nothing here touches SwiftData or the
/// network — it's a snapshot computed from the logs handed to `TasteInsightsBuilder`.
struct TasteInsights {
    let state: TasteInsightsState
    let totalLogs: Int
    let averageRating: Double?
    let topTag: String?
    let topArtist: String?
    let topRatedAlbums: [TopRatedAlbumItem]
    let topTags: [TagCount]
    let ratingDistribution: [RatingBucket]
    let tasteNote: String?
}

/// Deterministic aggregation of a user's local logs into `TasteInsights`. Every method
/// is pure and side-effect free; the same logs always produce the same recap.
enum TasteInsightsBuilder {
    static let topRatedAlbumLimit = 5
    static let topTagLimit = 8
    /// Tags shown / used only need to describe the albums the user actually rewards.
    static let highRatingThreshold = 4.0
    static let highRatedTagLimit = 3
    /// A top artist is only "earned" once at least this many logs point at them —
    /// avoids crowning an arbitrary winner when every artist has a single log.
    static let minimumTopArtistLogCount = 2

    static func make(from logs: [LogEntry]) -> TasteInsights {
        let state = TasteInsightsState(logCount: logs.count)
        let rankedTags = rankedTags(from: logs)
        let topTags = Array(rankedTags.prefix(topTagLimit))
        let topArtist = topArtist(from: logs)

        return TasteInsights(
            state: state,
            totalLogs: logs.count,
            averageRating: averageRating(of: logs),
            topTag: topTags.first?.tag,
            topArtist: topArtist,
            topRatedAlbums: topRatedAlbums(from: logs),
            topTags: topTags,
            ratingDistribution: ratingDistribution(from: logs),
            tasteNote: tasteNote(from: logs, state: state, overallRankedTags: rankedTags, topArtist: topArtist)
        )
    }

    // MARK: - Components

    static func averageRating(of logs: [LogEntry]) -> Double? {
        guard !logs.isEmpty else {
            return nil
        }

        let total = logs.reduce(0.0) { $0 + $1.rating }
        return total / Double(logs.count)
    }

    /// All tags across the logs, counted case-insensitively and sorted by count desc
    /// with an alphabetical tie-break. Defensive lowercasing/trimming keeps counting
    /// robust even though `LogEntry.tags` already yields normalized values.
    static func rankedTags(from logs: [LogEntry]) -> [TagCount] {
        var counts: [String: Int] = [:]

        for log in logs {
            for rawTag in log.tags {
                let tag = normalizedTag(rawTag)
                guard !tag.isEmpty else {
                    continue
                }

                counts[tag, default: 0] += 1
            }
        }

        return counts
            .sorted(by: rankByCountThenKey)
            .map { TagCount(tag: $0.key, count: $0.value) }
    }

    /// The most-logged artist, or nil when no artist reaches `minimumTopArtistLogCount`.
    static func topArtist(from logs: [LogEntry]) -> String? {
        var counts: [String: Int] = [:]

        for log in logs {
            guard let artist = log.album?.artistName else {
                continue
            }

            let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            counts[trimmed, default: 0] += 1
        }

        guard let leader = counts.sorted(by: rankByCountThenKey).first,
              leader.value >= minimumTopArtistLogCount else {
            return nil
        }

        return leader.key
    }

    /// Up to 5 albums, highest rating first. Each album appears once — a re-logged album
    /// collapses to its best log (highest rating, ties broken by most recent). Albums are
    /// then ordered by that representative rating desc, most recent desc, with a stable
    /// title/key tie-break. Logs without an album are excluded.
    static func topRatedAlbums(from logs: [LogEntry]) -> [TopRatedAlbumItem] {
        var bestLogByAlbum: [String: LogEntry] = [:]

        for log in logs {
            guard let album = log.album else {
                continue
            }

            let key = albumKey(for: album)
            if let existing = bestLogByAlbum[key] {
                if isBetterRepresentative(log, than: existing) {
                    bestLogByAlbum[key] = log
                }
            } else {
                bestLogByAlbum[key] = log
            }
        }

        return bestLogByAlbum
            .map { (key: $0.key, log: $0.value) }
            .sorted { lhs, rhs in
                if lhs.log.rating != rhs.log.rating {
                    return lhs.log.rating > rhs.log.rating
                }

                if lhs.log.loggedAt != rhs.log.loggedAt {
                    return lhs.log.loggedAt > rhs.log.loggedAt
                }

                let lhsTitle = lhs.log.album?.title ?? ""
                let rhsTitle = rhs.log.album?.title ?? ""
                if lhsTitle != rhsTitle {
                    return lhsTitle < rhsTitle
                }

                return lhs.key < rhs.key
            }
            .prefix(topRatedAlbumLimit)
            .map { entry in
                TopRatedAlbumItem(
                    id: entry.log.id,
                    title: entry.log.album?.title ?? "Unknown Album",
                    artist: entry.log.album?.artistName ?? "Unknown Artist",
                    rating: entry.log.rating,
                    loggedAt: entry.log.loggedAt
                )
            }
    }

    /// Identity used to collapse re-logs of the same album: the Apple Music catalog id when
    /// present (the reliable key), otherwise a normalized title+artist fallback for
    /// albums logged without catalog metadata.
    static func albumKey(for album: Album) -> String {
        if let appleMusicID = album.appleMusicID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !appleMusicID.isEmpty {
            return "amid:\(appleMusicID)"
        }

        let title = album.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let artist = album.artistName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "ta:\(title)\u{1}\(artist)"
    }

    /// A log better represents its album than another when it rates higher, or matches on
    /// rating but was logged more recently.
    private static func isBetterRepresentative(_ candidate: LogEntry, than current: LogEntry) -> Bool {
        if candidate.rating != current.rating {
            return candidate.rating > current.rating
        }

        return candidate.loggedAt > current.loggedAt
    }

    /// Counts folded into whole-star buckets (1...5), returned high-to-low for display.
    static func ratingDistribution(from logs: [LogEntry]) -> [RatingBucket] {
        var counts: [Int: Int] = [:]

        for log in logs {
            counts[bucket(for: log.rating), default: 0] += 1
        }

        return stride(from: 5, through: 1, by: -1).map { star in
            RatingBucket(star: star, count: counts[star, default: 0])
        }
    }

    /// Nearest whole star, clamped to 1...5 (0.5 → 1, 4.5 → 5). Half-stars fold up/down.
    static func bucket(for rating: Double) -> Int {
        min(5, max(1, Int(rating.rounded())))
    }

    /// One deterministic, grounded sentence. Nil for the empty state (the screen shows an
    /// invitation instead). Deliberately avoids "eclectic"/"diverse" and fake certainty.
    static func tasteNote(
        from logs: [LogEntry],
        state: TasteInsightsState,
        overallRankedTags: [TagCount],
        topArtist: String?
    ) -> String? {
        switch state {
        case .empty:
            return nil
        case .early:
            return "You're still early in your Listend history — a few more logs will make this sharper."
        case .full:
            let highRatedLogs = logs.filter { $0.rating >= highRatingThreshold }
            let highRatedTags = rankedTags(from: highRatedLogs).prefix(highRatedTagLimit).map(\.tag)
            if !highRatedTags.isEmpty {
                return "Your highest ratings tend to go to albums tagged \(formattedList(highRatedTags))."
            }

            let overallTags = overallRankedTags.prefix(highRatedTagLimit).map(\.tag)
            if !overallTags.isEmpty {
                return "You've been gravitating toward \(formattedList(overallTags)) albums lately."
            }

            if let topArtist {
                return "You keep coming back to \(topArtist)."
            }

            return "You've logged \(logs.count) albums — add a few tags and your taste notes will get sharper."
        }
    }

    // MARK: - Helpers

    private static func normalizedTag(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func formattedList(_ items: [String]) -> String {
        items.formatted(.list(type: .and, width: .standard))
    }

    /// Count descending, alphabetical key ascending on ties — shared by tag and artist ranking.
    private static func rankByCountThenKey(_ lhs: (key: String, value: Int), _ rhs: (key: String, value: Int)) -> Bool {
        if lhs.value == rhs.value {
            return lhs.key < rhs.key
        }

        return lhs.value > rhs.value
    }
}
