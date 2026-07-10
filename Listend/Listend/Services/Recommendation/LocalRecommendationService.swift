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

struct TodayPickEligibility: Equatable {
    static let requiredDistinctAlbumCount = 5

    let distinctAlbumCount: Int

    @MainActor
    init(logs: [LogEntry]) {
        distinctAlbumCount = Set(logs.compactMap { log in
            log.album.map(Self.albumKey)
        }).count
    }

    var remainingDistinctAlbumCount: Int {
        max(Self.requiredDistinctAlbumCount - distinctAlbumCount, 0)
    }

    var isEligible: Bool {
        remainingDistinctAlbumCount == 0
    }

    var progressDescription: String {
        "Log \(remainingDistinctAlbumCount) more distinct \(remainingDistinctAlbumCount == 1 ? "album" : "albums") to unlock."
    }

    var lockedDescription: String {
        "Log \(remainingDistinctAlbumCount) more distinct \(remainingDistinctAlbumCount == 1 ? "album" : "albums") to unlock Today's Pick. Ratings alone count."
    }

    private static func albumKey(_ album: Album) -> String {
        if let appleMusicID = album.appleMusicID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !appleMusicID.isEmpty {
            return "amid:\(appleMusicID)"
        }

        return "ta:\(album.title.normalizedRecommendationText)|\(album.artistName.normalizedRecommendationText)"
    }
}

struct LocalRecommendationService {
    private let catalogAlbums: [AlbumSearchResult]
    private let candidateProvider: CatalogRecommendationCandidateProvider?
    private let appleMusicService: AppleMusicRecommendationServiceProtocol?
    private let appleMusicCandidateLimit: Int

    init(
        catalogAlbums: [AlbumSearchResult] = MockAlbumCatalogService.defaultAlbums,
        appleMusicService: AppleMusicRecommendationServiceProtocol? = nil,
        appleMusicCandidateLimit: Int = 20
    ) {
        self.catalogAlbums = catalogAlbums
        candidateProvider = nil
        self.appleMusicService = appleMusicService
        self.appleMusicCandidateLimit = appleMusicCandidateLimit
    }

    init(
        catalogService: AlbumCatalogServiceProtocol,
        fallbackCandidates: [AlbumSearchResult] = MockAlbumCatalogService.defaultAlbums,
        appleMusicService: AppleMusicRecommendationServiceProtocol? = nil,
        appleMusicCandidateLimit: Int = 20
    ) {
        catalogAlbums = fallbackCandidates
        candidateProvider = CatalogRecommendationCandidateProvider(
            catalogService: catalogService,
            fallbackCandidates: fallbackCandidates
        )
        self.appleMusicService = appleMusicService
        self.appleMusicCandidateLimit = appleMusicCandidateLimit
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
        guard TodayPickEligibility(logs: logs).isEligible else {
            throw LocalRecommendationError.needsMoreLogs
        }

        let albums = try modelContext.fetch(FetchDescriptor<Album>())
        let evidence = try modelContext.fetch(FetchDescriptor<TasteEvidence>())
        let avoidanceSignals = try modelContext.fetch(FetchDescriptor<TasteAvoidanceSignal>())
        let recommendations = try modelContext.fetch(FetchDescriptor<Recommendation>())
        let anchors = preferenceReferenceLogs(from: logs, evidence: evidence)

        guard !anchors.isEmpty else {
            throw LocalRecommendationError.needsMoreLogs
        }

        let recommendationInput = try await scoredRecommendationInput(
            logs: logs,
            albums: albums,
            evidence: evidence,
            avoidanceSignals: avoidanceSignals,
            recommendations: recommendations,
            anchors: anchors,
            in: modelContext
        )

        let album = try upsertAlbum(for: recommendationInput.scoredCandidate.album, existingAlbums: albums, in: modelContext)
        let recommendation = Recommendation(
            album: album,
            score: recommendationInput.scoredCandidate.score,
            confidence: recommendationInput.scoredCandidate.confidence,
            source: recommendationInput.source.rawValue,
            freshnessStatus: recommendationInput.freshnessStatus.rawValue,
            explanationText: recommendationInput.scoredCandidate.explanation
        )
        modelContext.insert(recommendation)

        for receipt in recommendationInput.scoredCandidate.receipts {
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

    func preferenceReferenceLogs(from logs: [LogEntry], evidence: [TasteEvidence]) -> [LogEntry] {
        let evidenceStrengthByLogID = Dictionary(grouping: evidence.filter(\.isPositiveEvidence), by: \.logEntryID)
            .mapValues { items in
                items.map { $0.strength * $0.confidence }.max() ?? 0
            }
        var bestLogByAlbum: [String: LogEntry] = [:]

        for log in logs {
            guard let album = log.album else {
                continue
            }

            let key = Self.albumKey(album)
            if let current = bestLogByAlbum[key],
               !Self.isBetterReference(log, than: current, evidenceStrengthByLogID: evidenceStrengthByLogID) {
                continue
            }

            bestLogByAlbum[key] = log
        }

        let ranked = bestLogByAlbum.values.sorted {
            Self.isBetterReference($0, than: $1, evidenceStrengthByLogID: evidenceStrengthByLogID)
        }
        let nonNegative = ranked.filter { !$0.isNegativeSignal }

        return nonNegative.isEmpty ? Array(ranked.prefix(1)) : nonNegative
    }

    @MainActor
    func bestCandidate(
        candidates: [AlbumSearchResult]? = nil,
        logs: [LogEntry],
        localAlbums: [Album],
        evidence: [TasteEvidence],
        recommendations: [Recommendation],
        anchors: [LogEntry],
        avoidanceSignals: [TasteAvoidanceSignal] = [],
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
        let avoidanceLogIDs = Set(avoidanceSignals.flatMap(\.evidenceLogEntryIDs))

        return (candidates ?? catalogAlbums)
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
                    avoidanceLogIDs: avoidanceLogIDs,
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
    private func scoredRecommendationInput(
        logs: [LogEntry],
        albums: [Album],
        evidence: [TasteEvidence],
        avoidanceSignals: [TasteAvoidanceSignal],
        recommendations: [Recommendation],
        anchors: [LogEntry],
        in modelContext: ModelContext
    ) async throws -> PendingRecommendationInput {
        if let appleMusicService {
            do {
                let candidates = try await appleMusicRecommendationCandidates(
                    service: appleMusicService,
                    in: modelContext
                )

                guard let scoredCandidate = bestCandidate(
                    candidates: candidates,
                    logs: logs,
                    localAlbums: albums,
                    evidence: evidence,
                    recommendations: recommendations,
                    anchors: anchors,
                    avoidanceSignals: avoidanceSignals,
                    allowDismissed: false
                ) else {
                    throw LocalRecommendationError.noCandidates
                }

                return PendingRecommendationInput(
                    scoredCandidate: scoredCandidate,
                    source: .applePersonalRecommendations,
                    freshnessStatus: .appleFreshnessChecked
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch LocalRecommendationError.noCandidates {
                throw LocalRecommendationError.noCandidates
            } catch {
                return try await listendFallbackRecommendationInput(
                    logs: logs,
                    albums: albums,
                    evidence: evidence,
                    avoidanceSignals: avoidanceSignals,
                    recommendations: recommendations,
                    anchors: anchors
                )
            }
        }

        return try await listendFallbackRecommendationInput(
            logs: logs,
            albums: albums,
            evidence: evidence,
            avoidanceSignals: avoidanceSignals,
            recommendations: recommendations,
            anchors: anchors
        )
    }

    @MainActor
    private func listendFallbackRecommendationInput(
        logs: [LogEntry],
        albums: [Album],
        evidence: [TasteEvidence],
        avoidanceSignals: [TasteAvoidanceSignal],
        recommendations: [Recommendation],
        anchors: [LogEntry]
    ) async throws -> PendingRecommendationInput {
        let candidates = await recommendationCandidates(
            logs: logs,
            albums: albums,
            evidence: evidence,
            anchors: anchors
        )

        guard let scoredCandidate = bestCandidate(
            candidates: candidates,
            logs: logs,
            localAlbums: albums,
            evidence: evidence,
            recommendations: recommendations,
            anchors: anchors,
            avoidanceSignals: avoidanceSignals,
            allowDismissed: false
        ) else {
            throw LocalRecommendationError.noCandidates
        }

        return PendingRecommendationInput(
            scoredCandidate: scoredCandidate,
            source: .listendFallback,
            freshnessStatus: .appleFreshnessUnavailable
        )
    }

    @MainActor
    private func appleMusicRecommendationCandidates(
        service: AppleMusicRecommendationServiceProtocol,
        in modelContext: ModelContext
    ) async throws -> [AlbumSearchResult] {
        async let recommendedAlbums = service.recommendedAlbums(limit: appleMusicCandidateLimit)
        async let recentlyPlayedAlbums = service.recentlyPlayedAlbums(limit: appleMusicCandidateLimit)

        let (recommendations, recentAlbums) = try await (recommendedAlbums, recentlyPlayedAlbums)
        try AppleMusicRecentPlaySnapshotStore.recordRecentlyPlayedAlbums(recentAlbums, in: modelContext)
        let recentSnapshots = try AppleMusicRecentPlaySnapshotStore.recentlyObservedAlbums(in: modelContext)

        let freshnessEligibleCandidates = recommendations
            .prefix(appleMusicCandidateLimit)
            .filter { candidate in
                !recentAlbums.contains(where: { Self.matches($0, candidate) })
                    && !recentSnapshots.contains(where: { AppleMusicRecentPlaySnapshotStore.matches($0, candidate) })
            }

        return try await withThrowingTaskGroup(of: AppleMusicLibraryCheckResult.self) { group in
            for (index, candidate) in freshnessEligibleCandidates.enumerated() {
                group.addTask {
                    try Task.checkCancellation()
                    let isInLibrary = try await service.containsInLibrary(candidate)
                    return AppleMusicLibraryCheckResult(index: index, album: candidate, isInLibrary: isInLibrary)
                }
            }

            var checkedCandidates: [AppleMusicLibraryCheckResult] = []
            for try await checkedCandidate in group {
                checkedCandidates.append(checkedCandidate)
            }

            return checkedCandidates
                .filter { !$0.isInLibrary }
                .sorted { $0.index < $1.index }
                .map(\.album)
        }
    }

    @MainActor
    private func recommendationCandidates(
        logs: [LogEntry],
        albums: [Album],
        evidence: [TasteEvidence],
        anchors: [LogEntry]
    ) async -> [AlbumSearchResult] {
        guard let candidateProvider else {
            return catalogAlbums
        }

        let anchorInputs = anchors.compactMap(Self.anchorInput)
        let loggedAlbumInputs = logs
            .compactMap(\.album)
            .map(Self.loggedAlbumInput)
        let evidenceInputs = evidence.map(Self.evidenceInput)

        return await candidateProvider.candidates(
            anchors: anchorInputs,
            evidence: evidenceInputs,
            loggedAlbums: loggedAlbumInputs
        )
    }

    @MainActor
    private func score(
        _ candidate: AlbumSearchResult,
        anchors: [LogEntry],
        negativeLogs: [LogEntry],
        evidence: [TasteEvidence],
        avoidanceLogIDs: Set<UUID>,
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
        let hasPositiveEvidence = evidence.contains { $0.logEntryID == matchedAnchor.id && $0.isPositiveEvidence }
        let confidenceCap: Double

        if matchedAnchor.isNegativeSignal {
            confidenceCap = 0.55
        } else if !hasPositiveEvidence || avoidanceLogIDs.contains(matchedAnchor.id) {
            confidenceCap = 0.65
        } else {
            confidenceCap = 0.85
        }

        return ScoredRecommendationCandidate(
            album: candidate,
            score: clampedScore,
            confidence: min(0.55 + clampedScore * 0.35, confidenceCap),
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
        "Based on your strongest signals around \(receipt.sourceAlbumTitle), Today's Pick is \(candidate.title) by \(candidate.artistName). \(receipt.snippet)"
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
            genreName: candidate.genreName,
            artworkURL: candidate.artworkURL
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
        album.artworkURL = candidate.artworkURL
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
        if let appleMusicID = album.appleMusicID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !appleMusicID.isEmpty {
            return "amid:\(appleMusicID)"
        }

        return "ta:\(album.title.normalizedRecommendationText)|\(album.artistName.normalizedRecommendationText)"
    }

    private static func isBetterReference(
        _ candidate: LogEntry,
        than current: LogEntry,
        evidenceStrengthByLogID: [UUID: Double]
    ) -> Bool {
        if candidate.isNegativeSignal != current.isNegativeSignal {
            return !candidate.isNegativeSignal
        }

        if candidate.rating != current.rating {
            return candidate.rating > current.rating
        }

        let candidateEvidence = evidenceStrengthByLogID[candidate.id, default: 0]
        let currentEvidence = evidenceStrengthByLogID[current.id, default: 0]
        if candidateEvidence != currentEvidence {
            return candidateEvidence > currentEvidence
        }

        return candidate.loggedAt > current.loggedAt
    }

    private static func albumKey(_ album: AlbumSearchResult) -> String {
        "amid:\(album.catalogID)"
    }

    private static func matches(_ lhs: AlbumSearchResult, _ rhs: AlbumSearchResult) -> Bool {
        if lhs.catalogID == rhs.catalogID {
            return true
        }

        return lhs.title.normalizedRecommendationText == rhs.title.normalizedRecommendationText
            && lhs.artistName.normalizedRecommendationText == rhs.artistName.normalizedRecommendationText
    }

    @MainActor
    private static func anchorInput(from log: LogEntry) -> RecommendationAnchorInput? {
        guard let album = log.album else {
            return nil
        }

        return RecommendationAnchorInput(
            logID: log.id,
            albumCatalogID: album.appleMusicID,
            albumTitle: album.title,
            artistName: album.artistName,
            genreName: album.genreName,
            tags: log.tags
        )
    }

    @MainActor
    private static func loggedAlbumInput(from album: Album) -> RecommendationLoggedAlbumInput {
        RecommendationLoggedAlbumInput(
            catalogID: album.appleMusicID,
            title: album.title,
            artistName: album.artistName
        )
    }

    private static func evidenceInput(from evidence: TasteEvidence) -> RecommendationEvidenceInput {
        RecommendationEvidenceInput(
            logEntryID: evidence.logEntryID,
            dimensionName: evidence.dimensionName,
            strength: evidence.strength,
            isPositiveEvidence: evidence.isPositiveEvidence
        )
    }
}

private struct PendingRecommendationInput {
    let scoredCandidate: ScoredRecommendationCandidate
    let source: RecommendationSource
    let freshnessStatus: RecommendationFreshnessStatus
}

private struct AppleMusicLibraryCheckResult {
    let index: Int
    let album: AlbumSearchResult
    let isInLibrary: Bool
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
