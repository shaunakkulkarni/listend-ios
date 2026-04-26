//
//  SeedData.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import Foundation
import SwiftData

enum SeedData {
    static func seedIfNeeded(in modelContext: ModelContext) {
        do {
            let albumCount = try modelContext.fetchCount(FetchDescriptor<Album>())
            let logCount = try modelContext.fetchCount(FetchDescriptor<LogEntry>())

            guard albumCount == 0, logCount == 0 else {
                return
            }

            let now = Date()
            let albums = [
                Album(title: "Dragon New Warm Mountain I Believe in You", artistName: "Big Thief", releaseYear: 2022, genreName: "Indie Folk"),
                Album(title: "Blonde", artistName: "Frank Ocean", releaseYear: 2016, genreName: "Alternative R&B"),
                Album(title: "Madvillainy", artistName: "Madvillain", releaseYear: 2004, genreName: "Hip-Hop"),
                Album(title: "Titanic Rising", artistName: "Weyes Blood", releaseYear: 2019, genreName: "Art Pop")
            ]

            for album in albums {
                modelContext.insert(album)
            }

            let logs = [
                seededLog(
                    album: albums[0],
                    rating: 4.5,
                    reviewText: "Warm, strange, and generous. Keeps finding new corners.",
                    tags: ["warm", "folk", "repeat"],
                    loggedAt: now.addingTimeInterval(-60 * 60 * 6),
                    updatedAt: now.addingTimeInterval(-60 * 60 * 6)
                ),
                seededLog(
                    album: albums[1],
                    rating: 5.0,
                    reviewText: "Sparse in the right places, huge when it needs to be.",
                    tags: ["intimate", "late night", "vocals"],
                    loggedAt: now.addingTimeInterval(-60 * 60 * 26),
                    updatedAt: now.addingTimeInterval(-60 * 60 * 26)
                ),
                seededLog(
                    album: albums[2],
                    rating: 4.0,
                    reviewText: "Dense, funny, dusty, still ridiculous.",
                    tags: ["samples", "clever", "dense"],
                    loggedAt: now.addingTimeInterval(-60 * 60 * 48),
                    updatedAt: now.addingTimeInterval(-60 * 60 * 48)
                )
            ]

            for log in logs {
                modelContext.insert(log)
            }

            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed Listend data: \(error)")
        }
    }

    private static func seededLog(
        album: Album,
        rating: Double,
        reviewText: String,
        tags: [String],
        loggedAt: Date,
        updatedAt: Date
    ) -> LogEntry {
        let sentiment = MockSoundPrintProvider.analyzeSentiment(
            input: SentimentInput(
                rating: rating,
                reviewText: reviewText,
                tags: tags
            )
        )

        return LogEntry(
            album: album,
            rating: rating,
            reviewText: reviewText,
            tags: tags,
            sentimentScore: sentiment.score,
            sentimentConfidence: sentiment.confidence,
            loggedAt: loggedAt,
            updatedAt: updatedAt
        )
    }
}
