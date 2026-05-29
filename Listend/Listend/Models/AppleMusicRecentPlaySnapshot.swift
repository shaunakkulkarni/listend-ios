//
//  AppleMusicRecentPlaySnapshot.swift
//  Listend
//
//  Created by Codex on 5/28/26.
//

import Foundation
import SwiftData

@Model
final class AppleMusicRecentPlaySnapshot {
    var catalogID: String
    var title: String
    var artistName: String
    var lastObservedAt: Date

    init(
        catalogID: String,
        title: String,
        artistName: String,
        lastObservedAt: Date = Date()
    ) {
        self.catalogID = catalogID
        self.title = title
        self.artistName = artistName
        self.lastObservedAt = lastObservedAt
    }
}
