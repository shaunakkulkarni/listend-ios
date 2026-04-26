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
