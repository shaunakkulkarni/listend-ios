//
//  DiscoveryCandidate.swift
//  Listend
//

import Foundation

struct RelatedAlbumLookupResult: Sendable {
    let anchorIndex: Int
    let albums: [AlbumSearchResult]
}

/// Candidate-only discovery context. Persistence deliberately stays on Recommendation,
/// its source, explanation, and receipts so a relaunch never depends on this structure.
struct DiscoveryCandidate {
    let album: AlbumSearchResult
    var source: RecommendationSource
    var anchorAlbumKeys: Set<String>
    var anchorLogIDs: Set<UUID>
    var isKnownArtist: Bool?

    var distinctAnchorCount: Int { anchorAlbumKeys.count }

    mutating func merge(_ other: DiscoveryCandidate) {
        anchorAlbumKeys.formUnion(other.anchorAlbumKeys)
        anchorLogIDs.formUnion(other.anchorLogIDs)
        isKnownArtist = isKnownArtist ?? other.isKnownArtist
        if other.source.discoveryPriority > source.discoveryPriority {
            source = other.source
        }
    }
}

extension RecommendationSource {
    var isRelationshipDiscovery: Bool {
        self == .relatedAlbum || self == .similarArtist
    }

    var discoveryPriority: Int {
        switch self {
        case .relatedAlbum: 3
        case .similarArtist: 2
        case .applePersonalRecommendations: 1
        case .listendFallback: 0
        }
    }
}
