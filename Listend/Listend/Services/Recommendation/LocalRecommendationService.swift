//
//  LocalRecommendationService.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

import Foundation
import SwiftData

enum LocalRecommendationError: Error, Equatable {
    case needsMoreLogs
    case noCandidates
}

struct LocalRecommendationService {
    private let catalogAlbums: [AlbumSearchResult]

    init(catalogAlbums: [AlbumSearchResult] = MockAlbumCatalogService.defaultAlbums) {
        self.catalogAlbums = catalogAlbums
    }

    @MainActor
    func activeRecommendation(in modelContext: ModelContext) throws -> Recommendation? {
        let recommendations = try modelContext.fetch(FetchDescriptor<Recommendation>())
        return recommendations
            .filter { $0.status == RecommendationStatus.active.rawValue }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }

    @MainActor
    func currentOrGenerateRecommendation(in modelContext: ModelContext) async throws -> Recommendation {
        if let activeRecommendation = try activeRecommendation(in: modelContext) {
            return activeRecommendation
        }

        let logs = try modelContext.fetch(FetchDescriptor<LogEntry>())
        let albums = try modelContext.fetch(FetchDescriptor<Album>())
        let evidence = try modelContext.fetch(FetchDescriptor<TasteEvidence>())
        let recommendations = try modelContext.fetch(FetchDescriptor<Recommendation>())
        let anchors = positiveAnchorLogs(from: logs)

        guard !anchors.isEmpty else {
            throw LocalRecommendationError.needsMoreLogs
        }

        guard let scoredCandidate = bestCandidate(
            logs: logs,
            localAlbums: albums,
            evidence: evidence,
            recommendations: recommendations,
            anchors: anchors,
            allowDismissed: false
        ) else {
            throw LocalRecommendationError.noCandidates
        }

        let album = try upsertAlbum(for: scoredCandidate.album, existingAlbums: albums, in: modelContext)
        let recommendation = Recommendation(
            album: album,
            score: scoredCandidate.score,
            confidence: scoredCandidate.confidence,
            explanationText: scoredCandidate.explanation
        )
        modelContext.insert(recommendation)

        for receipt in scoredCandidate.receipts {
            modelContext.insert(
                RecommendationReceipt(
                    recommendationID: recommendation.id,
                    logEntryID: receipt.logID,
                    sourceAlbumTitle: receipt.sourceAlbumTitle,
                    sourceArtistName: receipt.sourceArtistName,
                    sourceRating: receipt.sourceRating,
                    snippet: receipt.snippet,
                    linkedDimension: receipt.linkedDimension
                )
            )
        }

        try modelContext.save()
        return recommendation
    }

    @MainActor
    func submitFeedback(
        _ feedbackType: RecommendationFeedbackType,
        for recommendation: Recommendation,
        in modelContext: ModelContext
    ) throws {
        recommendation.status = feedbackType.resultingStatus.rawValue
        modelContext.insert(
            RecommendationFeedback(
                recommendationID: recommendation.id,
                feedbackType: feedbackType.rawValue
            )
        )
        try modelContext.save()
    }

    @MainActor
    func receipts(for recommendation: Recommendation, in modelContext: ModelContext) throws -> [RecommendationReceipt] {
        let receipts = try modelContext.fetch(FetchDescriptor<RecommendationReceipt>())
        return receipts
            .filter { $0.recommendationID == recommendation.id }
            .sorted {
                if $0.sourceRating == $1.sourceRating {
                    return $0.sourceAlbumTitle < $1.sourceAlbumTitle
                }

                return $0.sourceRating > $1.sourceRating
            }
    }

    func positiveAnchorLogs(from logs: [LogEntry]) -> [LogEntry] {
        logs
            .filter { log in
                log.album != nil
                    && !log.isNegativeSignal
                    && log.rating >= 4.0
            }
            .sorted {
                if $0.rating == $1.rating {
                    return ($0.album?.title ?? "") < ($1.album?.title ?? "")
                }

                return $0.rating > $1.rating
            }
    }

    @MainActor
    func bestCandidate(
        logs: [LogEntry],
        localAlbums: [Album],
        evidence: [TasteEvidence],
        recommendations: [Recommendation],
        anchors: [LogEntry],
        allowDismissed: Bool
    ) -> ScoredRecommendationCandidate? {
        let loggedAlbums = logs.compactMap(\.album)
        let dismissedAlbumKeys = Set(
            recommendations
                .filter { $0.status == RecommendationStatus.dismissed.rawValue }
                .compactMap(\.album)
                .map(Self.albumKey)
        )
        let recentlyRecommendedArtists = Set(
            recommendations
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(3)
                .compactMap { $0.album?.artistName.normalizedRecommendationText }
        )
        let negativeLogs = logs.filter(\.isNegativeSignal)

        return catalogAlbums
            .filter { candidate in
                !loggedAlbums.contains { Self.matches($0, candidate) }
            }
            .filter { candidate in
                allowDismissed || !dismissedAlbumKeys.contains(Self.albumKey(candidate))
            }
            .map { candidate in
                score(
                    candidate,
                    anchors: anchors,
                    negativeLogs: negativeLogs,
                    evidence: evidence,
                    recentlyRecommendedArtists: recentlyRecommendedArtists
                )
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                if lhs.album.catalogID != rhs.album.catalogID {
                    return lhs.album.catalogID < rhs.album.catalogID
                }

                let lhsName = "\(lhs.album.artistName.normalizedRecommendationText)|\(lhs.album.title.normalizedRecommendationText)"
                let rhsName = "\(rhs.album.artistName.normalizedRecommendationText)|\(rhs.album.title.normalizedRecommendationText)"
                return lhsName < rhsName
            }
            .first
    }

    @MainActor
    private func score(
        _ candidate: AlbumSearchResult,
        anchors: [LogEntry],
        negativeLogs: [LogEntry],
        evidence: [TasteEvidence],
        recentlyRecommendedArtists: Set<String>
    ) -> ScoredRecommendationCandidate {
        var score = 0.2
        var matchedAnchor = anchors[0]
        var linkedDimension: String?

        if let genreName = candidate.genreName,
           let anchor = anchors.first(where: { $0.album?.genreName?.normalizedRecommendationText == genreName.normalizedRecommendationText }) {
            score += 0.3
            matchedAnchor = anchor
        }

        if let releaseYear = candidate.releaseYear,
           let anchor = anchors.first(where: { $0.album?.releaseYear?.recommendationDecade == releaseYear.recommendationDecade }) {
            score += 0.2
            matchedAnchor = anchor
        }

        if let overlap = tagOrEvidenceOverlap(for: candidate, anchors: anchors, evidence: evidence) {
            score += 0.2
            matchedAnchor = overlap.log
            linkedDimension = overlap.dimensionName
        }

        if !anchors.contains(where: { $0.album?.artistName.normalizedRecommendationText == candidate.artistName.normalizedRecommendationText }) {
            score += 0.1
        }

        if let genreName = candidate.genreName,
           negativeLogs.contains(where: { $0.album?.genreName?.normalizedRecommendationText == genreName.normalizedRecommendationText }) {
            score -= 0.4
        }

        if recentlyRecommendedArtists.contains(candidate.artistName.normalizedRecommendationText) {
            score -= 0.2
        }

        let clampedScore = score.clamped(to: 0.0...1.0)
        let receipt = makeReceipt(from: matchedAnchor, linkedDimension: linkedDimension)

        return ScoredRecommendationCandidate(
            album: candidate,
            score: clampedScore,
            confidence: (0.55 + clampedScore * 0.35).clamped(to: 0.0...0.95),
            explanation: explanation(candidate: candidate, receipt: receipt),
            receipts: [receipt]
        )
    }

    @MainActor
    private func tagOrEvidenceOverlap(
        for candidate: AlbumSearchResult,
        anchors: [LogEntry],
        evidence: [TasteEvidence]
    ) -> (log: LogEntry, dimensionName: String?)? {
        let candidateText = [
            candidate.title,
            candidate.artistName,
            candidate.genreName ?? ""
        ]
            .joined(separator: " ")
            .normalizedRecommendationText

        for anchor in anchors {
            if anchor.tags.contains(where: { !$0.isEmpty && candidateText.contains($0.normalizedRecommendationText) }) {
                return (anchor, nil)
            }

            if let matchedEvidence = evidence.first(where: { item in
                item.logEntryID == anchor.id
                    && item.isPositiveEvidence
                    && candidateText.contains(item.dimensionName.normalizedRecommendationText)
            }) {
                return (anchor, matchedEvidence.dimensionName)
            }
        }

        return nil
    }

    @MainActor
    private func makeReceipt(from log: LogEntry, linkedDimension: String?) -> PendingRecommendationReceipt {
        let album = log.album
        let snippet: String

        if !log.tags.isEmpty {
            snippet = "Rated \(album?.title ?? "this album") \(log.rating.formatted(.number.precision(.fractionLength(1)))) stars and tagged it \(log.tags.prefix(2).joined(separator: ", "))."
        } else if !log.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snippet = "Your review said: \(log.reviewText.trimmedRecommendationSnippet)"
        } else {
            snippet = "Rated \(album?.title ?? "this album") \(log.rating.formatted(.number.precision(.fractionLength(1)))) stars."
        }

        return PendingRecommendationReceipt(
            logID: log.id,
            sourceAlbumTitle: album?.title ?? "Unknown Album",
            sourceArtistName: album?.artistName ?? "Unknown Artist",
            sourceRating: log.rating,
            snippet: snippet,
            linkedDimension: linkedDimension
        )
    }

    private func explanation(candidate: AlbumSearchResult, receipt: PendingRecommendationReceipt) -> String {
        "Because you liked \(receipt.sourceAlbumTitle), Tonight's Pick is \(candidate.title) by \(candidate.artistName). \(receipt.snippet)"
    }

    @MainActor
    private func upsertAlbum(
        for candidate: AlbumSearchResult,
        existingAlbums: [Album],
        in modelContext: ModelContext
    ) throws -> Album {
        if let catalogMatch = existingAlbums.first(where: { $0.appleMusicID == candidate.catalogID }) {
            update(catalogMatch, with: candidate)
            try modelContext.save()
            return catalogMatch
        }

        if let titleMatch = existingAlbums.first(where: { Self.matches($0, candidate) }) {
            update(titleMatch, with: candidate)
            try modelContext.save()
            return titleMatch
        }

        let album = Album(
            appleMusicID: candidate.catalogID,
            title: candidate.title,
            artistName: candidate.artistName,
            releaseYear: candidate.releaseYear,
            genreName: candidate.genreName
        )
        modelContext.insert(album)
        try modelContext.save()
        return album
    }

    private func update(_ album: Album, with candidate: AlbumSearchResult) {
        album.appleMusicID = candidate.catalogID
        album.title = candidate.title
        album.artistName = candidate.artistName
        album.releaseYear = candidate.releaseYear
        album.genreName = candidate.genreName
        album.cachedAt = Date()
    }

    @MainActor
    static func matches(_ album: Album, _ candidate: AlbumSearchResult) -> Bool {
        if album.appleMusicID == candidate.catalogID {
            return true
        }

        return album.title.normalizedRecommendationText == candidate.title.normalizedRecommendationText
            && album.artistName.normalizedRecommendationText == candidate.artistName.normalizedRecommendationText
    }

    @MainActor
    private static func albumKey(_ album: Album) -> String {
        if let appleMusicID = album.appleMusicID {
            return appleMusicID
        }

        return "\(album.artistName.normalizedRecommendationText)|\(album.title.normalizedRecommendationText)"
    }

    private static func albumKey(_ album: AlbumSearchResult) -> String {
        album.catalogID
    }
}

struct ScoredRecommendationCandidate {
    let album: AlbumSearchResult
    let score: Double
    let confidence: Double
    let explanation: String
    let receipts: [PendingRecommendationReceipt]
}

struct PendingRecommendationReceipt {
    let logID: UUID
    let sourceAlbumTitle: String
    let sourceArtistName: String
    let sourceRating: Double
    let snippet: String
    let linkedDimension: String?
}

private extension String {
    var normalizedRecommendationText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRecommendationSnippet: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count > 96 else {
            return trimmed
        }

        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 96)
        return String(trimmed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

private extension Int {
    var recommendationDecade: Int {
        self / 10
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
