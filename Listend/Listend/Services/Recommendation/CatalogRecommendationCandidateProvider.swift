//
//  CatalogRecommendationCandidateProvider.swift
//  Listend
//
//  Created by Codex on 5/3/26.
//

import Foundation

struct RecommendationAnchorInput: Hashable {
    let logIDs: [UUID]
    let albumCatalogID: String?
    let albumTitle: String
    let artistName: String
    let genreName: String?
    let tags: [String]
    let strength: Double
}

struct RecommendationEvidenceInput: Hashable {
    let logEntryID: UUID
    let dimensionName: String
    let strength: Double
    let isPositiveEvidence: Bool
}

struct RecommendationLoggedAlbumInput: Hashable {
    let catalogID: String?
    let title: String
    let artistName: String
}

struct CatalogRecommendationCandidateProvider {
    private static let genreStyleResolver = LocalGenreStyleResolver(
        catalog: TaxonomyCatalogLoader.shared
    )

    private let catalogService: AlbumCatalogServiceProtocol
    private let fallbackCandidates: [AlbumSearchResult]
    private let candidateLimit: Int
    private let queryLimit: Int

    init(
        catalogService: AlbumCatalogServiceProtocol,
        fallbackCandidates: [AlbumSearchResult] = MockAlbumCatalogService.defaultAlbums,
        candidateLimit: Int = 40,
        queryLimit: Int = 5
    ) {
        self.catalogService = catalogService
        self.fallbackCandidates = fallbackCandidates
        self.candidateLimit = candidateLimit
        self.queryLimit = queryLimit
    }

    func candidates(
        anchors: [RecommendationAnchorInput],
        evidence: [RecommendationEvidenceInput],
        loggedAlbums: [RecommendationLoggedAlbumInput],
        mode: TodayPickRecommendationMode = .balanced
    ) async -> [AlbumSearchResult] {
        let queries = Self.searchQueries(anchors: anchors, evidence: evidence, mode: mode, limit: queryLimit)

        guard !queries.isEmpty else {
            return fallbackCandidates
        }

        var candidates: [AlbumSearchResult] = []
        var seenCatalogIDs: Set<String> = []

        for query in queries {
            do {
                try Task.checkCancellation()
                let results = try await catalogService.searchAlbums(query: query)
                try Task.checkCancellation()

                for result in results where isUsable(result) && !isLogged(result, loggedAlbums: loggedAlbums) {
                    guard seenCatalogIDs.insert(result.catalogID).inserted else {
                        continue
                    }

                    candidates.append(result)

                    if candidates.count >= candidateLimit {
                        return candidates
                    }
                }
            } catch is CancellationError {
                return candidates
            } catch {
                continue
            }
        }

        return candidates.isEmpty ? fallbackCandidates : candidates
    }

    static func searchQueries(
        anchors: [RecommendationAnchorInput],
        evidence: [RecommendationEvidenceInput],
        mode: TodayPickRecommendationMode = .balanced,
        limit: Int = 5
    ) -> [String] {
        let positiveAnchors = anchors.filter { $0.strength > 0 }
        let anchorIDs = Set(positiveAnchors.flatMap(\.logIDs))
        var queries: [String] = []

        let genreValues = rankedWeightedValues(positiveAnchors.compactMap { anchor in
            anchor.genreName.map { ($0, anchor.strength) }
        })
        let artistValues = rankedWeightedValues(positiveAnchors.map { ($0.artistName, $0.strength) })
        let tagPairs = positiveAnchors.flatMap { anchor in
            anchor.tags.compactMap { tag in
                isApprovedCatalogQueryTag(tag) ? (tag, anchor.strength) : nil
            }
        }
        let tagValues = rankedWeightedValues(tagPairs)
        let evidencePairs = strongestWeightedValues(evidence
            .filter { $0.isPositiveEvidence && anchorIDs.contains($0.logEntryID) }
            .map { ($0.dimensionName, $0.strength) })
        let evidenceValues = rankedWeightedValuesKeepingStrongest(evidencePairs)

        let remainingValues: [String]

        switch mode {
        case .familiar:
            appendFirst(from: artistValues, to: &queries)
            appendFirst(from: genreValues, to: &queries)
            appendFirst(from: evidenceValues, to: &queries)
            appendFirst(from: tagValues, to: &queries)
            remainingValues = rankedWeightedValues(
                positiveAnchors.map { ($0.artistName, $0.strength) }
                    + positiveAnchors.compactMap { anchor in anchor.genreName.map { ($0, anchor.strength) } }
                    + evidencePairs
                    + tagPairs
            )
        case .balanced:
            appendFirst(from: genreValues, to: &queries)
            appendFirst(from: artistValues, to: &queries)
            appendFirst(from: evidenceValues, to: &queries)
            appendFirst(from: tagValues, to: &queries)
            remainingValues = rankedWeightedValues(
                positiveAnchors.compactMap { anchor in anchor.genreName.map { ($0, anchor.strength) } }
                    + positiveAnchors.map { ($0.artistName, $0.strength) }
                    + evidencePairs
                    + tagPairs
            )
        case .adventurous:
            appendFirst(from: genreValues, to: &queries)
            appendFirst(from: evidenceValues, to: &queries)
            appendFirst(from: tagValues, to: &queries)
            remainingValues = rankedWeightedValues(
                positiveAnchors.compactMap { anchor in anchor.genreName.map { ($0, anchor.strength) } }
                    + evidencePairs
                    + tagPairs
            )
        }

        for value in remainingValues where queries.count < limit {
            append(value, to: &queries)
        }

        return Array(queries.prefix(limit))
    }

    private static func isApprovedCatalogQueryTag(_ tag: String) -> Bool {
        let style: GenreStyleDefinition

        switch genreStyleResolver.resolveExact(tag) {
        case .canonical(let match), .exactAlias(_, let match):
            style = match
        case .unresolved:
            return false
        }

        return style.recommendationRole == .catalogQuery
    }

    private func isUsable(_ candidate: AlbumSearchResult) -> Bool {
        !candidate.catalogID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !candidate.artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isLogged(_ candidate: AlbumSearchResult, loggedAlbums: [RecommendationLoggedAlbumInput]) -> Bool {
        loggedAlbums.contains { loggedAlbum in
            if let catalogID = loggedAlbum.catalogID, catalogID == candidate.catalogID {
                return true
            }

            return loggedAlbum.title.normalizedCandidateQueryText == candidate.title.normalizedCandidateQueryText
                && loggedAlbum.artistName.normalizedCandidateQueryText == candidate.artistName.normalizedCandidateQueryText
        }
    }

    private static func rankedWeightedValues(_ values: [(String, Double)]) -> [String] {
        rankedWeightedValues(values, combine: +)
    }

    private static func rankedWeightedValuesKeepingStrongest(_ values: [(String, Double)]) -> [String] {
        rankedWeightedValues(values, combine: max)
    }

    private static func strongestWeightedValues(_ values: [(String, Double)]) -> [(String, Double)] {
        var strongestByKey: [String: (String, Double)] = [:]
        for (value, weight) in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, weight > 0 else { continue }
            let key = trimmed.normalizedCandidateQueryText
            if weight > (strongestByKey[key]?.1 ?? 0) {
                strongestByKey[key] = (trimmed, weight)
            }
        }
        return Array(strongestByKey.values)
    }

    private static func rankedWeightedValues(
        _ values: [(String, Double)],
        combine: (Double, Double) -> Double
    ) -> [String] {
        var weights: [String: (value: String, weight: Double)] = [:]

        for (value, weight) in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty, weight > 0 else {
                continue
            }

            let key = trimmed.normalizedCandidateQueryText
            let existing = weights[key]
            weights[key] = (existing?.value ?? trimmed, combine(existing?.weight ?? 0, weight))
        }

        return weights.values
            .sorted {
                if $0.weight == $1.weight {
                    return $0.value.normalizedCandidateQueryText < $1.value.normalizedCandidateQueryText
                }

                return $0.weight > $1.weight
            }
            .map(\.value)
    }

    private static func appendFirst(from values: [String], to queries: inout [String]) {
        guard let value = values.first else {
            return
        }

        append(value, to: &queries)
    }

    private static func append(_ value: String, to queries: inout [String]) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.normalizedCandidateQueryText

        guard !trimmed.isEmpty, !queries.contains(where: { $0.normalizedCandidateQueryText == normalized }) else {
            return
        }

        queries.append(trimmed)
    }
}

private extension String {
    var normalizedCandidateQueryText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
