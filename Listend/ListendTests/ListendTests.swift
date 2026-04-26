//
//  ListendTests.swift
//  ListendTests
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import Testing
import Foundation
import SwiftData
@testable import Listend

@MainActor
struct ListendTests {

    @Test func highRatingPositiveReviewProducesPositiveSentiment() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.analyzeSentiment(
            input: SentimentInput(
                rating: 4.5,
                reviewText: "Loved this beautiful, incredible album.",
                tags: []
            )
        )

        #expect(result.score > 0.0)
        #expect(result.confidence == 0.8)
    }

    @Test func lowRatingNegativeReviewProducesNegativeSentiment() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.analyzeSentiment(
            input: SentimentInput(
                rating: 2.0,
                reviewText: "Boring, weak, and disappointing.",
                tags: []
            )
        )

        #expect(result.score < -0.2)
        #expect(result.confidence == 0.8)
    }

    @Test func ratingOnlyInputUsesLowerConfidence() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.analyzeSentiment(
            input: SentimentInput(
                rating: 3.5,
                reviewText: "",
                tags: []
            )
        )

        #expect(result.score == 0.2)
        #expect(result.confidence == 0.6)
    }

    @Test func sentimentScoresAreClamped() async throws {
        let provider = MockSoundPrintProvider()

        let positiveResult = try await provider.analyzeSentiment(
            input: SentimentInput(
                rating: 5.0,
                reviewText: "love loved great favorite beautiful amazing replay catchy incredible",
                tags: []
            )
        )
        let negativeResult = try await provider.analyzeSentiment(
            input: SentimentInput(
                rating: 1.0,
                reviewText: "hate hated boring overrated bad weak annoying forgettable disappointing",
                tags: []
            )
        )

        #expect(positiveResult.score == 1.0)
        #expect(negativeResult.score == -1.0)
    }

    @MainActor
    @Test func logEntrySignalHelpersUseStoredSentiment() {
        let positiveLog = LogEntry(album: nil, rating: 1.0, sentimentScore: 0.4)
        let negativeLog = LogEntry(album: nil, rating: 5.0, sentimentScore: -0.4)

        #expect(positiveLog.isPositiveSignal)
        #expect(!positiveLog.isNegativeSignal)
        #expect(positiveLog.canAnchorRecommendation)

        #expect(!negativeLog.isPositiveSignal)
        #expect(negativeLog.isNegativeSignal)
        #expect(!negativeLog.canAnchorRecommendation)
    }

    @MainActor
    @Test func logEntrySignalHelpersFallbackToRatingWhenSentimentIsMissing() {
        let positiveFallback = LogEntry(album: nil, rating: 4.0)
        let negativeFallback = LogEntry(album: nil, rating: 2.0)

        #expect(positiveFallback.isPositiveSignal)
        #expect(!positiveFallback.isNegativeSignal)
        #expect(positiveFallback.canAnchorRecommendation)

        #expect(!negativeFallback.isPositiveSignal)
        #expect(negativeFallback.isNegativeSignal)
        #expect(!negativeFallback.canAnchorRecommendation)
    }

    @Test func positiveInputProducesTasteDimensions() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.extractTasteSignals(
            input: TasteExtractionInput(
                logID: UUID(),
                albumTitle: "Test Album",
                artistName: "Test Artist",
                genreName: nil,
                releaseYear: nil,
                rating: 4.5,
                reviewText: "Energetic vocals with polished replay value.",
                tags: ["repeat"],
                sentimentScore: 0.8
            )
        )

        let dimensions = Set(result.signals.map(\.dimensionName))
        #expect(dimensions.contains("energy"))
        #expect(dimensions.contains("productionStyle"))
        #expect(dimensions.contains("vocalFocus"))
        #expect(dimensions.contains("replayability"))
    }

    @Test func negativeInputProducesNoPositiveTasteSignals() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.extractTasteSignals(
            input: TasteExtractionInput(
                logID: UUID(),
                albumTitle: "Test Album",
                artistName: "Test Artist",
                genreName: nil,
                releaseYear: nil,
                rating: 2.0,
                reviewText: "Dark, moody, intense, and raw.",
                tags: ["lo-fi"],
                sentimentScore: -0.5
            )
        )

        #expect(result.signals.isEmpty)
    }

    @Test func phraseKeywordsMatchDeterministically() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.extractTasteSignals(
            input: TasteExtractionInput(
                logID: UUID(),
                albumTitle: "Test Album",
                artistName: "Test Artist",
                genreName: nil,
                releaseYear: nil,
                rating: 4.0,
                reviewText: "Lo-fi, old-school, genre-bending ideas everywhere.",
                tags: [],
                sentimentScore: 0.7
            )
        )

        let dimensions = Set(result.signals.map(\.dimensionName))
        #expect(dimensions.contains("productionStyle"))
        #expect(dimensions.contains("eraAffinity"))
        #expect(dimensions.contains("genreOpenness"))
    }

    @MainActor
    @Test func soundPrintProfileRebuildPersistsPositiveEvidenceAndRemovesStaleData() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext

        let positiveAlbum = Album(title: "Positive Album", artistName: "Positive Artist")
        let negativeAlbum = Album(title: "Negative Album", artistName: "Negative Artist")
        let positiveLog = LogEntry(
            album: positiveAlbum,
            rating: 4.5,
            reviewText: "Energetic vocals with polished replay value.",
            tags: ["repeat"],
            sentimentScore: 0.8
        )
        let negativeLog = LogEntry(
            album: negativeAlbum,
            rating: 1.5,
            reviewText: "Dark, moody, intense, and raw.",
            tags: ["lo-fi"],
            sentimentScore: -0.6
        )

        modelContext.insert(positiveAlbum)
        modelContext.insert(negativeAlbum)
        modelContext.insert(positiveLog)
        modelContext.insert(negativeLog)
        try modelContext.save()

        try await SoundPrintProfileBuilder().rebuildProfile(in: modelContext)

        var dimensions = try modelContext.fetch(FetchDescriptor<TasteDimension>())
        var evidence = try modelContext.fetch(FetchDescriptor<TasteEvidence>())
        let dimensionNames = Set(dimensions.map(\.name))

        #expect(dimensionNames.contains("energy"))
        #expect(dimensionNames.contains("vocalFocus"))
        #expect(!dimensionNames.contains("mood"))
        let allEvidenceIsPositive = evidence.allSatisfy { $0.isPositiveEvidence }
        let evidenceLogIDs = Set(evidence.map(\.logEntryID))
        #expect(allEvidenceIsPositive)
        #expect(evidenceLogIDs == [positiveLog.id])

        modelContext.delete(positiveLog)
        try modelContext.save()

        try await SoundPrintProfileBuilder().rebuildProfile(in: modelContext)

        dimensions = try modelContext.fetch(FetchDescriptor<TasteDimension>())
        evidence = try modelContext.fetch(FetchDescriptor<TasteEvidence>())

        #expect(dimensions.isEmpty)
        #expect(evidence.isEmpty)
    }

    @Test func personaGenerationReferencesConcreteSignalsAndAvoidsBannedPhrases() async throws {
        let provider = MockSoundPrintProvider()
        let input = personaInput()

        let result = try await provider.generatePersona(input: input)
        let normalizedText = result.text.lowercased()

        #expect(result.text.count >= 80)
        #expect(normalizedText.contains("vocal focus") || normalizedText.contains("vocals"))
        #expect(normalizedText.contains("blonde") || normalizedText.contains("frank ocean"))
        #expect(!normalizedText.contains("eclectic taste"))
        #expect(!normalizedText.contains("wide range of genres"))
    }

    @Test func personaQualityFilterRejectsVagueOrGenericText() {
        let concreteSignals = ["Vocal Focus", "Blonde", "vocals"]

        #expect(!MockSoundPrintProvider.isValidPersona("", concreteSignals: concreteSignals))
        #expect(!MockSoundPrintProvider.isValidPersona("Too short.", concreteSignals: concreteSignals))
        #expect(!MockSoundPrintProvider.isValidPersona("You have eclectic taste and a wide range of genres, especially around Vocal Focus and Blonde.", concreteSignals: concreteSignals))
        #expect(!MockSoundPrintProvider.isValidPersona("Across five logs, the profile is long enough to seem substantial, but it carefully avoids naming any actual signal from the input data.", concreteSignals: concreteSignals))
    }

    @Test func personaGenerationFallsBackToSpecificSparseInput() async throws {
        let provider = MockSoundPrintProvider()
        let result = try await provider.generatePersona(
            input: PersonaInput(
                dimensions: [],
                recentLogs: [
                    PersonaLogInput(
                        albumTitle: "Titanic Rising",
                        artistName: "Weyes Blood",
                        rating: 4.5,
                        reviewSnippet: "",
                        tags: [],
                        isPositiveSignal: true
                    )
                ],
                totalLogCount: 5,
                topTags: [],
                averageRating: 4.1
            )
        )

        #expect(result.text.count >= 80)
        #expect(result.text.lowercased().contains("titanic rising"))
    }

    @MainActor
    @Test func soundPrintProfileRebuildPersistsOneCurrentPersonaAtFiveLogs() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext

        insertPersonaReadyLogs(in: modelContext, count: 5)
        modelContext.insert(SoundPrintPersona(personaText: "Old persona one", logCountAtGeneration: 5))
        modelContext.insert(SoundPrintPersona(personaText: "Old persona two", logCountAtGeneration: 5))
        try modelContext.save()

        try await SoundPrintProfileBuilder().rebuildProfile(in: modelContext)

        let personas = try modelContext.fetch(FetchDescriptor<SoundPrintPersona>())

        #expect(personas.count == 1)
        #expect(personas[0].logCountAtGeneration == 5)
        #expect(personas[0].personaText.count >= 80)
        #expect(!personas[0].personaText.contains("Old persona"))
    }

    @MainActor
    @Test func soundPrintProfileRebuildDeletesPersonaBelowFiveLogs() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext

        insertPersonaReadyLogs(in: modelContext, count: 4)
        modelContext.insert(SoundPrintPersona(personaText: "Stale persona", logCountAtGeneration: 5))
        try modelContext.save()

        try await SoundPrintProfileBuilder().rebuildProfile(in: modelContext)

        let personas = try modelContext.fetch(FetchDescriptor<SoundPrintPersona>())

        #expect(personas.isEmpty)
    }

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Album.self,
            LogEntry.self,
            TasteDimension.self,
            TasteEvidence.self,
            SoundPrintPersona.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func personaInput() -> PersonaInput {
        PersonaInput(
            dimensions: [
                TasteDimension(
                    name: "vocalFocus",
                    label: "Vocal Focus",
                    weight: 0.9,
                    confidence: 0.8,
                    summary: "Leans into vocal focus."
                ),
                TasteDimension(
                    name: "productionStyle",
                    label: "Production Style",
                    weight: 0.75,
                    confidence: 0.75,
                    summary: "Leans into production style."
                )
            ],
            recentLogs: [
                PersonaLogInput(
                    albumTitle: "Blonde",
                    artistName: "Frank Ocean",
                    rating: 5.0,
                    reviewSnippet: "Sparse intimate vocals that still feel huge.",
                    tags: ["vocals", "late night"],
                    isPositiveSignal: true
                ),
                PersonaLogInput(
                    albumTitle: "Titanic Rising",
                    artistName: "Weyes Blood",
                    rating: 4.5,
                    reviewSnippet: "Lush production with replay value.",
                    tags: ["lush"],
                    isPositiveSignal: true
                )
            ],
            totalLogCount: 5,
            topTags: ["vocals", "late night"],
            averageRating: 4.4
        )
    }

    @MainActor
    private func insertPersonaReadyLogs(in modelContext: ModelContext, count: Int) {
        let albums = [
            Album(title: "Blonde", artistName: "Frank Ocean"),
            Album(title: "Titanic Rising", artistName: "Weyes Blood"),
            Album(title: "Madvillainy", artistName: "Madvillain"),
            Album(title: "Vespertine", artistName: "Bjork"),
            Album(title: "Sometimes I Might Be Introvert", artistName: "Little Simz")
        ]
        let reviews = [
            "Sparse intimate vocals with polished replay value.",
            "Lush layered production that feels beautiful.",
            "Dense energetic samples with repeat value.",
            "Experimental vocals with weird beautiful details.",
            "Polished storytelling and intense momentum."
        ]
        let tags = [
            ["vocals", "polished"],
            ["lush", "layered"],
            ["dense", "repeat"],
            ["experimental", "beautiful"],
            ["storytelling", "intense"]
        ]

        for index in 0..<count {
            let album = albums[index]
            modelContext.insert(album)
            modelContext.insert(
                LogEntry(
                    album: album,
                    rating: index == 2 ? 4.0 : 4.5,
                    reviewText: reviews[index],
                    tags: tags[index],
                    sentimentScore: 0.75,
                    sentimentConfidence: 0.8,
                    loggedAt: Date().addingTimeInterval(TimeInterval(-index * 86_400)),
                    updatedAt: Date().addingTimeInterval(TimeInterval(-index * 86_400))
                )
            )
        }
    }

}
