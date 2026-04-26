//
//  RecommendationReceipt.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

import Foundation
import SwiftData

@Model
final class RecommendationReceipt {
    var id: UUID
    var recommendationID: UUID
    var logEntryID: UUID
    var sourceAlbumTitle: String
    var sourceArtistName: String
    var sourceRating: Double
    var snippet: String
    var linkedDimension: String?

    init(
        id: UUID = UUID(),
        recommendationID: UUID,
        logEntryID: UUID,
        sourceAlbumTitle: String,
        sourceArtistName: String,
        sourceRating: Double,
        snippet: String,
        linkedDimension: String? = nil
    ) {
        self.id = id
        self.recommendationID = recommendationID
        self.logEntryID = logEntryID
        self.sourceAlbumTitle = sourceAlbumTitle
        self.sourceArtistName = sourceArtistName
        self.sourceRating = sourceRating
        self.snippet = snippet
        self.linkedDimension = linkedDimension
    }
}
