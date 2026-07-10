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

enum TodayPickMatchQuality: String, Equatable {
    case strong = "Strong match"
    case good = "Good match"
    case exploratory = "Exploratory pick"

    init(confidence: Double) {
        if confidence >= 0.75 {
            self = .strong
        } else if confidence >= 0.60 {
            self = .good
        } else {
            self = .exploratory
        }
    }

    var label: String { rawValue }
}

struct AnchorStrengthBreakdown: Equatable {
    let ratingDirection: Double
    let sentimentDirection: Double
    let direction: Double
    let favoriteTrackBoost: Double
    let standoutMomentBoost: Double
    let positiveEvidenceBoost: Double
    let skipPenalty: Double
    let avoidancePenalty: Double
    let detailAdjustment: Double
    let total: Double
}

struct RecommendationAnchorProfile {
    let albumKey: String
    let album: Album
    let logs: [LogEntry]
    let averageRating: Double
    let tags: [String]
    let favoriteTracks: [String]
    let skipTracks: [String]
    let positiveEvidenceDimensions: [String]
    let hasPositiveEvidence: Bool
    let hasAvoidanceEvidence: Bool
    let strengthBreakdown: AnchorStrengthBreakdown

    var logIDs: [UUID] { logs.map(\.id) }
    var strength: Double { strengthBreakdown.total }
    var isPositive: Bool { strength > 0 }
    var isNegative: Bool { strength < 0 }
}

struct RecommendationScoreBreakdown: Equatable {
    let base: Double
    let genreAffinity: Double
    let eraAffinity: Double
    let tagAffinity: Double
    let artistNovelty: Double
    let recentArtistRepetition: Double
    let genreAvoidance: Double
    let feedbackAffinity: Double

    var total: Double {
        (base + genreAffinity + eraAffinity + tagAffinity + artistNovelty
            + recentArtistRepetition + genreAvoidance + feedbackAffinity)
            .clamped(to: 0...1)
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
        let feedback = try modelContext.fetch(FetchDescriptor<RecommendationFeedback>())
        let anchorProfiles = recommendationAnchorProfiles(
            from: logs,
            evidence: evidence,
            avoidanceSignals: avoidanceSignals
        )

        let recommendationInput = try await scoredRecommendationInput(
            logs: logs,
            evidence: evidence,
            recommendations: recommendations,
            feedback: feedback,
            anchorProfiles: anchorProfiles,
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

    @MainActor
    func recommendationAnchorProfiles(
        from logs: [LogEntry],
        evidence: [TasteEvidence],
        avoidanceSignals: [TasteAvoidanceSignal] = []
    ) -> [RecommendationAnchorProfile] {
        let groupedLogs = Dictionary(grouping: logs.compactMap { log in
            log.album.map { (Self.albumKey($0), log) }
        }, by: \.0)

        return groupedLogs.compactMap { albumKey, keyedLogs in
            let albumLogs = keyedLogs.map(\.1)
            guard let album = albumLogs.first?.album else { return nil }

            let logIDs = Set(albumLogs.map(\.id))
            let averageRating = albumLogs.map(\.rating).reduce(0, +) / Double(albumLogs.count)
            let ratingDirection = ((averageRating - 3) / 2).clamped(to: -1...1)
            let sentimentValues = albumLogs.map { log -> (Double, Double) in
                guard let score = log.sentimentScore else {
                    return (((log.rating - 3) / 2).clamped(to: -1...1), 1)
                }
                return (score.clamped(to: -1...1), (log.sentimentConfidence ?? 1).clamped(to: 0...1))
            }
            let sentimentWeight = sentimentValues.map(\.1).reduce(0, +)
            let sentimentDirection = sentimentWeight > 0
                ? sentimentValues.reduce(0) { $0 + $1.0 * $1.1 } / sentimentWeight
                : ratingDirection
            let direction = (ratingDirection * 0.7 + sentimentDirection * 0.3).clamped(to: -1...1)

            let positiveEvidence = evidence.filter { $0.isPositiveEvidence && logIDs.contains($0.logEntryID) }
            let positiveEvidenceByDimension = Dictionary(grouping: positiveEvidence, by: {
                $0.dimensionName.normalizedRecommendationText
            }).compactMapValues { items in
                items.max { lhs, rhs in
                    lhs.strength * lhs.confidence < rhs.strength * rhs.confidence
                }
            }
            let evidenceStrengths = positiveEvidenceByDimension.values
                .map { ($0.strength * $0.confidence).clamped(to: 0...1) }
                .sorted(by: >)
            let positiveEvidenceBoost = min(evidenceStrengths.prefix(2).reduce(0, +) * 0.04, 0.08)

            let relatedAvoidanceSignals = avoidanceSignals.filter { signal in
                !logIDs.isDisjoint(with: signal.evidenceLogEntryIDs)
            }
            let avoidanceByName = Dictionary(grouping: relatedAvoidanceSignals, by: {
                $0.name.normalizedRecommendationText
            }).compactMapValues { items in
                items.max { lhs, rhs in
                    lhs.strength * lhs.confidence < rhs.strength * rhs.confidence
                }
            }
            let avoidanceStrengths = avoidanceByName.values
                .map { ($0.strength * $0.confidence).clamped(to: 0...1) }
                .sorted(by: >)
            let avoidancePenalty = min(avoidanceStrengths.prefix(2).reduce(0, +) * 0.04, 0.08)

            let tags = Self.uniqueNormalizedValues(albumLogs.flatMap(\.tags))
            let favoriteTracks = Self.uniqueNormalizedValues(albumLogs.flatMap(\.favoriteTracks))
            let skipTracks = Self.uniqueNormalizedValues(albumLogs.flatMap(\.skipTracks))
            let favoriteTrackBoost = min(Double(favoriteTracks.count) * 0.04, 0.08)
            let standoutMomentBoost = albumLogs.contains(where: { $0.normalizedStandoutMoment != nil }) ? 0.04 : 0
            let skipPenalty = min(Double(skipTracks.count) * 0.03, 0.09)
            let detailAdjustment = (favoriteTrackBoost + standoutMomentBoost + positiveEvidenceBoost
                - skipPenalty - avoidancePenalty).clamped(to: -0.15...0.15)
            let adjustedStrength = (direction + detailAdjustment).clamped(to: -1...1)
            let total = ratingDirection < 0 ? min(adjustedStrength, 0) : adjustedStrength

            return RecommendationAnchorProfile(
                albumKey: albumKey,
                album: album,
                logs: albumLogs.sorted { $0.loggedAt > $1.loggedAt },
                averageRating: averageRating,
                tags: tags,
                favoriteTracks: favoriteTracks,
                skipTracks: skipTracks,
                positiveEvidenceDimensions: positiveEvidenceByDimension.values
                    .sorted { lhs, rhs in
                        let lhsStrength = lhs.strength * lhs.confidence
                        let rhsStrength = rhs.strength * rhs.confidence
                        return lhsStrength == rhsStrength
                            ? lhs.dimensionName.normalizedRecommendationText < rhs.dimensionName.normalizedRecommendationText
                            : lhsStrength > rhsStrength
                    }
                    .map(\.dimensionName),
                hasPositiveEvidence: !positiveEvidenceByDimension.isEmpty,
                hasAvoidanceEvidence: !avoidanceByName.isEmpty,
                strengthBreakdown: AnchorStrengthBreakdown(
                    ratingDirection: ratingDirection,
                    sentimentDirection: sentimentDirection,
                    direction: direction,
                    favoriteTrackBoost: favoriteTrackBoost,
                    standoutMomentBoost: standoutMomentBoost,
                    positiveEvidenceBoost: positiveEvidenceBoost,
                    skipPenalty: skipPenalty,
                    avoidancePenalty: avoidancePenalty,
                    detailAdjustment: detailAdjustment,
                    total: total
                )
            )
        }
        .sorted {
            if $0.strength == $1.strength { return $0.albumKey < $1.albumKey }
            return $0.strength > $1.strength
        }
    }

    @MainActor
    func bestCandidate(
        candidates: [AlbumSearchResult]? = nil,
        logs: [LogEntry],
        recommendations: [Recommendation],
        feedback: [RecommendationFeedback] = [],
        anchorProfiles: [RecommendationAnchorProfile]
    ) -> ScoredRecommendationCandidate? {
        let loggedAlbums = logs.compactMap(\.album)
        let recommendedAlbums = recommendations.compactMap(\.album)
        let recentlyRecommendedArtists = Set(
            recommendations
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(3)
                .compactMap { $0.album?.artistName.normalizedRecommendationText }
        )
        let latestFeedbackByRecommendationID = Dictionary(grouping: feedback, by: \.recommendationID)
            .compactMapValues { $0.max { $0.createdAt < $1.createdAt } }

        return (candidates ?? catalogAlbums)
            .filter { candidate in
                !loggedAlbums.contains { Self.matches($0, candidate) }
            }
            .filter { candidate in
                !recommendedAlbums.contains { Self.matches($0, candidate) }
            }
            .map { candidate in
                score(
                    candidate,
                    anchorProfiles: anchorProfiles,
                    recommendations: recommendations,
                    latestFeedbackByRecommendationID: latestFeedbackByRecommendationID,
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
        evidence: [TasteEvidence],
        recommendations: [Recommendation],
        feedback: [RecommendationFeedback],
        anchorProfiles: [RecommendationAnchorProfile],
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
                    recommendations: recommendations,
                    feedback: feedback,
                    anchorProfiles: anchorProfiles
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
                    evidence: evidence,
                    recommendations: recommendations,
                    feedback: feedback,
                    anchorProfiles: anchorProfiles
                )
            }
        }

        return try await listendFallbackRecommendationInput(
            logs: logs,
            evidence: evidence,
            recommendations: recommendations,
            feedback: feedback,
            anchorProfiles: anchorProfiles
        )
    }

    @MainActor
    private func listendFallbackRecommendationInput(
        logs: [LogEntry],
        evidence: [TasteEvidence],
        recommendations: [Recommendation],
        feedback: [RecommendationFeedback],
        anchorProfiles: [RecommendationAnchorProfile]
    ) async throws -> PendingRecommendationInput {
        let candidates = await recommendationCandidates(
            logs: logs,
            evidence: evidence,
            anchorProfiles: anchorProfiles
        )

        guard let scoredCandidate = bestCandidate(
            candidates: candidates,
            logs: logs,
            recommendations: recommendations,
            feedback: feedback,
            anchorProfiles: anchorProfiles
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
        evidence: [TasteEvidence],
        anchorProfiles: [RecommendationAnchorProfile]
    ) async -> [AlbumSearchResult] {
        guard let candidateProvider else {
            return catalogAlbums
        }

        let anchorInputs = anchorProfiles.filter(\.isPositive).map(Self.anchorInput)
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
        anchorProfiles: [RecommendationAnchorProfile],
        recommendations: [Recommendation],
        latestFeedbackByRecommendationID: [UUID: RecommendationFeedback],
        recentlyRecommendedArtists: Set<String>
    ) -> ScoredRecommendationCandidate {
        let breakdown = recommendationScoreBreakdown(
            for: candidate,
            anchorProfiles: anchorProfiles,
            recommendations: recommendations,
            latestFeedbackByRecommendationID: latestFeedbackByRecommendationID,
            recentlyRecommendedArtists: recentlyRecommendedArtists
        )
        let relevantProfiles = candidateRelevantPositiveProfiles(candidate, profiles: anchorProfiles)
        let receiptsAndProfiles = relevantProfiles.compactMap { profile -> (PendingRecommendationReceipt, RecommendationAnchorProfile)? in
            guard let receipt = makeReceipt(from: profile, candidate: candidate) else { return nil }
            return (receipt, profile)
        }
        .prefix(2)
        let receipts = receiptsAndProfiles.map(\.0)
        let receiptProfiles = receiptsAndProfiles.map(\.1)
        let confidenceCap: Double = if receipts.isEmpty {
            0.55
        } else if receiptProfiles.allSatisfy({ $0.hasPositiveEvidence && !$0.hasAvoidanceEvidence }) {
            0.85
        } else {
            0.65
        }

        return ScoredRecommendationCandidate(
            album: candidate,
            score: breakdown.total,
            confidence: min(0.55 + breakdown.total * 0.35, confidenceCap),
            explanation: explanation(candidate: candidate, receipts: receipts),
            receipts: receipts,
            scoreBreakdown: breakdown
        )
    }

    @MainActor
    func recommendationScoreBreakdown(
        for candidate: AlbumSearchResult,
        anchorProfiles: [RecommendationAnchorProfile],
        recommendations: [Recommendation] = [],
        feedback: [RecommendationFeedback] = []
    ) -> RecommendationScoreBreakdown {
        let latestFeedback = Dictionary(grouping: feedback, by: \.recommendationID)
            .compactMapValues { $0.max { $0.createdAt < $1.createdAt } }
        let recentArtists = Set(recommendations.sorted { $0.createdAt > $1.createdAt }.prefix(3)
            .compactMap { $0.album?.artistName.normalizedRecommendationText })
        return recommendationScoreBreakdown(
            for: candidate,
            anchorProfiles: anchorProfiles,
            recommendations: recommendations,
            latestFeedbackByRecommendationID: latestFeedback,
            recentlyRecommendedArtists: recentArtists
        )
    }

    @MainActor
    private func recommendationScoreBreakdown(
        for candidate: AlbumSearchResult,
        anchorProfiles: [RecommendationAnchorProfile],
        recommendations: [Recommendation],
        latestFeedbackByRecommendationID: [UUID: RecommendationFeedback],
        recentlyRecommendedArtists: Set<String>
    ) -> RecommendationScoreBreakdown {
        let positiveProfiles = anchorProfiles.filter(\.isPositive)
        let genreProfiles = positiveProfiles.filter { Self.sameGenre($0.album, candidate) }
            .sorted { $0.strength > $1.strength }
        let genreStrengths = genreProfiles.prefix(2).map(\.strength)
        let genreAffinity = min(
            (genreStrengths.isEmpty ? 0 : genreStrengths.reduce(0, +) / Double(genreStrengths.count) * 0.25)
                + (genreProfiles.count >= 2 ? 0.05 : 0),
            0.30
        )
        let eraAffinity = positiveProfiles
            .filter { Self.sameEra($0.album, candidate) }
            .map(\.strength)
            .max()
            .map { $0 * 0.12 } ?? 0
        let candidateText = Self.candidateMetadataText(candidate)
        let tagAffinity = min(positiveProfiles.compactMap { profile in
            profile.tags.contains { candidateText.contains($0.normalizedRecommendationText) }
                ? profile.strength * 0.05
                : nil
        }.max() ?? 0, 0.05)
        let knownArtists = Set(anchorProfiles.map { $0.album.artistName.normalizedRecommendationText }
            + recommendations.compactMap { $0.album?.artistName.normalizedRecommendationText })
        let artistNovelty = knownArtists.contains(candidate.artistName.normalizedRecommendationText) ? 0 : 0.05
        let recentArtistRepetition = recentlyRecommendedArtists.contains(candidate.artistName.normalizedRecommendationText) ? -0.10 : 0
        let matchingNegativeProfiles = anchorProfiles.filter { $0.isNegative && Self.sameGenre($0.album, candidate) }
        let genreAvoidance: Double = if matchingNegativeProfiles.count >= 2 {
            -0.20 * matchingNegativeProfiles.map { abs($0.strength) }.reduce(0, +) / Double(matchingNegativeProfiles.count)
        } else {
            0
        }
        let feedbackAffinity = min(recommendations.compactMap { recommendation -> Double? in
            guard let album = recommendation.album else { return nil }
            let multiplier = Self.feedbackMultiplier(
                feedback: latestFeedbackByRecommendationID[recommendation.id],
                recommendationStatus: recommendation.status
            )
            guard multiplier > 0 else { return nil }
            return ((Self.sameGenre(album, candidate) ? 0.04 : 0)
                + (Self.sameEra(album, candidate) ? 0.02 : 0)) * multiplier
        }.max() ?? 0, 0.06)

        return RecommendationScoreBreakdown(
            base: 0.20,
            genreAffinity: genreAffinity,
            eraAffinity: eraAffinity,
            tagAffinity: tagAffinity,
            artistNovelty: artistNovelty,
            recentArtistRepetition: recentArtistRepetition,
            genreAvoidance: genreAvoidance,
            feedbackAffinity: feedbackAffinity
        )
    }

    @MainActor
    private func candidateRelevantPositiveProfiles(
        _ candidate: AlbumSearchResult,
        profiles: [RecommendationAnchorProfile]
    ) -> [RecommendationAnchorProfile] {
        let candidateText = Self.candidateMetadataText(candidate)
        return profiles.filter { profile in
            profile.isPositive && (
                Self.sameGenre(profile.album, candidate)
                    || Self.sameEra(profile.album, candidate)
                    || profile.tags.contains { candidateText.contains($0.normalizedRecommendationText) }
                    || profile.positiveEvidenceDimensions.contains { candidateText.contains($0.normalizedRecommendationText) }
            )
        }
        .sorted {
            if $0.strength == $1.strength { return $0.albumKey < $1.albumKey }
            return $0.strength > $1.strength
        }
    }

    @MainActor
    private func makeReceipt(
        from profile: RecommendationAnchorProfile,
        candidate: AlbumSearchResult
    ) -> PendingRecommendationReceipt? {
        guard let log = profile.logs.filter({ !$0.isNegativeSignal }).sorted(by: Self.isBetterReceiptLog).first else {
            return nil
        }

        let album = log.album
        let albumTitle = album?.title ?? "this album"
        let snippet: String

        if let standoutMoment = log.normalizedStandoutMoment {
            snippet = "Your standout moment on \(albumTitle): \(standoutMoment.trimmedRecommendationSnippet)"
        } else if !log.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            snippet = "Your review of \(albumTitle) said: \(log.reviewText.trimmedRecommendationSnippet)"
        } else if !log.favoriteTracks.isEmpty {
            snippet = "Favorite \(log.favoriteTracks.count == 1 ? "track" : "tracks") from \(albumTitle): \(log.favoriteTracks.prefix(2).joined(separator: ", "))."
        } else if !log.tags.isEmpty {
            snippet = "You tagged \(albumTitle) \(log.tags.prefix(2).joined(separator: ", "))."
        } else {
            snippet = "Rated \(albumTitle) \(log.rating.formatted(.number.precision(.fractionLength(1)))) stars."
        }

        let candidateText = Self.candidateMetadataText(candidate)
        let linkedDimension = profile.positiveEvidenceDimensions.first {
            candidateText.contains($0.normalizedRecommendationText)
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

    private func explanation(candidate: AlbumSearchResult, receipts: [PendingRecommendationReceipt]) -> String {
        switch receipts.count {
        case 0:
            return "Today's Pick is \(candidate.title) by \(candidate.artistName). Your strongest signals are still taking shape, so this is a lower-confidence pick."
        case 1:
            return "Today's Pick is \(candidate.title) by \(candidate.artistName), grounded in your log for \(receipts[0].sourceAlbumTitle)."
        default:
            return "Today's Pick is \(candidate.title) by \(candidate.artistName), grounded in your logs for \(receipts[0].sourceAlbumTitle) and \(receipts[1].sourceAlbumTitle)."
        }
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
    private static func anchorInput(from profile: RecommendationAnchorProfile) -> RecommendationAnchorInput {
        let album = profile.album
        return RecommendationAnchorInput(
            logIDs: profile.logIDs,
            albumCatalogID: album.appleMusicID,
            albumTitle: album.title,
            artistName: album.artistName,
            genreName: album.genreName,
            tags: profile.tags,
            strength: profile.strength
        )
    }

    private static func uniqueNormalizedValues(_ values: [String]) -> [String] {
        var valuesByKey: [String: String] = [:]
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            valuesByKey[trimmed.normalizedRecommendationText] = valuesByKey[trimmed.normalizedRecommendationText] ?? trimmed
        }
        return valuesByKey.sorted { $0.key < $1.key }.map(\.value)
    }

    private static func candidateMetadataText(_ candidate: AlbumSearchResult) -> String {
        [candidate.title, candidate.artistName, candidate.genreName ?? ""]
            .joined(separator: " ")
            .normalizedRecommendationText
    }

    @MainActor
    private static func sameGenre(_ album: Album, _ candidate: AlbumSearchResult) -> Bool {
        guard let albumGenre = album.genreName?.normalizedRecommendationText,
              let candidateGenre = candidate.genreName?.normalizedRecommendationText,
              !albumGenre.isEmpty,
              !candidateGenre.isEmpty else { return false }
        return albumGenre == candidateGenre
    }

    @MainActor
    private static func sameEra(_ album: Album, _ candidate: AlbumSearchResult) -> Bool {
        guard let albumYear = album.releaseYear, let candidateYear = candidate.releaseYear else { return false }
        return albumYear.recommendationDecade == candidateYear.recommendationDecade
    }

    private static func feedbackMultiplier(
        feedback: RecommendationFeedback?,
        recommendationStatus: String
    ) -> Double {
        if let feedbackType = feedback.flatMap({ RecommendationFeedbackType(rawValue: $0.feedbackType) }) {
            switch feedbackType {
            case .liked, .listened: return 1
            case .savedForLater: return 0.5
            case .dismissed: return 0
            }
        }

        switch RecommendationStatus(rawValue: recommendationStatus) {
        case .accepted: return 1
        case .saved: return 0.5
        default: return 0
        }
    }

    @MainActor
    private static func isBetterReceiptLog(_ lhs: LogEntry, _ rhs: LogEntry) -> Bool {
        let lhsPriority = receiptPriority(lhs)
        let rhsPriority = receiptPriority(rhs)
        if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
        if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
        return lhs.loggedAt > rhs.loggedAt
    }

    @MainActor
    private static func receiptPriority(_ log: LogEntry) -> Int {
        if log.normalizedStandoutMoment != nil { return 0 }
        if !log.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 1 }
        if !log.favoriteTracks.isEmpty { return 2 }
        if !log.tags.isEmpty { return 3 }
        return 4
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
            strength: evidence.strength * evidence.confidence,
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
    let scoreBreakdown: RecommendationScoreBreakdown
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
