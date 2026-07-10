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
    case savedForLater
    case listened

    var resultingStatus: RecommendationStatus {
        switch self {
        case .liked, .listened:
            return .accepted
        case .dismissed:
            return .dismissed
        case .savedForLater:
            return .saved
        }
    }
}

enum RecommendationSource: String, Codable {
    case applePersonalRecommendations
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
            return "Uses a mix of familiarity and discovery, matching Today's Pick's original behavior."
        case .adventurous:
            return "Explores new artists and adjacent sounds, always tied back to your logs."
        }
    }
}

enum TodayPickPreferenceKey {
    static let recommendationMode = "todayPick.recommendationMode"
}
