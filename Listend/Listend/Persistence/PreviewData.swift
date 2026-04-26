//
//  PreviewData.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

import Foundation
import SwiftData

enum PreviewData {
    @MainActor
    static let lockedPersonaContainer: ModelContainer = makeContainer(logCount: 3, includePersona: false)

    @MainActor
    static let unlockedPersonaContainer: ModelContainer = makeContainer(logCount: 5, includePersona: true)

    @MainActor
    static let coldStartRecommendationContainer: ModelContainer = makeContainer(logCount: 0, includePersona: false)

    @MainActor
    static let activeRecommendationContainer: ModelContainer = makeContainer(logCount: 5, includePersona: true, includeRecommendation: true)

    @MainActor
    private static func makeContainer(
        logCount: Int,
        includePersona: Bool,
        includeRecommendation: Bool = false
    ) -> ModelContainer {
        let schema = Schema([
            Album.self,
            LogEntry.self,
            TasteDimension.self,
            TasteEvidence.self,
            SoundPrintPersona.self,
            Recommendation.self,
            RecommendationReceipt.self,
            RecommendationFeedback.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            seedPreviewData(
                logCount: logCount,
                includePersona: includePersona,
                includeRecommendation: includeRecommendation,
                in: container.mainContext
            )
            return container
        } catch {
            fatalError("Could not create preview container: \(error)")
        }
    }

    @MainActor
    private static func seedPreviewData(
        logCount: Int,
        includePersona: Bool,
        includeRecommendation: Bool,
        in modelContext: ModelContext
    ) {
        let albums = [
            Album(title: "Blonde", artistName: "Frank Ocean", releaseYear: 2016, genreName: "Alternative R&B"),
            Album(title: "Titanic Rising", artistName: "Weyes Blood", releaseYear: 2019, genreName: "Art Pop"),
            Album(title: "Madvillainy", artistName: "Madvillain", releaseYear: 2004, genreName: "Hip-Hop"),
            Album(title: "Vespertine", artistName: "Bjork", releaseYear: 2001, genreName: "Art Pop"),
            Album(title: "Sometimes I Might Be Introvert", artistName: "Little Simz", releaseYear: 2021, genreName: "Hip-Hop")
        ]
        let reviews = [
            "Sparse, intimate vocals that still feel huge.",
            "Lush and layered, but never sleepy.",
            "Dense samples with replay value for days.",
            "Weird, beautiful production with a cold little heartbeat.",
            "Polished storytelling with real momentum."
        ]
        let tags = [
            ["vocals", "late night"],
            ["lush", "layered"],
            ["dense", "repeat"],
            ["experimental", "beautiful"],
            ["storytelling", "polished"]
        ]

        for album in albums {
            modelContext.insert(album)
        }

        for index in 0..<min(logCount, albums.count) {
            modelContext.insert(
                LogEntry(
                    album: albums[index],
                    rating: index == 2 ? 4.0 : 4.5,
                    reviewText: reviews[index],
                    tags: tags[index],
                    sentimentScore: 0.7,
                    sentimentConfidence: 0.8,
                    loggedAt: Date().addingTimeInterval(TimeInterval(-index * 86_400)),
                    updatedAt: Date().addingTimeInterval(TimeInterval(-index * 86_400))
                )
            )
        }

        modelContext.insert(
            TasteDimension(
                name: "vocalFocus",
                label: "Vocal Focus",
                weight: 0.82,
                confidence: 0.8,
                summary: "Leans into vocal focus."
            )
        )

        if includePersona {
            modelContext.insert(
                SoundPrintPersona(
                    personaText: "Across 5 logs, your ear keeps rewarding vocal focus and polished storytelling, especially when the notes drift toward vocals. Blonde by Frank Ocean looks like the current north star, and your 4.4 average says you are picky without being joyless.",
                    logCountAtGeneration: 5
                )
            )
        }

        if includeRecommendation {
            let recommendedAlbum = Album(
                appleMusicID: "mock.fiona-apple.fetch-the-bolt-cutters",
                title: "Fetch the Bolt Cutters",
                artistName: "Fiona Apple",
                releaseYear: 2020,
                genreName: "Art Pop"
            )
            let recommendation = Recommendation(
                album: recommendedAlbum,
                score: 0.82,
                confidence: 0.84,
                explanationText: "Because you liked Titanic Rising, Tonight's Pick is Fetch the Bolt Cutters by Fiona Apple. Rated Titanic Rising 4.5 stars and tagged it lush, layered."
            )

            modelContext.insert(recommendedAlbum)
            modelContext.insert(recommendation)
            modelContext.insert(
                RecommendationReceipt(
                    recommendationID: recommendation.id,
                    logEntryID: UUID(),
                    sourceAlbumTitle: "Titanic Rising",
                    sourceArtistName: "Weyes Blood",
                    sourceRating: 4.5,
                    snippet: "Rated Titanic Rising 4.5 stars and tagged it lush, layered.",
                    linkedDimension: "instrumentalRichness"
                )
            )
        }

        try? modelContext.save()
    }
}
