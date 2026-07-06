//
//  PreviewData.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

import Foundation
import SwiftData

enum PreviewData {
    /// 0 logs: cold-start placeholder state.
    @MainActor
    static let coldStartRecommendationContainer: ModelContainer = makeContainer(logCount: 0, includePersona: false)

    /// 1-2 logs: "too early to form a taste profile" state.
    @MainActor
    static let tooEarlyContainer: ModelContainer = makeContainer(logCount: 1, includePersona: false)

    /// 3-4 logs: early signals, not a full persona yet.
    @MainActor
    static let lockedPersonaContainer: ModelContainer = makeContainer(logCount: 3, includePersona: false)

    /// 5+ logs: modest persona and compact summary.
    @MainActor
    static let unlockedPersonaContainer: ModelContainer = makeContainer(logCount: 5, includePersona: true)

    @MainActor
    static let appleIntelligencePersonaContainer: ModelContainer = makeContainer(
        logCount: 5,
        includePersona: true,
        personaGenerationSource: .foundationModels
    )

    @MainActor
    static let localFallbackPersonaContainer: ModelContainer = makeContainer(
        logCount: 5,
        includePersona: true,
        personaGenerationSource: .localFallback
    )

    /// 10+ logs: fuller profile with dimensions, avoidance signals, and evidence receipts.
    @MainActor
    static let fullerProfileContainer: ModelContainer = makeContainer(
        logCount: 10,
        includePersona: true,
        includeAvoidanceSignals: true
    )

    @MainActor
    static let activeRecommendationContainer: ModelContainer = makeContainer(logCount: 5, includePersona: true, includeRecommendation: true)

    @MainActor
    private static func makeContainer(
        logCount: Int,
        includePersona: Bool,
        includeRecommendation: Bool = false,
        includeAvoidanceSignals: Bool = false,
        personaGenerationSource: SoundPrintGenerationSource = .localFallback
    ) -> ModelContainer {
        let schema = Schema([
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
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            seedPreviewData(
                logCount: logCount,
                includePersona: includePersona,
                includeRecommendation: includeRecommendation,
                includeAvoidanceSignals: includeAvoidanceSignals,
                personaGenerationSource: personaGenerationSource,
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
        includeAvoidanceSignals: Bool,
        personaGenerationSource: SoundPrintGenerationSource,
        in modelContext: ModelContext
    ) {
        let albums = [
            Album(title: "Blonde", artistName: "Frank Ocean", releaseYear: 2016, genreName: "Alternative R&B"),
            Album(title: "Titanic Rising", artistName: "Weyes Blood", releaseYear: 2019, genreName: "Art Pop"),
            Album(title: "Madvillainy", artistName: "Madvillain", releaseYear: 2004, genreName: "Hip-Hop"),
            Album(title: "Vespertine", artistName: "Bjork", releaseYear: 2001, genreName: "Art Pop"),
            Album(title: "Sometimes I Might Be Introvert", artistName: "Little Simz", releaseYear: 2021, genreName: "Hip-Hop"),
            Album(title: "In Rainbows", artistName: "Radiohead", releaseYear: 2007, genreName: "Alternative Rock"),
            Album(title: "Fetch the Bolt Cutters", artistName: "Fiona Apple", releaseYear: 2020, genreName: "Art Pop"),
            Album(title: "SOS", artistName: "SZA", releaseYear: 2022, genreName: "R&B"),
            Album(title: "Ctrl", artistName: "SZA", releaseYear: 2017, genreName: "R&B"),
            Album(title: "Norman Fucking Rockwell!", artistName: "Lana Del Rey", releaseYear: 2019, genreName: "Art Pop")
        ]
        let reviews = [
            "Sparse, intimate vocals that still feel huge.",
            "Lush and layered, but never sleepy.",
            "Dense samples with replay value for days.",
            "Weird, beautiful production with a cold little heartbeat.",
            "Polished storytelling with real momentum.",
            "Tense, textured, and rewards a close listen.",
            "Raw and unpredictable, never plays it safe.",
            "Feels bloated and inconsistent in the back half.",
            "Sparse vocals with real replay value.",
            "Polished but a little front-loaded overall."
        ]
        let tags = [
            ["vocals", "late night"],
            ["lush", "layered"],
            ["dense", "repeat"],
            ["experimental", "beautiful"],
            ["storytelling", "polished"],
            ["textured", "moody"],
            ["raw", "experimental"],
            ["uneven", "long"],
            ["vocals", "repeat"],
            ["polished", "front-loaded"]
        ]

        for album in albums {
            modelContext.insert(album)
        }

        var logs: [LogEntry] = []
        for index in 0..<min(logCount, albums.count) {
            let log = LogEntry(
                album: albums[index],
                rating: index == 2 ? 4.0 : (index == 7 ? 3.0 : 4.5),
                reviewText: reviews[index],
                tags: tags[index],
                favoriteTracks: index == 0 ? ["Nights"] : [],
                skipTracks: index == 7 ? ["Track 4", "Track 5"] : [],
                standoutMoment: index == 1 ? "The strings that come in on the bridge." : nil,
                sentimentScore: index == 7 ? 0.1 : 0.7,
                sentimentConfidence: 0.8,
                loggedAt: Date().addingTimeInterval(TimeInterval(-index * 86_400)),
                updatedAt: Date().addingTimeInterval(TimeInterval(-index * 86_400))
            )
            logs.append(log)
            modelContext.insert(log)
        }

        let vocalFocusDimension = TasteDimension(
            name: "vocalFocus",
            label: "Vocal Gravity",
            weight: 0.82,
            confidence: 0.8,
            summary: "Leans into vocal gravity."
        )
        modelContext.insert(vocalFocusDimension)
        modelContext.insert(
            TasteEvidence(
                dimensionName: "vocalFocus",
                logEntryID: logs.first?.id ?? UUID(),
                snippet: "Sparse, intimate vocals that still feel huge.",
                evidenceType: "reviewOrTag",
                strength: 0.82,
                confidence: 0.8,
                isPositiveEvidence: true
            )
        )

        if includeAvoidanceSignals {
            let replayabilityDimension = TasteDimension(
                name: "replayability",
                label: "Replay Pull",
                weight: 0.7,
                confidence: 0.72,
                summary: "Leans into replay pull."
            )
            modelContext.insert(replayabilityDimension)
            modelContext.insert(
                TasteEvidence(
                    dimensionName: "replayability",
                    logEntryID: logs.count > 8 ? logs[8].id : UUID(),
                    snippet: "Sparse vocals with real replay value.",
                    evidenceType: "reviewOrTag",
                    strength: 0.7,
                    confidence: 0.72,
                    isPositiveEvidence: true
                )
            )
            modelContext.insert(
                TasteAvoidanceSignal(
                    name: "skipHeavyAlbums",
                    label: "Skip-Heavy Albums",
                    summary: "Tends to skip through parts of albums like this.",
                    strength: 0.55,
                    confidence: 0.6,
                    evidenceLogEntryIDs: logs.count > 7 ? [logs[7].id] : []
                )
            )
        }

        if includePersona {
            modelContext.insert(
                SoundPrintPersona(
                    personaText: "You tend to reward vocal gravity and replay pull. Blonde by Frank Ocean is the clearest example so far.",
                    logCountAtGeneration: logCount,
                    headline: "Vocal Gravity Leads The Pattern",
                    summaryText: "You tend to reward vocal gravity and lose patience with skip-heavy albums.",
                    bullets: ["Rewards Vocal Gravity", "Loses patience with Skip-Heavy Albums", "High replay value overall"],
                    generationSource: personaGenerationSource
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
                source: RecommendationSource.applePersonalRecommendations.rawValue,
                freshnessStatus: RecommendationFreshnessStatus.appleFreshnessChecked.rawValue,
                explanationText: "Because you liked Titanic Rising, Today's Pick is Fetch the Bolt Cutters by Fiona Apple. Rated Titanic Rising 4.5 stars and tagged it lush, layered."
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
