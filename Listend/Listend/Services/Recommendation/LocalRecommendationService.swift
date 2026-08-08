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
    let artistAffinity: Double
    let artistNovelty: Double
    let genreNovelty: Double
    let eraNovelty: Double
    let recentArtistRepetition: Double
    let genreAvoidance: Double
    let feedbackAffinity: Double
    let relationshipAffinity: Double
    let crossAnchorConsensus: Double

    var total: Double {
        (base + genreAffinity + eraAffinity + tagAffinity + artistAffinity + artistNovelty
            + genreNovelty + eraNovelty + recentArtistRepetition + genreAvoidance + feedbackAffinity
            + relationshipAffinity + crossAnchorConsensus)
            .clamped(to: 0...1)
    }
}

private struct TodayPickScoringPolicy {
    let genreAffinityMultiplier: Double
    let genreAffinityCap: Double
    let eraAffinityMultiplier: Double
    let eraAffinityCap: Double
    let tagAffinityMultiplier: Double
    let tagAffinityCap: Double
    let maximumArtistAffinity: Double
    let artistNoveltyBonus: Double
    let genreNoveltyBonus: Double
    let eraNoveltyBonus: Double

    static func policy(for mode: TodayPickRecommendationMode) -> TodayPickScoringPolicy {
        switch mode {
        case .familiar:
            return TodayPickScoringPolicy(
                genreAffinityMultiplier: 1.25,
                genreAffinityCap: 0.35,
                eraAffinityMultiplier: 1.25,
                eraAffinityCap: 0.15,
                tagAffinityMultiplier: 1.50,
                tagAffinityCap: 0.075,
                maximumArtistAffinity: 0.12,
                artistNoveltyBonus: 0,
                genreNoveltyBonus: 0,
                eraNoveltyBonus: 0
            )
        case .balanced:
            return TodayPickScoringPolicy(
                genreAffinityMultiplier: 1,
                genreAffinityCap: 0.30,
                eraAffinityMultiplier: 1,
                eraAffinityCap: .greatestFiniteMagnitude,
                tagAffinityMultiplier: 1,
                tagAffinityCap: 0.05,
                maximumArtistAffinity: 0,
                artistNoveltyBonus: 0.05,
                genreNoveltyBonus: 0,
                eraNoveltyBonus: 0
            )
        case .adventurous:
            return TodayPickScoringPolicy(
                genreAffinityMultiplier: 0.60,
                genreAffinityCap: .greatestFiniteMagnitude,
                eraAffinityMultiplier: 0.50,
                eraAffinityCap: .greatestFiniteMagnitude,
                tagAffinityMultiplier: 1,
                tagAffinityCap: 0.05,
                maximumArtistAffinity: 0,
                artistNoveltyBonus: 0.15,
                genreNoveltyBonus: 0.08,
                eraNoveltyBonus: 0.06
            )
        }
    }
}

struct LocalRecommendationService {
    /// When this many viable new-artist candidates exist, Balanced does not trade
    /// discovery away merely to keep a familiar artist in the pool.
    static let balancedUnfamiliarArtistHardFilterMinimum = 5
    private static let relationshipAnchorLimit = 3
    private static let relatedAlbumLimitPerAnchor = 10
    private static let freshnessVerificationCandidateLimit = 8
    private static let minimumViableRelationshipCandidateCount = 1
    private static let similarArtistLimitPerAnchor = 3
    private static let similarArtistAlbumLimit = 4

    private let catalogAlbums: [AlbumSearchResult]
    private let candidateProvider: CatalogRecommendationCandidateProvider?
    private let catalogService: AlbumCatalogServiceProtocol?
    private let appleMusicService: AppleMusicRecommendationServiceProtocol?
    private let appleMusicCandidateLimit: Int

    init(
        catalogAlbums: [AlbumSearchResult] = MockAlbumCatalogService.defaultAlbums,
        appleMusicService: AppleMusicRecommendationServiceProtocol? = nil,
        appleMusicCandidateLimit: Int = 20
    ) {
        self.catalogAlbums = catalogAlbums
        candidateProvider = nil
        catalogService = nil
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
        self.catalogService = catalogService
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
    func currentOrGenerateRecommendation(
        in modelContext: ModelContext,
        mode: TodayPickRecommendationMode = .balanced
    ) async throws -> Recommendation {
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
            mode: mode,
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
        anchorProfiles: [RecommendationAnchorProfile],
        mode: TodayPickRecommendationMode = .balanced
    ) -> ScoredRecommendationCandidate? {
        bestDiscoveryCandidate(
            (candidates ?? catalogAlbums).map {
                DiscoveryCandidate(album: $0, source: .listendFallback, anchorAlbumKeys: [], anchorLogIDs: [], isKnownArtist: nil)
            },
            logs: logs,
            recommendations: recommendations,
            feedback: feedback,
            anchorProfiles: anchorProfiles,
            mode: mode
        )
    }

    @MainActor
    private func rankedDiscoveryCandidates(
        _ candidates: [DiscoveryCandidate],
        logs: [LogEntry],
        recommendations: [Recommendation],
        feedback: [RecommendationFeedback],
        anchorProfiles: [RecommendationAnchorProfile],
        mode: TodayPickRecommendationMode
    ) -> [ScoredRecommendationCandidate] {
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
        let knownArtists = knownArtistNames(
            logs: logs,
            recommendations: recommendations,
            feedback: feedback,
            anchorProfiles: anchorProfiles
        )
        let eligibleCandidates = candidates
            .filter { candidate in
                !loggedAlbums.contains { Self.matches($0, candidate.album) }
            }
            .filter { candidate in
                !recommendedAlbums.contains { Self.matches($0, candidate.album) }
            }
        let unfamiliarEligibleCandidates = eligibleCandidates.filter {
            !($0.isKnownArtist ?? knownArtists.contains($0.album.artistName.normalizedRecommendationText))
        }
        let modeCandidates: [DiscoveryCandidate]
        switch mode {
        case .balanced where unfamiliarEligibleCandidates.count >= Self.balancedUnfamiliarArtistHardFilterMinimum:
            modeCandidates = unfamiliarEligibleCandidates
        case .adventurous:
            modeCandidates = unfamiliarEligibleCandidates
        default:
            modeCandidates = eligibleCandidates
        }

        return modeCandidates
            .map { candidate in
                score(
                    candidate.album,
                    anchorProfiles: anchorProfiles,
                    recommendations: recommendations,
                    latestFeedbackByRecommendationID: latestFeedbackByRecommendationID,
                    recentlyRecommendedArtists: recentlyRecommendedArtists,
                    mode: mode,
                    discoveryCandidate: candidate
                )
            }
            .filter { candidate in mode != .adventurous || !candidate.receipts.isEmpty }
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
    }

    @MainActor
    private func bestDiscoveryCandidate(
        _ candidates: [DiscoveryCandidate],
        logs: [LogEntry],
        recommendations: [Recommendation],
        feedback: [RecommendationFeedback],
        anchorProfiles: [RecommendationAnchorProfile],
        mode: TodayPickRecommendationMode
    ) -> ScoredRecommendationCandidate? {
        rankedDiscoveryCandidates(
            candidates,
            logs: logs,
            recommendations: recommendations,
            feedback: feedback,
            anchorProfiles: anchorProfiles,
            mode: mode
        ).first
    }

    @MainActor
    private func scoredRecommendationInput(
        logs: [LogEntry],
        evidence: [TasteEvidence],
        recommendations: [Recommendation],
        feedback: [RecommendationFeedback],
        anchorProfiles: [RecommendationAnchorProfile],
        mode: TodayPickRecommendationMode,
        in modelContext: ModelContext
    ) async throws -> PendingRecommendationInput {
        if let appleMusicService {
            do {
                let candidates = try await discoveryCandidates(
                    service: appleMusicService,
                    logs: logs,
                    recommendations: recommendations,
                    feedback: feedback,
                    anchorProfiles: anchorProfiles,
                    mode: mode,
                    in: modelContext
                )

                if let scoredCandidate = bestDiscoveryCandidate(
                    candidates,
                    logs: logs,
                    recommendations: recommendations,
                    feedback: feedback,
                    anchorProfiles: anchorProfiles,
                    mode: mode
                ) {
                    return PendingRecommendationInput(
                        scoredCandidate: scoredCandidate,
                        source: scoredCandidate.discoverySource,
                        freshnessStatus: .appleFreshnessChecked
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Relationship and personalized source failures are deliberately
                // isolated below. A freshness/auth failure lands here and falls
                // through to the existing Listend-only disclosure.
            }
        }

        return try await listendFallbackRecommendationInput(
            logs: logs,
            evidence: evidence,
            recommendations: recommendations,
            feedback: feedback,
            anchorProfiles: anchorProfiles,
            mode: mode
        )
    }

    @MainActor
    private func listendFallbackRecommendationInput(
        logs: [LogEntry],
        evidence: [TasteEvidence],
        recommendations: [Recommendation],
        feedback: [RecommendationFeedback],
        anchorProfiles: [RecommendationAnchorProfile],
        mode: TodayPickRecommendationMode
    ) async throws -> PendingRecommendationInput {
        let candidates = await recommendationCandidates(
            logs: logs,
            evidence: evidence,
            anchorProfiles: anchorProfiles,
            mode: mode
        )

        let discoveryCandidates = candidates.map {
            DiscoveryCandidate(
                album: $0,
                source: .listendFallback,
                anchorAlbumKeys: [],
                anchorLogIDs: [],
                isKnownArtist: nil
            )
        }
        guard let scoredCandidate = bestDiscoveryCandidate(
            discoveryCandidates,
            logs: logs,
            recommendations: recommendations,
            feedback: feedback,
            anchorProfiles: anchorProfiles,
            mode: mode
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
    private func discoveryCandidates(
        service: AppleMusicRecommendationServiceProtocol,
        logs: [LogEntry],
        recommendations: [Recommendation],
        feedback: [RecommendationFeedback],
        anchorProfiles: [RecommendationAnchorProfile],
        mode: TodayPickRecommendationMode,
        in modelContext: ModelContext
    ) async throws -> [DiscoveryCandidate] {
        let recentAlbums = try await service.recentlyPlayedAlbums(limit: appleMusicCandidateLimit)
        try AppleMusicRecentPlaySnapshotStore.recordRecentlyPlayedAlbums(recentAlbums, in: modelContext)
        let recentSnapshots = try AppleMusicRecentPlaySnapshotStore.recentlyObservedAlbums(in: modelContext)
        let anchors = try await resolvedDiscoveryAnchors(from: anchorProfiles)
        var checkedCandidates: [DiscoveryCandidate] = []

        let relatedLookupResults = try await withThrowingTaskGroup(of: RelatedAlbumLookupResult.self) { group in
            for (anchorIndex, (_, anchor)) in anchors.enumerated() {
                group.addTask {
                    do {
                        let albums = try await service.relatedAlbums(
                            for: anchor,
                            limit: Self.relatedAlbumLimitPerAnchor
                        )
                        return RelatedAlbumLookupResult(anchorIndex: anchorIndex, albums: albums)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return RelatedAlbumLookupResult(anchorIndex: anchorIndex, albums: [])
                    }
                }
            }

            var results: [RelatedAlbumLookupResult] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.anchorIndex < $1.anchorIndex }
        }
        for result in relatedLookupResults {
            let profile = anchors[result.anchorIndex].0
            checkedCandidates.append(contentsOf: result.albums.map {
                DiscoveryCandidate(album: $0, source: .relatedAlbum, anchorAlbumKeys: [profile.albumKey], anchorLogIDs: Set(profile.logIDs), isKnownArtist: nil)
            })
        }

        let localKnownArtists = knownArtistNames(
            logs: logs,
            recommendations: recommendations,
            feedback: feedback,
            anchorProfiles: anchorProfiles,
            recentAlbums: recentAlbums,
            recentSnapshots: recentSnapshots
        )
        let artistLibraryResultCache = ArtistLibraryResultCache()
        var verifiedRelationshipCandidates = try await verifiedDiscoveryCandidates(
            checkedCandidates,
            service: service,
            recentAlbums: recentAlbums,
            recentSnapshots: recentSnapshots,
            localKnownArtists: localKnownArtists,
            artistLibraryResultCache: artistLibraryResultCache
        )
        if rankedDiscoveryCandidates(
            verifiedRelationshipCandidates,
            logs: logs,
            recommendations: recommendations,
            feedback: feedback,
            anchorProfiles: anchorProfiles,
            mode: mode
        ).count < Self.minimumViableRelationshipCandidateCount {
            for (profile, anchor) in anchors {
                do {
                    let similar = try await service.similarArtistAlbums(
                        for: anchor,
                        artistLimit: Self.similarArtistLimitPerAnchor,
                        albumLimit: Self.similarArtistAlbumLimit
                    )
                    let similarCandidates = similar.map {
                        DiscoveryCandidate(album: $0, source: .similarArtist, anchorAlbumKeys: [profile.albumKey], anchorLogIDs: Set(profile.logIDs), isKnownArtist: nil)
                    }
                    let netNewSimilarCandidates = Self.netNewDiscoveryCandidates(
                        similarCandidates,
                        excluding: checkedCandidates
                    )
                    checkedCandidates = Self.mergeDiscoveryCandidates(checkedCandidates + similarCandidates)
                    verifiedRelationshipCandidates = Self.mergeVerifiedDiscoveryCandidates(
                        verifiedRelationshipCandidates,
                        with: similarCandidates
                    )
                    if !netNewSimilarCandidates.isEmpty {
                        let verifiedSimilarCandidates = try await verifiedDiscoveryCandidates(
                            netNewSimilarCandidates,
                            service: service,
                            recentAlbums: recentAlbums,
                            recentSnapshots: recentSnapshots,
                            localKnownArtists: localKnownArtists,
                            artistLibraryResultCache: artistLibraryResultCache
                        )
                        verifiedRelationshipCandidates = Self.mergeVerifiedDiscoveryCandidates(
                            verifiedRelationshipCandidates,
                            with: verifiedSimilarCandidates
                        )
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Similar-artist expansion is optional after direct relatives.
                }
            }
        }

        if !rankedDiscoveryCandidates(
            verifiedRelationshipCandidates,
            logs: logs,
            recommendations: recommendations,
            feedback: feedback,
            anchorProfiles: anchorProfiles,
            mode: mode
        ).isEmpty {
            return verifiedRelationshipCandidates
        }

        do {
            let personalRecommendations = try await service.recommendedAlbums(limit: appleMusicCandidateLimit)
            let personalCandidates = personalRecommendations.prefix(appleMusicCandidateLimit).map {
                DiscoveryCandidate(album: $0, source: .applePersonalRecommendations, anchorAlbumKeys: [], anchorLogIDs: [], isKnownArtist: nil)
            }
            let netNewPersonalCandidates = Self.netNewDiscoveryCandidates(
                personalCandidates,
                excluding: checkedCandidates
            )
            checkedCandidates = Self.mergeDiscoveryCandidates(checkedCandidates + personalCandidates)
            verifiedRelationshipCandidates = Self.mergeVerifiedDiscoveryCandidates(
                verifiedRelationshipCandidates,
                with: personalCandidates
            )
            if !netNewPersonalCandidates.isEmpty {
                let verifiedPersonalCandidates = try await verifiedDiscoveryCandidates(
                    netNewPersonalCandidates,
                    service: service,
                    recentAlbums: recentAlbums,
                    recentSnapshots: recentSnapshots,
                    localKnownArtists: localKnownArtists,
                    artistLibraryResultCache: artistLibraryResultCache
                )
                verifiedRelationshipCandidates = Self.mergeVerifiedDiscoveryCandidates(
                    verifiedRelationshipCandidates,
                    with: verifiedPersonalCandidates
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Personal recommendations supplement, but never replace, relationship results.
        }
        return verifiedRelationshipCandidates
    }

    @MainActor
    private func verifiedDiscoveryCandidates(
        _ candidates: [DiscoveryCandidate],
        service: AppleMusicRecommendationServiceProtocol,
        recentAlbums: [AlbumSearchResult],
        recentSnapshots: [AppleMusicRecentPlaySnapshot],
        localKnownArtists: Set<String>,
        artistLibraryResultCache: ArtistLibraryResultCache
    ) async throws -> [DiscoveryCandidate] {
        let freshnessEligibleCandidates = Self.mergeDiscoveryCandidates(candidates)
            .filter { candidate in
                !recentAlbums.contains(where: { Self.matches($0, candidate.album) })
                    && !recentSnapshots.contains(where: { AppleMusicRecentPlaySnapshotStore.matches($0, candidate.album) })
            }
            .prefix(Self.freshnessVerificationCandidateLimit)

        let albumCheckedCandidates = try await withThrowingTaskGroup(of: AppleMusicLibraryCheckResult?.self) { group in
            for (index, candidate) in freshnessEligibleCandidates.enumerated() {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        guard !(try await service.containsInLibrary(candidate.album)) else { return nil }
                        return AppleMusicLibraryCheckResult(index: index, candidate: candidate)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // A failed album membership check excludes only this candidate.
                        return nil
                    }
                }
            }

            var checkedCandidates: [AppleMusicLibraryCheckResult] = []
            for try await checkedCandidate in group {
                if let checkedCandidate {
                    checkedCandidates.append(checkedCandidate)
                }
            }
            return checkedCandidates
                .sorted { $0.index < $1.index }
        }

        var artistResultsByKey: [String: Bool] = [:]
        var unknownArtistsByKey: [String: String] = [:]
        for result in albumCheckedCandidates {
            let artistKey = result.candidate.album.artistName.normalizedRecommendationText
            if localKnownArtists.contains(artistKey) {
                artistResultsByKey[artistKey] = true
            } else if let cachedResult = await artistLibraryResultCache.result(for: artistKey) {
                artistResultsByKey[artistKey] = cachedResult
            } else {
                unknownArtistsByKey[artistKey] = result.candidate.album.artistName
            }
        }

        let fetchedArtistResults = try await withThrowingTaskGroup(of: AppleMusicArtistLibraryCheckResult.self) { group in
            for (artistKey, artistName) in unknownArtistsByKey {
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        return AppleMusicArtistLibraryCheckResult(
                            artistKey: artistKey,
                            isKnownArtist: try await service.containsArtistInLibrary(named: artistName)
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        // Without an artist-library result, keep albums but treat the artist as familiar.
                        return AppleMusicArtistLibraryCheckResult(artistKey: artistKey, isKnownArtist: true)
                    }
                }
            }

            var results: [AppleMusicArtistLibraryCheckResult] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
        for result in fetchedArtistResults {
            await artistLibraryResultCache.store(result.isKnownArtist, for: result.artistKey)
            artistResultsByKey[result.artistKey] = result.isKnownArtist
        }

        return albumCheckedCandidates.map { result in
            var candidate = result.candidate
            let artistKey = candidate.album.artistName.normalizedRecommendationText
            candidate.isKnownArtist = artistResultsByKey[artistKey] ?? true
            return candidate
        }
    }

    @MainActor
    private func recommendationCandidates(
        logs: [LogEntry],
        evidence: [TasteEvidence],
        anchorProfiles: [RecommendationAnchorProfile],
        mode: TodayPickRecommendationMode
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
            loggedAlbums: loggedAlbumInputs,
            mode: mode
        )
    }

    @MainActor
    private func score(
        _ candidate: AlbumSearchResult,
        anchorProfiles: [RecommendationAnchorProfile],
        recommendations: [Recommendation],
        latestFeedbackByRecommendationID: [UUID: RecommendationFeedback],
        recentlyRecommendedArtists: Set<String>,
        mode: TodayPickRecommendationMode,
        discoveryCandidate: DiscoveryCandidate? = nil
    ) -> ScoredRecommendationCandidate {
        let breakdown = recommendationScoreBreakdown(
            for: candidate,
            anchorProfiles: anchorProfiles,
            recommendations: recommendations,
            latestFeedbackByRecommendationID: latestFeedbackByRecommendationID,
            recentlyRecommendedArtists: recentlyRecommendedArtists,
            mode: mode,
            discoveryCandidate: discoveryCandidate
        )
        let relevantProfiles: [RecommendationAnchorProfile]
        if let discoveryCandidate,
           discoveryCandidate.source.isRelationshipDiscovery,
           !discoveryCandidate.anchorAlbumKeys.isEmpty {
            relevantProfiles = candidateProfiles(discoveryCandidate, in: anchorProfiles)
        } else {
            relevantProfiles = candidateRelevantPositiveProfiles(candidate, profiles: anchorProfiles)
        }
        let receiptCandidates = relevantProfiles.compactMap { profile -> (PendingRecommendationReceipt, RecommendationAnchorProfile)? in
            guard let receipt = makeReceipt(from: profile, candidate: candidate) else { return nil }
            return (receipt, profile)
        }
        let receiptsAndProfiles = receiptCandidates.prefix(3)
        let receipts = receiptsAndProfiles.map(\.0)
        // Keep confidence behavior tied to the original two strongest profiles;
        // the third snapshot only adds a more useful receipt surface.
        let receiptProfiles = receiptCandidates.prefix(2).map(\.1)
        let confidenceCap: Double = if receiptCandidates.isEmpty {
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
            explanation: explanation(candidate: candidate, receipts: receipts, source: discoveryCandidate?.source),
            receipts: receipts,
            scoreBreakdown: breakdown,
            discoverySource: discoveryCandidate?.source ?? .listendFallback
        )
    }

    @MainActor
    func recommendationScoreBreakdown(
        for candidate: AlbumSearchResult,
        anchorProfiles: [RecommendationAnchorProfile],
        recommendations: [Recommendation] = [],
        feedback: [RecommendationFeedback] = [],
        mode: TodayPickRecommendationMode = .balanced
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
            recentlyRecommendedArtists: recentArtists,
            mode: mode
        )
    }

    @MainActor
    private func recommendationScoreBreakdown(
        for candidate: AlbumSearchResult,
        anchorProfiles: [RecommendationAnchorProfile],
        recommendations: [Recommendation],
        latestFeedbackByRecommendationID: [UUID: RecommendationFeedback],
        recentlyRecommendedArtists: Set<String>,
        mode: TodayPickRecommendationMode,
        discoveryCandidate: DiscoveryCandidate? = nil
    ) -> RecommendationScoreBreakdown {
        let policy = TodayPickScoringPolicy.policy(for: mode)
        let positiveProfiles = anchorProfiles.filter(\.isPositive)
        let genreProfiles = positiveProfiles.filter { Self.sameGenre($0.album, candidate) }
            .sorted { $0.strength > $1.strength }
        let genreStrengths = genreProfiles.prefix(2).map(\.strength)
        let balancedGenreAffinity = min(
            (genreStrengths.isEmpty ? 0 : genreStrengths.reduce(0, +) / Double(genreStrengths.count) * 0.25)
                + (genreProfiles.count >= 2 ? 0.05 : 0),
            0.30
        )
        let genreAffinity = min(
            balancedGenreAffinity * policy.genreAffinityMultiplier,
            policy.genreAffinityCap
        )
        let balancedEraAffinity = positiveProfiles
            .filter { Self.sameEra($0.album, candidate) }
            .map(\.strength)
            .max()
            .map { $0 * 0.12 } ?? 0
        let eraAffinity = min(
            balancedEraAffinity * policy.eraAffinityMultiplier,
            policy.eraAffinityCap
        )
        let candidateText = Self.candidateMetadataText(candidate)
        let balancedTagAffinity = min(positiveProfiles.compactMap { profile in
            profile.tags.contains { candidateText.contains($0.normalizedRecommendationText) }
                ? profile.strength * 0.05
                : nil
        }.max() ?? 0, 0.05)
        let tagAffinity = min(
            balancedTagAffinity * policy.tagAffinityMultiplier,
            policy.tagAffinityCap
        )
        let candidateArtist = candidate.artistName.normalizedRecommendationText
        let sameArtistStrength = positiveProfiles
            .filter { $0.album.artistName.normalizedRecommendationText == candidateArtist }
            .map(\.strength)
            .max() ?? 0
        let artistAffinity = min(
            sameArtistStrength * policy.maximumArtistAffinity,
            policy.maximumArtistAffinity
        )
        let knownArtists = Set(anchorProfiles.map { $0.album.artistName.normalizedRecommendationText }
            + recommendations.compactMap { $0.album?.artistName.normalizedRecommendationText })
        let artistNovelty = knownArtists.contains(candidateArtist) ? 0 : policy.artistNoveltyBonus
        let hasKnownCandidateGenre = !(candidate.genreName?.normalizedRecommendationText.isEmpty ?? true)
        let genreNovelty = mode == .adventurous
            && !positiveProfiles.isEmpty
            && hasKnownCandidateGenre
            && genreProfiles.isEmpty
            ? policy.genreNoveltyBonus
            : 0
        let hasKnownCandidateEra = candidate.releaseYear != nil
        let hasMatchingEra = positiveProfiles.contains { Self.sameEra($0.album, candidate) }
        let eraNovelty = mode == .adventurous
            && !positiveProfiles.isEmpty
            && hasKnownCandidateEra
            && !hasMatchingEra
            ? policy.eraNoveltyBonus
            : 0
        let recentArtistRepetition = recentlyRecommendedArtists.contains(candidateArtist) ? -0.10 : 0
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
        let relationshipAffinity: Double
        let crossAnchorConsensus: Double
        if let discoveryCandidate, discoveryCandidate.source.isRelationshipDiscovery {
            let relationshipStrength = candidateProfiles(discoveryCandidate, in: anchorProfiles)
                .map(\.strength)
                .max() ?? 0
            relationshipAffinity = min(relationshipStrength * 0.08, 0.08)
            crossAnchorConsensus = discoveryCandidate.distinctAnchorCount >= 2 ? 0.06 : 0
        } else {
            relationshipAffinity = 0
            crossAnchorConsensus = 0
        }

        return RecommendationScoreBreakdown(
            base: 0.20,
            genreAffinity: genreAffinity,
            eraAffinity: eraAffinity,
            tagAffinity: tagAffinity,
            artistAffinity: artistAffinity,
            artistNovelty: artistNovelty,
            genreNovelty: genreNovelty,
            eraNovelty: eraNovelty,
            recentArtistRepetition: recentArtistRepetition,
            genreAvoidance: genreAvoidance,
            feedbackAffinity: feedbackAffinity,
            relationshipAffinity: relationshipAffinity,
            crossAnchorConsensus: crossAnchorConsensus
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
    private func candidateProfiles(
        _ candidate: DiscoveryCandidate,
        in profiles: [RecommendationAnchorProfile]
    ) -> [RecommendationAnchorProfile] {
        profiles.filter { candidate.anchorAlbumKeys.contains($0.albumKey) }
            .sorted {
                $0.strength == $1.strength
                    ? $0.albumKey < $1.albumKey
                    : $0.strength > $1.strength
            }
    }

    @MainActor
    private func knownArtistNames(
        logs: [LogEntry],
        recommendations: [Recommendation],
        feedback: [RecommendationFeedback],
        anchorProfiles: [RecommendationAnchorProfile],
        recentAlbums: [AlbumSearchResult] = [],
        recentSnapshots: [AppleMusicRecentPlaySnapshot] = []
    ) -> Set<String> {
        let alreadyKnownRecommendationIDs = Set(feedback.compactMap { feedback in
            RecommendationFeedbackType(rawValue: feedback.feedbackType) == .alreadyKnown
                ? feedback.recommendationID
                : nil
        })
        let alreadyKnownArtists = recommendations
            .filter { alreadyKnownRecommendationIDs.contains($0.id) }
            .compactMap { $0.album?.artistName }
        let artistNames = logs.compactMap { $0.album?.artistName }
            + anchorProfiles.map { $0.album.artistName }
            + alreadyKnownArtists
            + recentAlbums.map(\.artistName)
            + recentSnapshots.map(\.artistName)
        return Set(artistNames.map(\.normalizedRecommendationText))
    }

    @MainActor
    private func resolvedDiscoveryAnchors(
        from profiles: [RecommendationAnchorProfile]
    ) async throws -> [(RecommendationAnchorProfile, AlbumSearchResult)] {
        var resolved: [(RecommendationAnchorProfile, AlbumSearchResult)] = []
        for profile in profiles.filter(\.isPositive).prefix(Self.relationshipAnchorLimit) {
            if let catalogID = profile.album.appleMusicID?.trimmingCharacters(in: .whitespacesAndNewlines), !catalogID.isEmpty {
                resolved.append((profile, AlbumSearchResult(
                    id: catalogID,
                    title: profile.album.title,
                    artistName: profile.album.artistName,
                    releaseYear: profile.album.releaseYear,
                    genreName: profile.album.genreName,
                    artworkURL: profile.album.artworkURL
                )))
                continue
            }

            guard let catalogService else { continue }
            do {
                let query = "\(profile.album.title) \(profile.album.artistName)"
                if let exact = try await catalogService.searchAlbums(query: query).first(where: {
                    $0.title.normalizedRecommendationText == profile.album.title.normalizedRecommendationText
                        && $0.artistName.normalizedRecommendationText == profile.album.artistName.normalizedRecommendationText
                }) {
                    resolved.append((profile, exact))
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // An unresolved local anchor simply skips relationship discovery.
            }
        }
        return resolved
    }

    static func mergeDiscoveryCandidates(_ candidates: [DiscoveryCandidate]) -> [DiscoveryCandidate] {
        var mergedCandidates: [DiscoveryCandidate] = []
        for candidate in candidates {
            if let index = mergedCandidates.indices.first(where: { index in
                Self.matches(mergedCandidates[index].album, candidate.album)
            }) {
                var existing = mergedCandidates[index]
                existing.merge(candidate)
                mergedCandidates[index] = existing
            } else {
                mergedCandidates.append(candidate)
            }
        }
        return mergedCandidates.sorted { lhs, rhs in
            if lhs.album.catalogID != rhs.album.catalogID {
                return lhs.album.catalogID < rhs.album.catalogID
            }
            return "\(lhs.album.artistName.normalizedRecommendationText)|\(lhs.album.title.normalizedRecommendationText)"
                < "\(rhs.album.artistName.normalizedRecommendationText)|\(rhs.album.title.normalizedRecommendationText)"
        }
    }

    private static func netNewDiscoveryCandidates(
        _ candidates: [DiscoveryCandidate],
        excluding checkedCandidates: [DiscoveryCandidate]
    ) -> [DiscoveryCandidate] {
        mergeDiscoveryCandidates(candidates).filter { candidate in
            !checkedCandidates.contains { Self.matches($0.album, candidate.album) }
        }
    }

    private static func mergeVerifiedDiscoveryCandidates(
        _ verifiedCandidates: [DiscoveryCandidate],
        with candidates: [DiscoveryCandidate]
    ) -> [DiscoveryCandidate] {
        mergeDiscoveryCandidates(verifiedCandidates + candidates)
            .filter { $0.isKnownArtist != nil }
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

    private func explanation(
        candidate: AlbumSearchResult,
        receipts: [PendingRecommendationReceipt],
        source: RecommendationSource?
    ) -> String {
        if source == .relatedAlbum, let receipt = receipts.first {
            return "Today's Pick is \(candidate.title) by \(candidate.artistName), branching from your log for \(receipt.sourceAlbumTitle)."
        }
        if source == .similarArtist, receipts.count >= 2 {
            return "Today's Pick is \(candidate.title) by \(candidate.artistName), a bridge from your logs for \(receipts[0].sourceAlbumTitle) and \(receipts[1].sourceAlbumTitle)."
        }
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
            case .dismissed, .alreadyKnown: return 0
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
    let candidate: DiscoveryCandidate
}

private struct AppleMusicArtistLibraryCheckResult {
    let artistKey: String
    let isKnownArtist: Bool
}

private actor ArtistLibraryResultCache {
    private var resultsByArtistKey: [String: Bool] = [:]

    func result(for artistKey: String) -> Bool? {
        resultsByArtistKey[artistKey]
    }

    func store(_ isKnownArtist: Bool, for artistKey: String) {
        resultsByArtistKey[artistKey] = isKnownArtist
    }
}

struct ScoredRecommendationCandidate {
    let album: AlbumSearchResult
    let score: Double
    let confidence: Double
    let explanation: String
    let receipts: [PendingRecommendationReceipt]
    let scoreBreakdown: RecommendationScoreBreakdown
    let discoverySource: RecommendationSource
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
