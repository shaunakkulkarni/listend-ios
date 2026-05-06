//
//  CatalogRecommendationCandidateProvider.swift
//  Listend
//
//  Created by Codex on 5/3/26.
//

import Foundation

struct RecommendationAnchorInput: Hashable {
    let logID: UUID
    let albumCatalogID: String?
    let albumTitle: String
    let artistName: String
    let genreName: String?
    let tags: [String]
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
        loggedAlbums: [RecommendationLoggedAlbumInput]
    ) async -> [AlbumSearchResult] {
        let queries = Self.searchQueries(anchors: anchors, evidence: evidence, limit: queryLimit)

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
        limit: Int = 5
    ) -> [String] {
        let anchorIDs = Set(anchors.map(\.logID))
        var queries: [String] = []

        appendFirst(from: rankedValues(anchors.compactMap(\.genreName)), to: &queries)
        appendFirst(from: rankedValues(anchors.map(\.artistName)), to: &queries)
        appendFirst(from: rankedValues(anchors.flatMap(\.tags)), to: &queries)

        let evidenceValues = evidence
            .filter { $0.isPositiveEvidence && anchorIDs.contains($0.logEntryID) }
            .sorted {
                if $0.strength == $1.strength {
                    return $0.dimensionName.normalizedCandidateQueryText < $1.dimensionName.normalizedCandidateQueryText
                }

                return $0.strength > $1.strength
            }
            .map(\.dimensionName)
        appendFirst(from: evidenceValues, to: &queries)

        let secondPassValues = rankedValues(anchors.compactMap(\.genreName) + anchors.flatMap(\.tags))
        for value in secondPassValues where queries.count < limit {
            append(value, to: &queries)
        }

        return Array(queries.prefix(limit))
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

    private static func rankedValues(_ values: [String]) -> [String] {
        var counts: [String: (value: String, count: Int)] = [:]

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty else {
                continue
            }

            let key = trimmed.normalizedCandidateQueryText
            let existing = counts[key]
            counts[key] = (existing?.value ?? trimmed, (existing?.count ?? 0) + 1)
        }

        return counts.values
            .sorted {
                if $0.count == $1.count {
                    return $0.value.normalizedCandidateQueryText < $1.value.normalizedCandidateQueryText
                }

                return $0.count > $1.count
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
