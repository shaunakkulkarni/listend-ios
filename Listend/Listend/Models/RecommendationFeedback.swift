//
//  RecommendationFeedback.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

import Foundation
import SwiftData

@Model
final class RecommendationFeedback {
    var id: UUID
    var recommendationID: UUID
    var feedbackType: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        recommendationID: UUID,
        feedbackType: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recommendationID = recommendationID
        self.feedbackType = feedbackType
        self.createdAt = createdAt
    }
}
