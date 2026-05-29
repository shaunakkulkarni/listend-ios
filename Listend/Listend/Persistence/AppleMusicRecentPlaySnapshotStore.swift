//
//  AppleMusicRecentPlaySnapshotStore.swift
//  Listend
//
//  Created by Codex on 5/28/26.
//

import Foundation
import SwiftData

enum AppleMusicRecentPlaySnapshotStore {
    static let freshnessWindow: TimeInterval = 90 * 86_400

    @MainActor
    static func recordRecentlyPlayedAlbums(
        _ albums: [AlbumSearchResult],
        observedAt: Date = Date(),
        in modelContext: ModelContext
    ) throws {
        let existingSnapshots = try modelContext.fetch(FetchDescriptor<AppleMusicRecentPlaySnapshot>())

        for album in albums {
            if let existingSnapshot = existingSnapshots.first(where: { matches($0, album) }) {
                existingSnapshot.catalogID = album.catalogID
                existingSnapshot.title = album.title
                existingSnapshot.artistName = album.artistName
                existingSnapshot.lastObservedAt = observedAt
            } else {
                modelContext.insert(
                    AppleMusicRecentPlaySnapshot(
                        catalogID: album.catalogID,
                        title: album.title,
                        artistName: album.artistName,
                        lastObservedAt: observedAt
                    )
                )
            }
        }

        try modelContext.save()
    }

    @MainActor
    static func recentlyObservedAlbums(
        now: Date = Date(),
        in modelContext: ModelContext
    ) throws -> [AppleMusicRecentPlaySnapshot] {
        let cutoff = now.addingTimeInterval(-freshnessWindow)
        return try modelContext.fetch(FetchDescriptor<AppleMusicRecentPlaySnapshot>())
            .filter { $0.lastObservedAt >= cutoff }
    }

    static func matches(_ snapshot: AppleMusicRecentPlaySnapshot, _ album: AlbumSearchResult) -> Bool {
        if snapshot.catalogID == album.catalogID {
            return true
        }

        return snapshot.title.normalizedAppleMusicFreshnessText == album.title.normalizedAppleMusicFreshnessText
            && snapshot.artistName.normalizedAppleMusicFreshnessText == album.artistName.normalizedAppleMusicFreshnessText
    }
}

extension String {
    var normalizedAppleMusicFreshnessText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
