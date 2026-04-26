//
//  Recommendation.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

import Foundation
import SwiftData

@Model
final class Recommendation {
    var id: UUID
    var album: Album?
    var score: Double
    var confidence: Double
    var status: String
    var explanationText: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        album: Album?,
        score: Double,
        confidence: Double,
        status: String = RecommendationStatus.active.rawValue,
        explanationText: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.album = album
        self.score = score
        self.confidence = confidence
        self.status = status
        self.explanationText = explanationText
        self.createdAt = createdAt
    }
}
