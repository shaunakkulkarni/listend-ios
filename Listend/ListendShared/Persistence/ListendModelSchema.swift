//
//  ListendModelSchema.swift
//  Listend
//

import SwiftData

enum ListendModelSchema {
    static let modelTypes: [any PersistentModel.Type] = [
        Album.self,
        LogEntry.self,
        TasteDimension.self,
        TasteEvidence.self,
        SoundPrintPersona.self,
        TasteAvoidanceSignal.self,
        Recommendation.self,
        RecommendationReceipt.self,
        RecommendationFeedback.self,
        RecentlyPlayedAlbumSnapshot.self,
        AppleMusicRecentPlaySnapshot.self,
        AlbumTrack.self
    ]

    static let schema = Schema(modelTypes)
}
