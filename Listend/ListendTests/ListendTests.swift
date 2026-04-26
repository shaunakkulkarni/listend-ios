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

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Album.self,
            LogEntry.self,
            TasteDimension.self,
            TasteEvidence.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

}
