//
//  RecommendationConstants.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

enum RecommendationStatus: String, Codable {
    case active
    case dismissed
    case saved
    case accepted
}

enum RecommendationFeedbackType: String, Codable, CaseIterable {
    case liked
    case dismissed
    case alreadyKnown
    case savedForLater
    case listened

    var resultingStatus: RecommendationStatus {
        switch self {
        case .liked, .listened:
            return .accepted
        case .dismissed, .alreadyKnown:
            return .dismissed
        case .savedForLater:
            return .saved
        }
    }
}

enum RecommendationSource: String, Codable {
    case applePersonalRecommendations
    case relatedAlbum
    case similarArtist
    case listendFallback
}

enum RecommendationFreshnessStatus: String, Codable {
    case appleFreshnessChecked
    case appleFreshnessUnavailable
}

enum TodayPickRecommendationMode: String, CaseIterable, Identifiable {
    case familiar
    case balanced
    case adventurous

    static let `default`: TodayPickRecommendationMode = .balanced

    init(rawValue: String?) {
        guard let rawValue, let mode = TodayPickRecommendationMode(rawValue: rawValue) else {
            self = .default
            return
        }

        self = mode
    }

    var id: String { rawValue }

    var userFacingTitle: String {
        switch self {
        case .familiar:
            return "Familiar"
        case .balanced:
            return "Balanced"
        case .adventurous:
            return "Adventurous"
        }
    }

    var userFacingDescription: String {
        switch self {
        case .familiar:
            return "Stays close to the artists, genres, eras, and tags you already love."
        case .balanced:
            return "Starts with new artists connected to the albums you love, then keeps quality in the mix."
        case .adventurous:
            return "Pushes further into new artists, always with a clear connection to your logs."
        }
    }
}

enum TodayPickPreferenceKey {
    static let recommendationMode = "todayPick.recommendationMode"
}
