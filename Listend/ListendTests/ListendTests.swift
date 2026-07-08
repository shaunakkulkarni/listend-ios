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

    @Test func fallbackSoundPrintProviderUsesPrimaryWhenPrimarySucceeds() async throws {
        let provider = FallbackSoundPrintProvider(
            primary: SuccessfulSoundPrintProvider(),
            fallback: MockSoundPrintProvider()
        )

        let result = try await provider.analyzeSentiment(
            input: SentimentInput(rating: 2.0, reviewText: "Primary should win.", tags: [])
        )

        #expect(result.score == 0.42)
        #expect(result.confidence == 0.91)
    }

    @Test func fallbackSoundPrintProviderUsesMockWhenPrimaryThrows() async throws {
        let provider = FallbackSoundPrintProvider(
            primary: ThrowingSoundPrintProvider(failingOperation: .sentiment),
            fallback: MockSoundPrintProvider()
        )

        let result = try await provider.analyzeSentiment(
            input: SentimentInput(rating: 4.0, reviewText: "", tags: [])
        )

        #expect(result.score == MockSoundPrintProvider.baseScore(for: 4.0))
        #expect(result.confidence == 0.6)
    }

    @Test func fallbackSoundPrintProviderDoesNotCreateMockOutputForCancellation() async {
        let provider = FallbackSoundPrintProvider(
            primary: CancellingSoundPrintProvider(),
            fallback: SuccessfulSoundPrintProvider()
        )

        do {
            _ = try await provider.analyzeSentiment(
                input: SentimentInput(rating: 5.0, reviewText: "Cancel this.", tags: [])
            )
            Issue.record("Cancellation should propagate instead of falling back.")
        } catch is CancellationError {
            #expect(true)
        } catch {
            Issue.record("Expected CancellationError, got \(error).")
        }
    }

    @Test func foundationModelsSentimentValidationClampsValues() {
        let result = FoundationModelsSoundPrintValidator.validatedSentiment(
            score: 2.5,
            confidence: -0.5
        )

        #expect(result.score == 1.0)
        #expect(result.confidence == 0.0)
    }

    @Test func foundationModelsTasteValidationRejectsUnknownDimensions() throws {
        let input = tasteExtractionInput(sentimentScore: 0.8)

        do {
            _ = try FoundationModelsSoundPrintValidator.validatedTasteExtraction(
                payload: TasteExtractionPayload(
                    sentiment: TasteExtractionPayload.Sentiment(score: 0.8, confidence: 0.8),
                    positiveSignals: [
                        FoundationModelsPositiveSignalPayload(
                            dimensionKey: "inventedDimension",
                            label: "Invented",
                            summary: "Invented.",
                            strength: 0.8,
                            confidence: 0.8,
                            evidenceSnippet: "Invented evidence."
                        )
                    ],
                    avoidanceSignals: []
                ),
                input: input
            )
            Issue.record("Unknown dimensions should be rejected.")
        } catch let error as FoundationModelsSoundPrintProviderError {
            #expect(error == .validationFailed)
        }
    }

    @Test func foundationModelsTasteValidationCreatesNoPositiveEvidenceFromNegativeSentiment() throws {
        let result = try FoundationModelsSoundPrintValidator.validatedTasteExtraction(
            payload: TasteExtractionPayload(
                sentiment: TasteExtractionPayload.Sentiment(score: -0.4, confidence: 0.8),
                positiveSignals: [
                    FoundationModelsPositiveSignalPayload(
                        dimensionKey: "energy",
                        label: "Energy Bias",
                        summary: "Energetic.",
                        strength: 0.8,
                        confidence: 0.8,
                        evidenceSnippet: "Intense momentum."
                    )
                ],
                avoidanceSignals: []
            ),
            input: tasteExtractionInput(sentimentScore: -0.4)
        )

        #expect(result.signals.isEmpty)
    }

    @Test func foundationModelsTasteValidationAcceptsKnownLabelsAsKeys() throws {
        let result = try FoundationModelsSoundPrintValidator.validatedTasteExtraction(
            payload: TasteExtractionPayload(
                sentiment: TasteExtractionPayload.Sentiment(score: 0.8, confidence: 0.8),
                positiveSignals: [
                    FoundationModelsPositiveSignalPayload(
                        dimensionKey: "Energy Bias",
                        label: "Energy Bias",
                        summary: "Energetic.",
                        strength: 0.8,
                        confidence: 0.8,
                        evidenceSnippet: "Intense momentum."
                    )
                ],
                avoidanceSignals: [
                    FoundationModelsAvoidanceSignalPayload(
                        signalKey: "Skip-Heavy Albums",
                        label: "Skip-Heavy Albums",
                        summary: "Too many skips.",
                        strength: 0.6,
                        confidence: 0.6,
                        evidenceSnippet: "Several weaker tracks."
                    )
                ]
            ),
            input: tasteExtractionInput(sentimentScore: 0.8)
        )

        #expect(result.signals.map(\.dimensionName) == ["energy"])
        #expect(result.avoidanceSignals.map(\.signalName) == ["skipHeavyAlbums"])
    }

    @Test func foundationModelsTasteValidationRejectsUnknownAvoidanceCategory() throws {
        let input = tasteExtractionInput(sentimentScore: 0.8)

        do {
            _ = try FoundationModelsSoundPrintValidator.validatedTasteExtraction(
                payload: TasteExtractionPayload(
                    sentiment: TasteExtractionPayload.Sentiment(score: 0.8, confidence: 0.8),
                    positiveSignals: [],
                    avoidanceSignals: [
                        FoundationModelsAvoidanceSignalPayload(
                            signalKey: "inventedAvoidance",
                            label: "Invented",
                            summary: "Invented.",
                            strength: 0.6,
                            confidence: 0.6,
                            evidenceSnippet: "Invented evidence."
                        )
                    ]
                ),
                input: input
            )
            Issue.record("Unknown avoidance categories should be rejected.")
        } catch let error as FoundationModelsSoundPrintProviderError {
            #expect(error == .validationFailed)
        }
    }

    @Test func foundationModelsTasteValidationSkipsDuplicateDimensionsInsteadOfFailing() throws {
        let duplicatedSignal = FoundationModelsPositiveSignalPayload(
            dimensionKey: "energy",
            label: "Energy Bias",
            summary: "Energetic.",
            strength: 0.8,
            confidence: 0.8,
            evidenceSnippet: "Intense momentum."
        )
        let distinctSignal = FoundationModelsPositiveSignalPayload(
            dimensionKey: "mood",
            label: "Emotional Temperature",
            summary: "Moody.",
            strength: 0.7,
            confidence: 0.7,
            evidenceSnippet: "Late night listening."
        )

        let result = try FoundationModelsSoundPrintValidator.validatedTasteExtraction(
            payload: TasteExtractionPayload(
                sentiment: TasteExtractionPayload.Sentiment(score: 0.8, confidence: 0.8),
                positiveSignals: [duplicatedSignal, duplicatedSignal, distinctSignal],
                avoidanceSignals: []
            ),
            input: tasteExtractionInput(sentimentScore: 0.8)
        )

        #expect(result.signals.map(\.dimensionName) == ["energy", "mood"])
    }

    @Test func foundationModelsTasteValidationSkipsSignalsWithBlankFieldsInsteadOfFailing() throws {
        let blankSummarySignal = FoundationModelsPositiveSignalPayload(
            dimensionKey: "energy",
            label: "Energy Bias",
            summary: "   ",
            strength: 0.8,
            confidence: 0.8,
            evidenceSnippet: "Intense momentum."
        )
        let completeSignal = FoundationModelsPositiveSignalPayload(
            dimensionKey: "mood",
            label: "Emotional Temperature",
            summary: "Moody.",
            strength: 0.7,
            confidence: 0.7,
            evidenceSnippet: "Late night listening."
        )

        let result = try FoundationModelsSoundPrintValidator.validatedTasteExtraction(
            payload: TasteExtractionPayload(
                sentiment: TasteExtractionPayload.Sentiment(score: 0.8, confidence: 0.8),
                positiveSignals: [blankSummarySignal, completeSignal],
                avoidanceSignals: []
            ),
            input: tasteExtractionInput(sentimentScore: 0.8)
        )

        #expect(result.signals.map(\.dimensionName) == ["mood"])
    }

    @Test func foundationModelsTasteValidationCapsPositiveAndAvoidanceSignalCounts() throws {
        let positiveSignals = FoundationModelsSoundPrintValidator.allowedDimensionNames.prefix(6).map { key in
            FoundationModelsPositiveSignalPayload(
                dimensionKey: key,
                label: key,
                summary: "Summary.",
                strength: 0.6,
                confidence: 0.6,
                evidenceSnippet: "Evidence."
            )
        }
        let avoidanceSignals = FoundationModelsSoundPrintValidator.allowedAvoidanceCategoryNames.map { key in
            FoundationModelsAvoidanceSignalPayload(
                signalKey: key,
                label: key,
                summary: "Summary.",
                strength: 0.5,
                confidence: 0.5,
                evidenceSnippet: "Evidence."
            )
        }

        let result = try FoundationModelsSoundPrintValidator.validatedTasteExtraction(
            payload: TasteExtractionPayload(
                sentiment: TasteExtractionPayload.Sentiment(score: 0.8, confidence: 0.8),
                positiveSignals: Array(positiveSignals),
                avoidanceSignals: avoidanceSignals
            ),
            input: tasteExtractionInput(sentimentScore: 0.8)
        )

        #expect(result.signals.count == 4)
        #expect(result.avoidanceSignals.count == 3)
    }

    @Test func foundationModelsPersonaValidationUsesExistingQualityGuard() throws {
        do {
            _ = try FoundationModelsSoundPrintValidator.validatedPersona(
                text: "You have eclectic taste and a wide range of genres, especially around Vocal Focus and Blonde.",
                input: personaInput()
            )
            Issue.record("Generic persona text should be rejected.")
        } catch let error as FoundationModelsSoundPrintProviderError {
            #expect(error == .validationFailed)
        }
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

    @Test func logEntryTrackHighlightDefaultsAreEmpty() {
        let log = LogEntry(album: nil, rating: 4.0)

        #expect(log.tags.isEmpty)
        #expect(log.favoriteTracks.isEmpty)
        #expect(log.skipTracks.isEmpty)
        #expect(log.normalizedStandoutMoment == nil)
        #expect(log.hasTrackHighlights == false)
        #expect(log.tagsRawValue == "[]")
        #expect(log.favoriteTracksRawValue == nil)
        #expect(log.skipTracksRawValue == nil)
    }

    @Test func logEntryListStorageWritesJSONValues() {
        let log = LogEntry(
            album: nil,
            rating: 4.0,
            tags: [" late night ", "Late Night", "", "vocals"],
            favoriteTracks: ["  Kill Bill  ", "", "Snooze"],
            skipTracks: ["Seek & Destroy", "  ", "Too Late"],
            standoutMoment: "  second chorus lift  "
        )

        #expect(log.tags == ["late night", "vocals"])
        #expect(log.favoriteTracks == ["Kill Bill", "Snooze"])
        #expect(log.skipTracks == ["Seek & Destroy", "Too Late"])
        #expect(log.standoutMoment == "second chorus lift")
        #expect(log.tagsRawValue == "[\"late night\",\"vocals\"]")
        #expect(log.favoriteTracksRawValue == "[\"Kill Bill\",\"Snooze\"]")
        #expect(log.skipTracksRawValue == "[\"Seek & Destroy\",\"Too Late\"]")
    }

    @Test func logEntryListStoragePreservesCommaContainingTrackNames() {
        let log = LogEntry(
            album: nil,
            rating: 4.0,
            favoriteTracks: ["Sweet, I Thought You Wanted To Dance"]
        )

        #expect(log.favoriteTracks == ["Sweet, I Thought You Wanted To Dance"])
        #expect(log.favoriteTracksRawValue == "[\"Sweet, I Thought You Wanted To Dance\"]")
    }

    @Test func logEntryListStorageDedupesValues() {
        let log = LogEntry(
            album: nil,
            rating: 4.0,
            tags: [" late night ", "Late Night", "VOCALS"],
            favoriteTracks: ["Snooze", " snooze ", "Good Days"],
            skipTracks: ["Élite", "elite", "Too Late"]
        )

        #expect(log.tags == ["late night", "vocals"])
        #expect(log.favoriteTracks == ["Snooze", "Good Days"])
        #expect(log.skipTracks == ["Élite", "Too Late"])
    }

    @Test func logEntryListStorageReadsLegacyCommaSeparatedValues() {
        let log = LogEntry(album: nil, rating: 4.0)

        log.tagsRawValue = "late night,vocals"
        log.favoriteTracksRawValue = "Snooze,Good Days"
        log.skipTracksRawValue = "Seek & Destroy,Too Late"

        #expect(log.tags == ["late night", "vocals"])
        #expect(log.favoriteTracks == ["Snooze", "Good Days"])
        #expect(log.skipTracks == ["Seek & Destroy", "Too Late"])
    }

    @Test func logEntryListStorageWritesJSONAfterReadingLegacyValues() {
        let log = LogEntry(album: nil, rating: 4.0)

        log.tagsRawValue = "late night,vocals"
        log.favoriteTracksRawValue = "Snooze,Good Days"
        log.skipTracksRawValue = "Seek & Destroy,Too Late"

        log.tags = log.tags + ["repeat"]
        log.favoriteTracks = log.favoriteTracks + ["Blind"]
        log.skipTracks = log.skipTracks + ["Ghost"]

        #expect(log.tagsRawValue == "[\"late night\",\"vocals\",\"repeat\"]")
        #expect(log.favoriteTracksRawValue == "[\"Snooze\",\"Good Days\",\"Blind\"]")
        #expect(log.skipTracksRawValue == "[\"Seek & Destroy\",\"Too Late\",\"Ghost\"]")
    }

    @Test func logEntryListStorageReturnsEmptyForMalformedJSONLookingValues() {
        let log = LogEntry(album: nil, rating: 4.0)

        log.tagsRawValue = "[late night,vocals"
        log.favoriteTracksRawValue = "[Snooze,Good Days"
        log.skipTracksRawValue = "[Seek & Destroy,Too Late"

        #expect(log.tags.isEmpty)
        #expect(log.favoriteTracks.isEmpty)
        #expect(log.skipTracks.isEmpty)
    }

    @Test func logEntryTrackHighlightSettersClearEmptyValues() {
        let log = LogEntry(
            album: nil,
            rating: 4.0,
            tags: ["late night"],
            favoriteTracks: ["Ghost in the Machine"],
            skipTracks: ["Too Late"],
            standoutMoment: "bridge"
        )

        log.tags = [" ", ""]
        log.favoriteTracks = [" ", ""]
        log.skipTracks = []
        log.standoutMoment = "   "

        #expect(log.tags.isEmpty)
        #expect(log.favoriteTracks.isEmpty)
        #expect(log.skipTracks.isEmpty)
        #expect(log.normalizedStandoutMoment == nil)
        #expect(log.hasTrackHighlights == false)
        #expect(log.tagsRawValue == "[]")
        #expect(log.favoriteTracksRawValue == nil)
        #expect(log.skipTracksRawValue == nil)
    }

    @Test func logEntryHasTrackHighlightsUsesNormalizedValues() {
        let emptyLog = LogEntry(album: nil, rating: 4.0)
        let favoriteLog = LogEntry(album: nil, rating: 4.0, favoriteTracks: ["Snooze"])
        let skipLog = LogEntry(album: nil, rating: 4.0, skipTracks: ["Too Late"])
        let standoutLog = LogEntry(album: nil, rating: 4.0, standoutMoment: "  final chorus  ")

        #expect(emptyLog.hasTrackHighlights == false)
        #expect(favoriteLog.hasTrackHighlights)
        #expect(skipLog.hasTrackHighlights)
        #expect(standoutLog.hasTrackHighlights)
        #expect(standoutLog.normalizedStandoutMoment == "final chorus")
    }

    @MainActor
    @Test func editingTrackHighlightsUpdatesSavedLog() throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let album = Album(title: "SOS", artistName: "SZA")
        let log = LogEntry(album: album, rating: 4.5)

        modelContext.insert(album)
        modelContext.insert(log)
        try modelContext.save()

        log.favoriteTracks = ["Snooze", "Good Days"]
        log.skipTracks = ["Too Late"]
        log.standoutMoment = "The last chorus opened up."
        try modelContext.save()

        let logs = try modelContext.fetch(FetchDescriptor<LogEntry>())
        let savedLog = try #require(logs.first)
        #expect(savedLog.favoriteTracks == ["Snooze", "Good Days"])
        #expect(savedLog.skipTracks == ["Too Late"])
        #expect(savedLog.standoutMoment == "The last chorus opened up.")
    }

    @Test func albumTrackCandidatesSortByDiscTrackThenReturnedOrder() {
        let tracks = [
            AlbumTrackCandidate(albumAppleMusicID: "album", title: "Second", trackNumber: 2, discNumber: 1, returnedOrder: 1),
            AlbumTrackCandidate(albumAppleMusicID: "album", title: "Disc Two", trackNumber: 1, discNumber: 2, returnedOrder: 2),
            AlbumTrackCandidate(albumAppleMusicID: "album", title: "First", trackNumber: 1, discNumber: 1, returnedOrder: 3),
            AlbumTrackCandidate(albumAppleMusicID: "album", title: "Untitled", returnedOrder: 0)
        ]

        #expect(tracks.sortedForAlbumDisplay().map(\.title) == ["First", "Second", "Disc Two", "Untitled"])
    }

    @MainActor
    @Test func fallbackAlbumTrackServiceReturnsEmptyForMissingAppleMusicID() async throws {
        let container = try makeInMemoryContainer()
        let album = Album(title: "Local Album", artistName: "Local Artist")
        let service = FallbackAlbumTrackService(
            primary: SuccessfulAlbumTrackService(tracks: [.sosTrack(title: "Snooze", trackNumber: 8)]),
            fallback: EmptyAlbumTrackService()
        )

        let tracks = try await service.tracks(for: album, in: container.mainContext)

        #expect(tracks.isEmpty)
    }

    @MainActor
    @Test func fallbackAlbumTrackServiceUsesFreshCacheBeforePrimary() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let album = Album(appleMusicID: "mock.sza.sos", title: "SOS", artistName: "SZA")
        modelContext.insert(album)
        try AlbumTrackCache.replaceCachedTracks(
            [.sosTrack(title: "Cached Snooze", trackNumber: 8)],
            albumAppleMusicID: "mock.sza.sos",
            in: modelContext
        )

        let service = FallbackAlbumTrackService(
            primary: ThrowingAlbumTrackService(),
            fallback: EmptyAlbumTrackService()
        )

        let tracks = try await service.tracks(for: album, in: modelContext)

        #expect(tracks.map(\.title) == ["Cached Snooze"])
    }

    @MainActor
    @Test func fallbackAlbumTrackServiceReplacesStaleCacheAfterFetch() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let oldDate = Date(timeIntervalSinceNow: -31 * 24 * 60 * 60)
        let album = Album(appleMusicID: "mock.sza.sos", title: "SOS", artistName: "SZA")
        modelContext.insert(album)
        modelContext.insert(
            AlbumTrack(
                albumAppleMusicID: "mock.sza.sos",
                title: "Old Track",
                trackNumber: 1,
                discNumber: 1,
                cachedAt: oldDate
            )
        )
        try modelContext.save()

        let service = FallbackAlbumTrackService(
            primary: SuccessfulAlbumTrackService(tracks: [.sosTrack(title: "Fresh Snooze", trackNumber: 8)]),
            fallback: EmptyAlbumTrackService()
        )

        let tracks = try await service.tracks(for: album, in: modelContext)
        let cachedTracks = try AlbumTrackCache.cachedTracks(albumAppleMusicID: "mock.sza.sos", in: modelContext)

        #expect(tracks.map(\.title) == ["Fresh Snooze"])
        #expect(cachedTracks?.map(\.title) == ["Fresh Snooze"])
    }

    @MainActor
    @Test func fallbackAlbumTrackServiceReturnsEmptyNotMockWhenPrimaryFails() async throws {
        let container = try makeInMemoryContainer()
        let album = Album(appleMusicID: "mock.sza.sos", title: "SOS", artistName: "SZA")
        let service = FallbackAlbumTrackService(
            primary: ThrowingAlbumTrackService(),
            fallback: EmptyAlbumTrackService()
        )

        let tracks = try await service.tracks(for: album, in: container.mainContext)

        #expect(tracks.isEmpty)
    }

    @Test func albumTrackSelectionMutuallyExcludesFavoritesAndSkips() {
        let track = AlbumTrackCandidate.sosTrack(title: "Snooze", trackNumber: 8)
        var selection = AlbumTrackSelectionState()

        selection.toggleFavorite(track)
        selection.toggleSkip(track)

        #expect(!selection.isFavorite(track))
        #expect(selection.isSkip(track))
    }

    @Test func albumTrackSelectionMapsOrderedTitlesIntoLogEntryLists() {
        let candidates = [
            AlbumTrackCandidate.sosTrack(title: "Kill Bill", trackNumber: 2),
            AlbumTrackCandidate.sosTrack(title: "Snooze", trackNumber: 8),
            AlbumTrackCandidate.sosTrack(title: "Good Days", trackNumber: 23)
        ]
        var selection = AlbumTrackSelectionState()
        selection.toggleFavorite(candidates[1])
        selection.toggleFavorite(candidates[0])
        selection.toggleSkip(candidates[2])
        let log = LogEntry(album: nil, rating: 4.5)

        log.favoriteTracks = selection.savedFavoriteTrackTitles(from: candidates, manualText: "Blind")
        log.skipTracks = selection.savedSkipTrackTitles(from: candidates, manualText: "Too Late")

        #expect(log.favoriteTracks == ["Kill Bill", "Snooze", "Blind"])
        #expect(log.skipTracks == ["Good Days", "Too Late"])
    }

    @Test func starRatingCalculatorClampsLeftEdgeToHalfStar() {
        #expect(StarRatingCalculator.rating(atX: 0, width: 200) == 0.5)
    }

    @Test func starRatingCalculatorClampsRightEdgeToFiveStars() {
        #expect(StarRatingCalculator.rating(atX: 200, width: 200) == 5.0)
    }

    @Test func starRatingCalculatorRoundsUpToHalfStep() {
        #expect(StarRatingCalculator.rating(atX: 81, width: 200) == 2.5)
        #expect(StarRatingCalculator.rating(atX: 180, width: 200) == 4.5)
    }

    @Test func starRatingCalculatorClampsOutOfBoundsPositions() {
        #expect(StarRatingCalculator.rating(atX: -20, width: 200) == 0.5)
        #expect(StarRatingCalculator.rating(atX: 260, width: 200) == 5.0)
        #expect(StarRatingCalculator.rating(atX: 20, width: 0) == 0.5)
    }

    @MainActor
    @Test func throwingSentimentProviderPersistsRatingFallback() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let album = Album(title: "Fallback Album", artistName: "Fallback Artist")
        let log = LogEntry(album: album, rating: 4.0, reviewText: "Provider should fail.", tags: ["fallback"])

        modelContext.insert(album)
        modelContext.insert(log)
        try modelContext.save()

        try await LogSentimentUpdater(provider: ThrowingSoundPrintProvider(failingOperation: .sentiment)).updateSentiment(for: log, in: modelContext)

        #expect(log.sentimentScore == MockSoundPrintProvider.baseScore(for: 4.0))
        #expect(log.sentimentConfidence == 0.6)
    }

    @MainActor
    @Test func coordinatorPostSaveProcessingUpdatesSentimentAndProfile() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let album = Album(title: "Post Save Album", artistName: "Post Save Artist")
        let log = LogEntry(
            album: album,
            rating: 4.5,
            reviewText: "Energetic vocals with polished replay value.",
            tags: ["repeat"]
        )

        modelContext.insert(album)
        modelContext.insert(log)
        try modelContext.save()

        await SoundPrintProfileRefreshCoordinator().processSavedLog(log, in: modelContext, provider: MockSoundPrintProvider())

        let dimensions = try modelContext.fetch(FetchDescriptor<TasteDimension>())
        #expect(log.sentimentScore != nil)
        #expect(log.sentimentConfidence != nil)
        #expect(dimensions.contains { $0.name == "energy" })
        #expect(dimensions.contains { $0.name == "vocalFocus" })
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

    @Test func favoriteTracksContributePositiveReplayabilityEvidence() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.extractTasteSignals(
            input: TasteExtractionInput(
                logID: UUID(),
                albumTitle: "Test Album",
                artistName: "Test Artist",
                genreName: nil,
                releaseYear: nil,
                rating: 4.5,
                reviewText: "",
                tags: [],
                sentimentScore: 0.7,
                favoriteTracks: ["Track One", "Track Two"]
            )
        )

        let replayability = try #require(result.signals.first { $0.dimensionName == "replayability" })
        #expect(replayability.evidenceSnippet.contains("Track One"))
    }

    @Test func standoutMomentProducesHighConfidencePositiveEvidence() async throws {
        let provider = MockSoundPrintProvider()

        let withoutStandout = try await provider.extractTasteSignals(
            input: TasteExtractionInput(
                logID: UUID(),
                albumTitle: "Test Album",
                artistName: "Test Artist",
                genreName: nil,
                releaseYear: nil,
                rating: 4.5,
                reviewText: "Polished production throughout.",
                tags: [],
                sentimentScore: 0.7
            )
        )
        let withStandout = try await provider.extractTasteSignals(
            input: TasteExtractionInput(
                logID: UUID(),
                albumTitle: "Test Album",
                artistName: "Test Artist",
                genreName: nil,
                releaseYear: nil,
                rating: 4.5,
                reviewText: "Polished production throughout.",
                tags: [],
                sentimentScore: 0.7,
                standoutMoment: "The polished bridge section really lands."
            )
        )

        let baseConfidence = try #require(withoutStandout.signals.first { $0.dimensionName == "productionStyle" }?.confidence)
        let boostedConfidence = try #require(withStandout.signals.first { $0.dimensionName == "productionStyle" }?.confidence)

        #expect(boostedConfidence > baseConfidence)
    }

    @Test func twoOrMoreSkipTracksTriggerSkipHeavyAvoidance() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.extractTasteSignals(
            input: TasteExtractionInput(
                logID: UUID(),
                albumTitle: "Test Album",
                artistName: "Test Artist",
                genreName: nil,
                releaseYear: nil,
                rating: 3.5,
                reviewText: "",
                tags: [],
                sentimentScore: 0.2,
                skipTracks: ["Track Three", "Track Four"]
            )
        )

        let skipHeavy = try #require(result.avoidanceSignals.first { $0.signalName == "skipHeavyAlbums" })
        #expect(skipHeavy.evidenceSnippet.contains("Track Three"))
    }

    @Test func negativeReviewLanguageAloneTriggersSkipHeavyAvoidance() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.extractTasteSignals(
            input: TasteExtractionInput(
                logID: UUID(),
                albumTitle: "Test Album",
                artistName: "Test Artist",
                genreName: nil,
                releaseYear: nil,
                rating: 3.0,
                reviewText: "Feels bloated and inconsistent in the middle.",
                tags: [],
                sentimentScore: 0.1
            )
        )

        #expect(result.avoidanceSignals.contains { $0.signalName == "skipHeavyAlbums" })
    }

    @Test func positiveNoSkipReviewDoesNotTriggerSkipHeavyAvoidance() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.extractTasteSignals(
            input: TasteExtractionInput(
                logID: UUID(),
                albumTitle: "Test Album",
                artistName: "Test Artist",
                genreName: nil,
                releaseYear: nil,
                rating: 4.5,
                reviewText: "Not a single skip on here.",
                tags: [],
                sentimentScore: 0.8
            )
        )

        #expect(result.signals.contains { $0.dimensionName == "tracklistConsistency" })
        #expect(!result.avoidanceSignals.contains { $0.signalName == "skipHeavyAlbums" })
    }

    @Test func skipCountAndKeywordAgreementIncreasesAvoidanceConfidenceVsEitherAlone() async throws {
        let provider = MockSoundPrintProvider()

        let countOnly = try await provider.extractTasteSignals(
            input: TasteExtractionInput(
                logID: UUID(),
                albumTitle: "Test Album",
                artistName: "Test Artist",
                genreName: nil,
                releaseYear: nil,
                rating: 3.0,
                reviewText: "",
                tags: [],
                sentimentScore: 0.1,
                skipTracks: ["A", "B", "C"]
            )
        )
        let agreement = try await provider.extractTasteSignals(
            input: TasteExtractionInput(
                logID: UUID(),
                albumTitle: "Test Album",
                artistName: "Test Artist",
                genreName: nil,
                releaseYear: nil,
                rating: 3.0,
                reviewText: "Feels bloated in the back half.",
                tags: [],
                sentimentScore: 0.1,
                skipTracks: ["A", "B", "C"]
            )
        )

        let countOnlyStrength = try #require(countOnly.avoidanceSignals.first { $0.signalName == "skipHeavyAlbums" }?.strength)
        let agreementStrength = try #require(agreement.avoidanceSignals.first { $0.signalName == "skipHeavyAlbums" }?.strength)

        #expect(agreementStrength > countOnlyStrength)
    }

    @Test func highRatingWithSkipTracksProducesModestAvoidanceAlongsidePositiveDimensions() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.extractTasteSignals(
            input: TasteExtractionInput(
                logID: UUID(),
                albumTitle: "Test Album",
                artistName: "Test Artist",
                genreName: nil,
                releaseYear: nil,
                rating: 4.5,
                reviewText: "Polished and energetic throughout.",
                tags: [],
                sentimentScore: 0.8,
                skipTracks: ["Track Three", "Track Four"]
            )
        )

        let skipHeavy = try #require(result.avoidanceSignals.first { $0.signalName == "skipHeavyAlbums" })

        #expect(!result.signals.isEmpty)
        #expect(skipHeavy.strength <= 0.4)
    }

    @Test func lowRatingWithOneFavoriteTrackDoesNotBecomeBroadPositiveClaim() async throws {
        let provider = MockSoundPrintProvider()

        // An explicit (mildly positive) sentimentScore override is used here so the log clears
        // the overall positive-signal gate despite the low star rating, letting us exercise the
        // conflict-dampening logic itself rather than the earlier "negative sentiment" cutoff.
        let result = try await provider.extractTasteSignals(
            input: TasteExtractionInput(
                logID: UUID(),
                albumTitle: "Test Album",
                artistName: "Test Artist",
                genreName: nil,
                releaseYear: nil,
                rating: 2.5,
                reviewText: "",
                tags: [],
                sentimentScore: 0.15,
                favoriteTracks: ["Track One"]
            )
        )

        let replayability = try #require(result.signals.first { $0.dimensionName == "replayability" })
        #expect(replayability.weight <= 0.3)
        #expect(replayability.confidence <= 0.35)
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

    @Test func positiveReceiptDisplayExcludesNegativeLogs() {
        let positiveAlbum = Album(title: "Positive Album", artistName: "Positive Artist")
        let negativeAlbum = Album(title: "Negative Album", artistName: "Negative Artist")
        let positiveLog = LogEntry(album: positiveAlbum, rating: 4.5, reviewText: "Polished replay value.", tags: ["repeat"], sentimentScore: 0.8)
        let negativeLog = LogEntry(album: negativeAlbum, rating: 1.5, reviewText: "Bloated and uneven.", tags: ["uneven"], sentimentScore: -0.6)
        let evidence = [
            TasteEvidence(
                dimensionName: "replayability",
                logEntryID: positiveLog.id,
                snippet: "Polished replay value.",
                evidenceType: "reviewOrTag",
                strength: 0.8,
                confidence: 0.8,
                isPositiveEvidence: true
            ),
            TasteEvidence(
                dimensionName: "replayability",
                logEntryID: negativeLog.id,
                snippet: "Bloated and uneven.",
                evidenceType: "reviewOrTag",
                strength: 0.8,
                confidence: 0.8,
                isPositiveEvidence: true
            )
        ]

        let receipts = SoundPrintReceiptDisplay.positiveReceipts(
            from: evidence,
            logsByID: [positiveLog.id: positiveLog, negativeLog.id: negativeLog]
        )

        #expect(receipts.count == 1)
        #expect(receipts[0].albumTitle == "Positive Album")
        #expect(!receipts.contains { $0.albumTitle == "Negative Album" })
    }

    @Test func positiveReceiptDisplayIncludesStoredContext() throws {
        let album = Album(title: "Blonde", artistName: "Frank Ocean")
        let log = LogEntry(
            album: album,
            rating: 4.5,
            reviewText: "Sparse intimate vocals that still feel huge.",
            tags: ["vocals", "late night"],
            sentimentScore: 0.8
        )
        let evidence = TasteEvidence(
            dimensionName: "vocalFocus",
            logEntryID: log.id,
            snippet: "Sparse intimate vocals.",
            evidenceType: "reviewOrTag",
            strength: 0.8,
            confidence: 0.8,
            isPositiveEvidence: true
        )

        let receipt = try #require(
            SoundPrintReceiptDisplay.positiveReceipts(from: [evidence], logsByID: [log.id: log]).first
        )

        #expect(receipt.sectionTitle == "You reward...")
        #expect(receipt.albumTitle == "Blonde")
        #expect(receipt.artistName == "Frank Ocean")
        #expect(receipt.ratingText == "4.5 stars")
        #expect(receipt.contextText.contains("Tagged vocals, late night"))
        #expect(receipt.snippet == "Sparse intimate vocals.")
    }

    @Test func avoidanceReceiptDisplayUsesSeparateLabelAndShortContext() throws {
        let album = Album(title: "Skip Heavy Album", artistName: "Some Artist")
        let log = LogEntry(
            album: album,
            rating: 2.0,
            reviewText: "This starts strong but becomes bloated, repetitive, uneven, and exhausting across a very long back half.",
            tags: ["uneven"],
            skipTracks: ["Track A", "Track B"],
            sentimentScore: -0.5
        )

        let receipt = try #require(
            SoundPrintReceiptDisplay.avoidanceReceipts(logIDs: [log.id], logsByID: [log.id: log]).first
        )

        #expect(receipt.sectionTitle == "You tend to avoid...")
        #expect(receipt.ratingText == "2 stars")
        #expect(receipt.contextText.contains("Tagged uneven"))
        #expect(receipt.contextText.contains("Skipped Track A, Track B"))
        #expect(receipt.snippet.count <= 96)
        #expect(receipt.snippet.hasSuffix("..."))
    }

    @Test func receiptDisplayShowsSafeCopyForMissingLog() throws {
        let evidence = TasteEvidence(
            dimensionName: "vocalFocus",
            logEntryID: UUID(),
            snippet: "Sparse intimate vocals.",
            evidenceType: "reviewOrTag",
            strength: 0.8,
            confidence: 0.8,
            isPositiveEvidence: true
        )

        let receipt = try #require(SoundPrintReceiptDisplay.positiveReceipts(from: [evidence], logsByID: [:]).first)

        #expect(receipt.albumTitle == "Original log unavailable")
        #expect(receipt.artistName == nil)
        #expect(receipt.contextText == "Original log unavailable")
        #expect(receipt.snippet == "Sparse intimate vocals.")
    }

    @MainActor
    @Test func soundPrintExtractionFailurePreservesExistingProfileData() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let album = Album(title: "Positive Album", artistName: "Positive Artist")
        let log = LogEntry(
            album: album,
            rating: 4.5,
            reviewText: "Energetic vocals with polished replay value.",
            tags: ["repeat"],
            sentimentScore: 0.8
        )
        let existingDimension = TasteDimension(
            name: "vocalFocus",
            label: "Vocal Focus",
            weight: 0.8,
            confidence: 0.7,
            summary: "Existing profile."
        )
        let existingEvidence = TasteEvidence(
            dimensionName: "vocalFocus",
            logEntryID: log.id,
            snippet: "Existing evidence.",
            evidenceType: "reviewOrTag",
            strength: 0.8,
            confidence: 0.7,
            isPositiveEvidence: true
        )

        modelContext.insert(album)
        modelContext.insert(log)
        modelContext.insert(existingDimension)
        modelContext.insert(existingEvidence)
        try modelContext.save()

        do {
            try await SoundPrintProfileBuilder(provider: ThrowingSoundPrintProvider(failingOperation: .tasteExtraction)).rebuildProfile(in: modelContext)
            Issue.record("Profile rebuild should throw when extraction fails.")
        } catch {
            let dimensions = try modelContext.fetch(FetchDescriptor<TasteDimension>())
            let evidence = try modelContext.fetch(FetchDescriptor<TasteEvidence>())

            #expect(dimensions.count == 1)
            #expect(dimensions[0].summary == "Existing profile.")
            #expect(evidence.count == 1)
            #expect(evidence[0].snippet == "Existing evidence.")
        }
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

    @Test func personaGenerationRespectsSentenceAndWordLimits() async throws {
        let provider = MockSoundPrintProvider()
        let result = try await provider.generatePersona(input: personaInput())

        #expect(result.text.soundPrintSentences.count == 2)
        #expect(result.text.normalizedSoundPrintWords.count <= SoundPrintOutputValidator.maxPersonaWordCount)
        #expect(!result.text.normalizedSoundPrintText.hasPrefix("you are"))
    }

    @Test func personaGenerationPrioritizesAvoidanceSignalOverAlbumMention() async throws {
        let provider = MockSoundPrintProvider()
        var input = personaInput()
        input = PersonaInput(
            dimensions: input.dimensions,
            recentLogs: input.recentLogs,
            totalLogCount: input.totalLogCount,
            topTags: input.topTags,
            averageRating: input.averageRating,
            avoidanceSignals: ["Skip-Heavy Albums"]
        )

        let result = try await provider.generatePersona(input: input)

        #expect(result.text.lowercased().contains("skip-heavy albums") || result.text.lowercased().contains("skip heavy albums"))
    }

    @Test func personaGenerationUsesFavoriteTrackWhenPresent() async throws {
        let provider = MockSoundPrintProvider()
        let baseInput = personaInput()
        let logsWithFavorite = baseInput.recentLogs.map { log in
            log.albumTitle == "Blonde"
                ? PersonaLogInput(
                    albumTitle: log.albumTitle,
                    artistName: log.artistName,
                    rating: log.rating,
                    reviewSnippet: log.reviewSnippet,
                    tags: log.tags,
                    isPositiveSignal: log.isPositiveSignal,
                    favoriteTracks: ["Nights"]
                )
                : log
        }
        let input = PersonaInput(
            dimensions: baseInput.dimensions,
            recentLogs: logsWithFavorite,
            totalLogCount: baseInput.totalLogCount,
            topTags: baseInput.topTags,
            averageRating: baseInput.averageRating
        )

        let result = try await provider.generatePersona(input: input)

        #expect(result.text.contains("Nights"))
    }

    @Test func personaQualityFilterRejectsVagueOrGenericText() {
        let concreteSignals = ["Vocal Focus", "Blonde", "vocals"]

        #expect(!SoundPrintOutputValidator.isPersonaValid("", concreteSignals: concreteSignals))
        #expect(!SoundPrintOutputValidator.isPersonaValid("Too short.", concreteSignals: concreteSignals))
        #expect(!SoundPrintOutputValidator.isPersonaValid("You have eclectic taste and a wide range of genres, especially around Vocal Focus and Blonde.", concreteSignals: concreteSignals))
        #expect(!SoundPrintOutputValidator.isPersonaValid("Across five logs, the profile is long enough to seem substantial, but it carefully avoids naming any actual signal from the input data.", concreteSignals: concreteSignals))
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

    @Test func mockPersonaGenerationReportsLocalFallbackSource() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.generatePersona(input: personaInput())

        #expect(result.generationSource == .localFallback)
    }

    @Test func fallbackProviderPreservesPrimaryPersonaSourceWhenPrimarySucceeds() async throws {
        let provider = FallbackSoundPrintProvider(
            primary: SourceTrackingSoundPrintProvider(source: .foundationModels),
            fallback: SourceTrackingSoundPrintProvider(source: .localFallback)
        )

        let result = try await provider.generatePersona(input: personaInput())

        #expect(result.generationSource == .foundationModels)
    }

    @Test func fallbackProviderPreservesFallbackPersonaSourceWhenPrimaryFails() async throws {
        let provider = FallbackSoundPrintProvider(
            primary: SourceTrackingSoundPrintProvider(source: .foundationModels, failsPersonaGeneration: true),
            fallback: SourceTrackingSoundPrintProvider(source: .localFallback)
        )

        let result = try await provider.generatePersona(input: personaInput())

        #expect(result.generationSource == .localFallback)
    }

    @Test func soundPrintProviderFactoryPrefersFoundationModelsWhenEnabledAndSupported() {
        let provider = SoundPrintProviderFactory.makeProvider(
            preferAppleIntelligence: true,
            isUITesting: false,
            isSimulator: false
        )

        let fallbackProvider = provider as? FallbackSoundPrintProvider

        #expect(fallbackProvider != nil)
        #expect(fallbackProvider?.primary is FoundationModelsSoundPrintProvider)
        #expect(fallbackProvider?.fallback is MockSoundPrintProvider)
    }

    @Test func soundPrintProviderFactoryUsesLocalFallbackWhenPreferenceIsOff() {
        let provider = SoundPrintProviderFactory.makeProvider(
            preferAppleIntelligence: false,
            isUITesting: false,
            isSimulator: false
        )

        #expect(provider is MockSoundPrintProvider)
    }

    @Test func soundPrintProviderFactoryUsesMockProviderForUITesting() {
        let provider = SoundPrintProviderFactory.makeProvider(
            preferAppleIntelligence: true,
            isUITesting: true,
            isSimulator: false
        )

        #expect(provider is MockSoundPrintProvider)
    }

    @Test func soundPrintProviderFactoryUsesMockProviderForSimulator() {
        let provider = SoundPrintProviderFactory.makeProvider(
            preferAppleIntelligence: true,
            isUITesting: false,
            isSimulator: true
        )

        #expect(provider is MockSoundPrintProvider)
    }

    @Test func unsupportedAppleIntelligenceAvailabilityHidesSettingsToggle() {
        let availability = SoundPrintAppleIntelligenceAvailability(
            state: .unsupported("Apple Intelligence is not available in Simulator.")
        )

        #expect(!availability.isToggleVisible)
        #expect(availability.headline == "SoundPrint is using Local fallback on this device.")
        #expect(availability.technicalDetail == "Apple Intelligence is not available in Simulator.")
    }

    @Test func supportedAppleIntelligenceAvailabilityShowsSettingsToggle() {
        let availability = SoundPrintAppleIntelligenceAvailability(
            state: .supportedUnavailable("Foundation Models availability: unavailable")
        )

        #expect(availability.isToggleVisible)
        #expect(availability.headline == "Apple Intelligence is supported, but not available right now.")
        #expect(availability.technicalDetail == "Foundation Models availability: unavailable")
    }

    @Test func soundPrintSettingsDisplayReportsAppleIntelligenceGenerator() {
        let display = SoundPrintSettingsDisplayState(
            preferAppleIntelligence: true,
            latestSource: .foundationModels,
            availability: SoundPrintAppleIntelligenceAvailability(state: .available)
        )

        #expect(display.statusTitle == "Apple Intelligence")
        #expect(display.statusDetail == "Latest SoundPrint was generated with Apple Intelligence.")
        #expect(display.currentGeneratorTitle == "Apple Intelligence")
    }

    @Test func soundPrintSettingsDisplayReportsPreferredAppleIntelligenceUsingFallback() {
        let display = SoundPrintSettingsDisplayState(
            preferAppleIntelligence: true,
            latestSource: .localFallback,
            availability: SoundPrintAppleIntelligenceAvailability(
                state: .supportedUnavailable("Foundation Models availability: unavailable")
            )
        )

        #expect(display.statusTitle == "Apple Intelligence preferred, using Local fallback")
        #expect(display.statusDetail == "Listend will try Apple Intelligence first and keep SoundPrint available locally when needed.")
        #expect(display.currentGeneratorTitle == "Local fallback")
    }

    @Test func soundPrintSettingsDisplayReportsAvailableAppleIntelligenceRejectedOutput() {
        let display = SoundPrintSettingsDisplayState(
            preferAppleIntelligence: true,
            latestSource: .localFallback,
            availability: SoundPrintAppleIntelligenceAvailability(state: .available)
        )

        #expect(display.statusTitle == "Apple Intelligence preferred, using Local fallback")
        #expect(display.statusDetail == "Apple Intelligence is available, but the latest SoundPrint fell back locally after generation did not produce a valid profile.")
    }

    @Test func compactSummaryRespectsHeadlineSummaryBulletLimits() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.generateCompactSummary(
            input: CompactSummaryInput(
                dimensions: [
                    TasteDimension(name: "mood", label: "Emotional Temperature", weight: 0.8, confidence: 0.7, summary: "s"),
                    TasteDimension(name: "replayability", label: "Replay Pull", weight: 0.6, confidence: 0.6, summary: "s")
                ],
                avoidanceSignals: [
                    TasteAvoidanceSignal(name: "skipHeavyAlbums", label: "Skip-Heavy Albums", summary: "s", strength: 0.5, confidence: 0.5)
                ]
            )
        )

        let outcome = SoundPrintOutputValidator.validateCompactSummary(
            headline: result.headline,
            summary: result.summary,
            bullets: result.bullets
        )

        #expect(outcome.isValid)
        #expect(result.bullets.count == 3)
        #expect(result.headline.normalizedSoundPrintWords.count <= SoundPrintOutputValidator.maxHeadlineWordCount)
        #expect(result.summary.normalizedSoundPrintWords.count <= SoundPrintOutputValidator.maxSummaryWordCount)
    }

    @Test func compactSummaryUsesModestOutputWithThinEvidence() async throws {
        let provider = MockSoundPrintProvider()

        let result = try await provider.generateCompactSummary(
            input: CompactSummaryInput(dimensions: [], avoidanceSignals: [])
        )

        let outcome = SoundPrintOutputValidator.validateCompactSummary(
            headline: result.headline,
            summary: result.summary,
            bullets: result.bullets
        )

        #expect(outcome.isValid)
        #expect(result.bullets.count == 3)
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
    @Test func soundPrintProfileRebuildPersistsPersonaGenerationSource() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext

        insertPersonaReadyLogs(in: modelContext, count: 5)
        try modelContext.save()

        try await SoundPrintProfileBuilder(
            provider: SourceTrackingSoundPrintProvider(source: .foundationModels)
        ).rebuildProfile(in: modelContext)

        let personas = try modelContext.fetch(FetchDescriptor<SoundPrintPersona>())
        let persona = try #require(personas.first)

        #expect(persona.generationSource == .foundationModels)
        #expect(persona.generationSourceRawValue == SoundPrintGenerationSource.foundationModels.rawValue)
    }

    @Test func soundPrintProfileRebuildPersistsPersonaTone() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext

        insertPersonaReadyLogs(in: modelContext, count: 5)
        try modelContext.save()

        let previousRawValue = UserDefaults.standard.string(forKey: SoundPrintPreferenceKey.personaTone)
        UserDefaults.standard.set(SoundPrintPersonaTone.wrapped.rawValue, forKey: SoundPrintPreferenceKey.personaTone)
        defer { UserDefaults.standard.set(previousRawValue, forKey: SoundPrintPreferenceKey.personaTone) }

        try await SoundPrintProfileBuilder(
            provider: SourceTrackingSoundPrintProvider(source: .foundationModels)
        ).rebuildProfile(in: modelContext)

        let personas = try modelContext.fetch(FetchDescriptor<SoundPrintPersona>())
        let persona = try #require(personas.first)

        #expect(persona.tone == .wrapped)
        #expect(persona.toneRawValue == SoundPrintPersonaTone.wrapped.rawValue)
    }

    @Test func soundPrintPersonaUnknownSourceCoversOldAndInvalidRawValues() {
        let oldPersona = SoundPrintPersona(personaText: "Old persona", logCountAtGeneration: 5)
        let invalidPersona = SoundPrintPersona(personaText: "Invalid persona", logCountAtGeneration: 5)
        invalidPersona.generationSourceRawValue = "not-a-source"

        #expect(oldPersona.generationSource == .unknown)
        #expect(invalidPersona.generationSource == .unknown)
    }

    @MainActor
    @Test func personaGenerationFailurePreservesLastValidPersona() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext

        insertPersonaReadyLogs(in: modelContext, count: 5)
        modelContext.insert(
            SoundPrintPersona(
                personaText: "Existing persona should survive generation failure.",
                logCountAtGeneration: 5
            )
        )
        try modelContext.save()

        try await SoundPrintProfileBuilder(provider: ThrowingSoundPrintProvider(failingOperation: .persona)).rebuildProfile(in: modelContext)

        let personas = try modelContext.fetch(FetchDescriptor<SoundPrintPersona>())
        let dimensions = try modelContext.fetch(FetchDescriptor<TasteDimension>())

        #expect(!dimensions.isEmpty)
        #expect(personas.count == 1)
        #expect(personas[0].personaText == "Existing persona should survive generation failure.")
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
    @Test func soundPrintProfileRebuildPersistsAvoidanceSignalsFromNegativeAndSkipHeavyLogs() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext

        let album = Album(title: "Skip Heavy Album", artistName: "Some Artist")
        let log = LogEntry(
            album: album,
            rating: 3.0,
            reviewText: "Feels bloated in the back half.",
            skipTracks: ["Track A", "Track B"],
            sentimentScore: 0.1
        )

        modelContext.insert(album)
        modelContext.insert(log)
        try modelContext.save()

        try await SoundPrintProfileBuilder().rebuildProfile(in: modelContext)

        let avoidanceSignals = try modelContext.fetch(FetchDescriptor<TasteAvoidanceSignal>())
        let skipHeavy = try #require(avoidanceSignals.first { $0.name == "skipHeavyAlbums" })

        #expect(skipHeavy.evidenceLogEntryIDs.contains(log.id))
    }

    @MainActor
    @Test func soundPrintProfileRebuildReplacesAvoidanceSignalsOnlyAfterSuccessAndRemovesStaleOnes() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext

        let album = Album(title: "Bloated Album", artistName: "Some Artist")
        let log = LogEntry(
            album: album,
            rating: 3.0,
            reviewText: "Feels bloated and inconsistent.",
            sentimentScore: 0.1
        )

        modelContext.insert(album)
        modelContext.insert(log)
        try modelContext.save()

        try await SoundPrintProfileBuilder().rebuildProfile(in: modelContext)

        var avoidanceSignals = try modelContext.fetch(FetchDescriptor<TasteAvoidanceSignal>())
        #expect(!avoidanceSignals.isEmpty)

        modelContext.delete(log)
        try modelContext.save()

        try await SoundPrintProfileBuilder().rebuildProfile(in: modelContext)

        avoidanceSignals = try modelContext.fetch(FetchDescriptor<TasteAvoidanceSignal>())
        #expect(avoidanceSignals.isEmpty)
    }

    @MainActor
    @Test func soundPrintProfileRebuildPreservesAvoidanceSignalsOnExtractionFailure() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext

        let album = Album(title: "Existing Album", artistName: "Some Artist")
        let log = LogEntry(album: album, rating: 3.0, reviewText: "Feels bloated.", sentimentScore: 0.1)
        let existingAvoidance = TasteAvoidanceSignal(
            name: "fillerSensitivity",
            label: "Filler Sensitivity",
            summary: "Existing avoidance.",
            strength: 0.6,
            confidence: 0.6
        )

        modelContext.insert(album)
        modelContext.insert(log)
        modelContext.insert(existingAvoidance)
        try modelContext.save()

        do {
            try await SoundPrintProfileBuilder(provider: ThrowingSoundPrintProvider(failingOperation: .tasteExtraction)).rebuildProfile(in: modelContext)
            Issue.record("Profile rebuild should throw when extraction fails.")
        } catch {
            let avoidanceSignals = try modelContext.fetch(FetchDescriptor<TasteAvoidanceSignal>())
            #expect(avoidanceSignals.count == 1)
            #expect(avoidanceSignals[0].summary == "Existing avoidance.")
        }
    }

    @MainActor
    @Test func soundPrintProfileRebuildGeneratesCompactSummaryAlongsidePersona() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext

        insertPersonaReadyLogs(in: modelContext, count: 5)
        try modelContext.save()

        try await SoundPrintProfileBuilder().rebuildProfile(in: modelContext)

        let personas = try modelContext.fetch(FetchDescriptor<SoundPrintPersona>())
        let persona = try #require(personas.first)

        #expect(persona.headline != nil)
        #expect(persona.summaryText != nil)
        #expect(persona.bullets.count == 3)
    }

    @MainActor
    @Test func compactSummaryFailureDoesNotRollBackAnAlreadyPersistedPersona() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext

        insertPersonaReadyLogs(in: modelContext, count: 5)
        try modelContext.save()

        try await SoundPrintProfileBuilder(
            provider: ThrowingSoundPrintProvider(failingOperation: .compactSummary)
        ).rebuildProfile(in: modelContext)

        let personas = try modelContext.fetch(FetchDescriptor<SoundPrintPersona>())
        let persona = try #require(personas.first)

        #expect(!persona.personaText.isEmpty)
        #expect(persona.headline == nil)
    }

    @MainActor
    @Test func recommendationGenerationExcludesLoggedAlbumsAndCreatesReceipts() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let loggedAlbum = Album(appleMusicID: "mock.frank-ocean.blonde", title: "Blonde", artistName: "Frank Ocean", releaseYear: 2016, genreName: "Alternative R&B")
        let anchorLog = LogEntry(
            album: loggedAlbum,
            rating: 5.0,
            reviewText: "Sparse intimate vocals with real replay value.",
            tags: ["vocals"],
            sentimentScore: 0.8
        )

        modelContext.insert(loggedAlbum)
        modelContext.insert(anchorLog)
        try modelContext.save()

        let recommendation = try await LocalRecommendationService().currentOrGenerateRecommendation(in: modelContext)
        let receipts = try modelContext.fetch(FetchDescriptor<RecommendationReceipt>())

        #expect(recommendation.album?.title != "Blonde")
        #expect(recommendation.status == RecommendationStatus.active.rawValue)
        #expect(!receipts.isEmpty)
        #expect(receipts[0].sourceAlbumTitle == "Blonde")
        #expect(receipts[0].sourceArtistName == "Frank Ocean")
    }

    @MainActor
    @Test func recommendationGenerationRequiresPositiveAnchorAndIgnoresNegativeLogs() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let negativeAlbum = Album(title: "Negative Album", artistName: "Negative Artist", genreName: "Art Pop")
        let negativeLog = LogEntry(
            album: negativeAlbum,
            rating: 4.5,
            reviewText: "Bad, boring, and disappointing.",
            tags: ["lush"],
            sentimentScore: -0.7
        )

        modelContext.insert(negativeAlbum)
        modelContext.insert(negativeLog)
        try modelContext.save()

        do {
            _ = try await LocalRecommendationService().currentOrGenerateRecommendation(in: modelContext)
            Issue.record("Recommendation should require a positive anchor.")
        } catch let error as LocalRecommendationError {
            #expect(error == .needsMoreLogs)
        }
    }

    @Test func musicKitAlbumMapperBuildsSearchResultFromMetadata() throws {
        let releaseDate = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2023, month: 7, day: 14)))
        let result = try #require(
            MusicKitAlbumMapper.albumSearchResult(
                from: MusicKitAlbumMetadata(
                    id: "123456789",
                    title: "  Real Album  ",
                    artistName: "  Real Artist  ",
                    releaseDate: releaseDate,
                    genreNames: ["Alternative", "Rock"],
                    artworkURL: URL(string: "https://example.com/artwork.jpg")
                )
            )
        )

        #expect(result.catalogID == "123456789")
        #expect(result.title == "Real Album")
        #expect(result.artistName == "Real Artist")
        #expect(result.releaseYear == 2023)
        #expect(result.genreName == "Alternative")
        #expect(result.artworkURL == "https://example.com/artwork.jpg")
    }

    @Test func musicKitRecentlyPlayedAlbumMapperBuildsSearchResultFromMetadata() throws {
        let releaseDate = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2024, month: 2, day: 9)))
        let result = try #require(
            MusicKitRecentlyPlayedAlbumMapper.albumSearchResult(
                from: MusicKitRecentlyPlayedAlbumMetadata(
                    id: "recent.album",
                    title: "  Recent Album  ",
                    artistName: "  Recent Artist  ",
                    releaseDate: releaseDate,
                    genreNames: ["", "Electronic"],
                    artworkURL: URL(string: "https://example.com/recent.jpg")
                )
            )
        )

        #expect(result.catalogID == "recent.album")
        #expect(result.title == "Recent Album")
        #expect(result.artistName == "Recent Artist")
        #expect(result.releaseYear == 2024)
        #expect(result.genreName == "Electronic")
        #expect(result.artworkURL == "https://example.com/recent.jpg")
    }

    @Test func musicKitRecentlyPlayedAlbumMapperRejectsInvalidMetadata() {
        let missingID = MusicKitRecentlyPlayedAlbumMapper.albumSearchResult(
            from: MusicKitRecentlyPlayedAlbumMetadata(
                id: "",
                title: "Album",
                artistName: "Artist",
                releaseDate: nil,
                genreNames: [],
                artworkURL: nil
            )
        )
        let missingTitle = MusicKitRecentlyPlayedAlbumMapper.albumSearchResult(
            from: MusicKitRecentlyPlayedAlbumMetadata(
                id: "recent.album",
                title: "  ",
                artistName: "Artist",
                releaseDate: nil,
                genreNames: [],
                artworkURL: nil
            )
        )
        let missingArtist = MusicKitRecentlyPlayedAlbumMapper.albumSearchResult(
            from: MusicKitRecentlyPlayedAlbumMetadata(
                id: "recent.album",
                title: "Album",
                artistName: "  ",
                releaseDate: nil,
                genreNames: [],
                artworkURL: nil
            )
        )

        #expect(missingID == nil)
        #expect(missingTitle == nil)
        #expect(missingArtist == nil)
    }

    @MainActor
    @Test func albumCacheUpserterDedupesByAppleMusicIDAndRefreshesMetadata() throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let existingAlbum = Album(
            appleMusicID: "music.existing",
            title: "Old Title",
            artistName: "Old Artist",
            releaseYear: 1999,
            genreName: "Old Genre",
            artworkURL: "https://example.com/old.jpg"
        )
        modelContext.insert(existingAlbum)
        try modelContext.save()

        let upsertedAlbum = try AlbumCacheUpserter.upsertAlbum(
            from: AlbumSearchResult(
                id: "music.existing",
                title: "Fresh Title",
                artistName: "Fresh Artist",
                releaseYear: 2025,
                genreName: "Fresh Genre",
                artworkURL: "https://example.com/fresh.jpg"
            ),
            cachedAlbums: [existingAlbum],
            in: modelContext
        )
        let albums = try modelContext.fetch(FetchDescriptor<Album>())

        #expect(upsertedAlbum.id == existingAlbum.id)
        #expect(albums.count == 1)
        #expect(existingAlbum.title == "Fresh Title")
        #expect(existingAlbum.artistName == "Fresh Artist")
        #expect(existingAlbum.releaseYear == 2025)
        #expect(existingAlbum.genreName == "Fresh Genre")
        #expect(existingAlbum.artworkURL == "https://example.com/fresh.jpg")
    }

    @MainActor
    @Test func albumCacheUpserterFallsBackToNormalizedTitleAndArtist() throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let existingAlbum = Album(
            title: "Cafe Bleu",
            artistName: "The Style Council",
            releaseYear: 1984
        )
        modelContext.insert(existingAlbum)
        try modelContext.save()

        let upsertedAlbum = try AlbumCacheUpserter.upsertAlbum(
            from: AlbumSearchResult(
                id: "music.cafe-bleu",
                title: "Café Bleu",
                artistName: "the style council",
                releaseYear: 1984,
                genreName: "Pop",
                artworkURL: nil
            ),
            cachedAlbums: [existingAlbum],
            in: modelContext
        )
        let albums = try modelContext.fetch(FetchDescriptor<Album>())

        #expect(upsertedAlbum.id == existingAlbum.id)
        #expect(albums.count == 1)
        #expect(existingAlbum.appleMusicID == "music.cafe-bleu")
        #expect(existingAlbum.title == "Café Bleu")
        #expect(existingAlbum.genreName == "Pop")
    }

    @Test func mockRecentlyPlayedAlbumServiceReturnsDeterministicAlbums() async throws {
        let albums = try await MockRecentlyPlayedAlbumService().recentlyPlayedAlbums()

        #expect(albums.map(\.catalogID) == [
            "mock.frank-ocean.blonde",
            "mock.sza.sos",
            "mock.radiohead.in-rainbows",
            "mock.fiona-apple.fetch-the-bolt-cutters"
        ])
    }

    @MainActor
    @Test func recentlyPlayedAlbumCacheStoresAlbumsInFetchOrder() throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext

        try RecentlyPlayedAlbumCache.replaceCachedAlbums(
            with: [
                AlbumSearchResult(id: "music.first", title: "First", artistName: "Artist One", releaseYear: 2020, genreName: "Pop"),
                AlbumSearchResult(id: "music.second", title: "Second", artistName: "Artist Two", releaseYear: 2021, genreName: "Rock")
            ],
            in: modelContext
        )

        let cachedAlbums = try RecentlyPlayedAlbumCache.cachedAlbums(in: modelContext)

        #expect(cachedAlbums.map(\.catalogID) == ["music.first", "music.second"])
        #expect(cachedAlbums.first?.title == "First")
        #expect(cachedAlbums.first?.artistName == "Artist One")
        #expect(cachedAlbums.first?.releaseYear == 2020)
        #expect(cachedAlbums.first?.genreName == "Pop")
    }

    @MainActor
    @Test func recentlyPlayedAlbumCacheReplacesStaleAlbumsAndDedupesCatalogIDs() throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext

        try RecentlyPlayedAlbumCache.replaceCachedAlbums(
            with: [
                AlbumSearchResult(id: "music.old", title: "Old", artistName: "Old Artist", releaseYear: nil, genreName: nil),
                AlbumSearchResult(id: "music.duplicate", title: "Earlier Duplicate", artistName: "Artist", releaseYear: 2020, genreName: "Pop")
            ],
            in: modelContext
        )

        try RecentlyPlayedAlbumCache.replaceCachedAlbums(
            with: [
                AlbumSearchResult(id: "music.duplicate", title: "Fresh Duplicate", artistName: "Artist", releaseYear: 2024, genreName: "Soul"),
                AlbumSearchResult(id: "music.duplicate", title: "Ignored Duplicate", artistName: "Artist", releaseYear: 2025, genreName: "Rock"),
                AlbumSearchResult(id: "music.new", title: "New", artistName: "New Artist", releaseYear: 2026, genreName: "Jazz")
            ],
            in: modelContext
        )

        let cachedAlbums = try RecentlyPlayedAlbumCache.cachedAlbums(in: modelContext)
        let snapshots = try modelContext.fetch(FetchDescriptor<RecentlyPlayedAlbumSnapshot>())

        #expect(cachedAlbums.map(\.catalogID) == ["music.duplicate", "music.new"])
        #expect(cachedAlbums.first?.title == "Fresh Duplicate")
        #expect(cachedAlbums.first?.releaseYear == 2024)
        #expect(cachedAlbums.first?.genreName == "Soul")
        #expect(snapshots.count == 2)
    }

    @MainActor
    @Test func recentlyPlayedAlbumLogStateMatchesLoggedAlbumsByCatalogIDOrTitleAndArtist() {
        let catalogAlbum = Album(appleMusicID: "music.catalog", title: "Old Title", artistName: "Old Artist")
        let titleArtistAlbum = Album(title: "Cafe Bleu", artistName: "The Style Council")
        let logs = [
            LogEntry(album: catalogAlbum, rating: 4.0),
            LogEntry(album: titleArtistAlbum, rating: 3.5)
        ]

        let catalogMatch = AlbumSearchResult(
            id: "music.catalog",
            title: "Fresh Title",
            artistName: "Fresh Artist",
            releaseYear: nil,
            genreName: nil
        )
        let titleArtistMatch = AlbumSearchResult(
            id: "music.cafe-bleu",
            title: "Café Bleu",
            artistName: "the style council",
            releaseYear: nil,
            genreName: nil
        )
        let unloggedAlbum = AlbumSearchResult(
            id: "music.unlogged",
            title: "Unlogged",
            artistName: "Artist",
            releaseYear: nil,
            genreName: nil
        )

        #expect(RecentlyPlayedAlbumLogState.isLogged(catalogMatch, in: logs))
        #expect(RecentlyPlayedAlbumLogState.isLogged(titleArtistMatch, in: logs))
        #expect(!RecentlyPlayedAlbumLogState.isLogged(unloggedAlbum, in: logs))
    }

    @MainActor
    @Test func albumSelectionUpserterCachesSelectedAlbum() throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let selectedAlbum = try AlbumSelectionUpserter.cachedAlbum(
            from: AlbumSearchResult(
                id: "music.selected",
                title: "Selected Album",
                artistName: "Selected Artist",
                releaseYear: 2026,
                genreName: "Pop",
                artworkURL: "https://example.com/selected.jpg"
            ),
            cachedAlbums: [],
            in: modelContext
        )
        let albums = try modelContext.fetch(FetchDescriptor<Album>())

        #expect(albums.count == 1)
        #expect(selectedAlbum.appleMusicID == "music.selected")
        #expect(selectedAlbum.title == "Selected Album")
        #expect(selectedAlbum.artistName == "Selected Artist")
    }

    @Test func localTagSuggestionsUseAlbumGenreAndReviewKeywords() {
        let input = TagSuggestionInput(
            albumTitle: "SOS",
            artistName: "SZA",
            genreName: "R&B",
            releaseYear: 2022,
            reviewText: "Late night vocals with repeat value.",
            existingTags: []
        )
        let tags = LocalTagSuggestionProvider.suggestedTags(for: input)

        #expect(tags.contains("r&b"))
        #expect(tags.contains("late night"))
        #expect(tags.contains("vocals"))
        #expect(tags.contains("repeat"))
    }

    @Test func tagSuggestionValidationFiltersDuplicatesAndInvalidTags() {
        let input = TagSuggestionInput(
            albumTitle: "Blonde",
            artistName: "Frank Ocean",
            reviewText: "",
            existingTags: ["Late Night"]
        )
        let tags = TagSuggestionValidator.validatedTags(
            ["late night", "Vocals", "Blonde", "Frank Ocean", "two, tags", "this tag is far too long to keep"],
            input: input
        )

        #expect(tags == ["vocals"])
    }

    @Test func foundationModelsTagValidationRejectsInvalidPayload() throws {
        let input = TagSuggestionInput(
            albumTitle: "Blonde",
            artistName: "Frank Ocean",
            reviewText: "",
            existingTags: []
        )

        do {
            _ = try FoundationModelsTagSuggestionValidator.validatedTags(
                FoundationModelsTagSuggestionPayload(tags: ["Blonde", "Frank Ocean", "two, tags"]),
                input: input
            )
            Issue.record("Invalid model tags should be rejected.")
        } catch let error as TagSuggestionProviderError {
            #expect(error == .validationFailed)
        }
    }

    @Test func foundationModelsTagValidationAcceptsCleanTags() throws {
        let input = TagSuggestionInput(
            albumTitle: "Blonde",
            artistName: "Frank Ocean",
            reviewText: "Late night vocals.",
            existingTags: ["vocals"]
        )
        let tags = try FoundationModelsTagSuggestionValidator.validatedTags(
            FoundationModelsTagSuggestionPayload(tags: ["Late Night", "Vocals", "Warm"]),
            input: input
        )

        #expect(tags == ["late night", "warm"])
    }

    @Test func mockTagSuggestionProviderReturnsDeterministicTags() async throws {
        let tags = try await MockTagSuggestionProvider().suggestedTags(
            for: TagSuggestionInput(
                albumTitle: "SOS",
                artistName: "SZA",
                genreName: "R&B",
                releaseYear: 2022,
                reviewText: "Late night vocals.",
                existingTags: []
            )
        )

        #expect(tags == ["r&b", "late night", "vocals", "modern"])
    }

    @Test func mockJournalAssistServiceReturnsDeterministicDraft() async throws {
        let input = JournalAssistInput(
            albumTitle: "SOS",
            artistName: "SZA",
            genreName: "R&B",
            releaseYear: 2022,
            rating: 4.5,
            notes: "Late night vocals.",
            existingTags: ["warm"]
        )

        let result = try await MockJournalAssistService().draftReview(for: input)

        #expect(result.draftReview == "I rated SOS by SZA 4.5/5. My notes point to Late night vocals, warm.")
        #expect(result.prompts.isEmpty)
    }

    @Test func journalAssistStaticPromptsDoNotRequireFoundationModels() {
        let prompts = MockJournalAssistService().reflectionPrompts

        #expect(prompts.count == 4)
        #expect(prompts.map(\.question).contains("What stood out most?"))
    }

    @Test func emptyJournalAssistInputProducesPromptsInsteadOfDraft() async throws {
        let input = JournalAssistInput(albumTitle: "Blonde", artistName: "Frank Ocean")

        let result = try await MockJournalAssistService().draftReview(for: input)

        #expect(result.draftReview == nil)
        #expect(result.prompts == JournalAssistPrompt.defaults)
    }

    @Test func journalAssistDraftValidationRejectsInvalidDrafts() throws {
        let input = JournalAssistInput(
            albumTitle: "Blonde",
            artistName: "Frank Ocean",
            notes: "Sparse vocals."
        )

        #expect(throws: JournalAssistServiceError.emptyOutput) {
            _ = try JournalAssistValidator.validatedDraft("", input: input)
        }

        #expect(throws: JournalAssistServiceError.validationFailed) {
            _ = try JournalAssistValidator.validatedDraft("One. Two. Three. Four. Five.", input: input)
        }

        #expect(throws: JournalAssistServiceError.validationFailed) {
            _ = try JournalAssistValidator.validatedDraft("This is a flawless masterpiece.", input: input)
        }

        #expect(throws: JournalAssistServiceError.validationFailed) {
            _ = try JournalAssistValidator.validatedDraft("I loved the catchy hooks.", input: input)
        }
    }

    @Test func journalAssistTagValidationFiltersDuplicatesAndInvalidTags() {
        let input = JournalAssistInput(
            albumTitle: "Blonde",
            artistName: "Frank Ocean",
            existingTags: ["Late Night"]
        )
        let tags = JournalAssistValidator.validatedTags(
            ["late night", "Vocals", "two, tags", "this tag has way too many words"],
            input: input
        )

        #expect(tags == ["vocals"])
    }

    @Test func mockJournalAssistTagSuggestionsAreManualServiceOutput() async throws {
        let input = JournalAssistInput(
            albumTitle: "SOS",
            artistName: "SZA",
            genreName: "R&B",
            rating: 4.0,
            notes: "Late night vocals.",
            existingTags: ["vocals"]
        )

        let tags = try await MockJournalAssistService().suggestedTags(for: input)

        #expect(tags == ["late night", "r&b", "repeat"])
    }

    @Test func reflectionPromptInsertsIntoEmptyReview() {
        let updated = LogReflectionPromptInserter.insert("What stood out: ", into: "")

        #expect(updated == "What stood out: ")
    }

    @Test func reflectionPromptInsertsIntoWhitespaceOnlyReview() {
        let updated = LogReflectionPromptInserter.insert("Favorite moment: ", into: "   \n  ")

        #expect(updated == "Favorite moment: ")
    }

    @Test func reflectionPromptAppendsOnNewLine() {
        let updated = LogReflectionPromptInserter.insert("Favorite moment: ", into: "Already wrote something.")

        #expect(updated == "Already wrote something.\nFavorite moment: ")
    }

    @Test func reflectionPromptAppendsWithoutExtraBlankLineWhenReviewEndsWithNewline() {
        let updated = LogReflectionPromptInserter.insert("Replay value: ", into: "Already wrote something.\n")

        #expect(updated == "Already wrote something.\nReplay value: ")
    }

    @Test func reflectionPromptPreservesExistingReviewBody() {
        let existing = "  Already wrote something.  \n"
        let updated = LogReflectionPromptInserter.insert("How it felt: ", into: existing)

        #expect(updated == "  Already wrote something.  \nHow it felt: ")
    }

    @Test func reflectionPromptDoesNotDuplicateSamePrompt() {
        let unchanged = LogReflectionPromptInserter.insert("What stood out: ", into: "What stood out: great")

        #expect(unchanged == "What stood out: great")
    }

    @Test func reflectionPromptDoesNotDuplicateWithDifferentCasing() {
        let unchanged = LogReflectionPromptInserter.insert("What stood out: ", into: "WHAT STOOD OUT: great")

        #expect(unchanged == "WHAT STOOD OUT: great")
    }

    @Test func reflectionPromptAllowsDifferentPrompts() {
        let updated = LogReflectionPromptInserter.insert("Replay value: ", into: "What stood out: great")

        #expect(updated == "What stood out: great\nReplay value: ")
    }

    @Test func acceptingJournalAssistDraftUpdatesReviewText() {
        let updated = JournalAssistValidator.applyDraft("  I rated SOS by SZA 4.5/5.  ", to: "Original review.")

        #expect(updated == "I rated SOS by SZA 4.5/5.")
    }

    @Test func dismissingJournalAssistDraftLeavesReviewTextUnchanged() {
        let unchanged = JournalAssistValidator.dismissDraft(currentReviewText: "Original review.")

        #expect(unchanged == "Original review.")
    }

    @Test func fallbackJournalAssistServiceUsesFallbackWhenPrimaryThrows() async throws {
        let service = FallbackJournalAssistService(
            primary: ThrowingJournalAssistService(),
            fallback: MockJournalAssistService()
        )
        let input = JournalAssistInput(
            albumTitle: "SOS",
            artistName: "SZA",
            rating: 4.5,
            notes: "Late night vocals."
        )

        let result = try await service.draftReview(for: input)

        #expect(result.draftReview == "I rated SOS by SZA 4.5/5. My notes point to Late night vocals.")
    }

    @Test func fallbackJournalAssistServicePropagatesCancellation() async {
        let service = FallbackJournalAssistService(
            primary: CancellingJournalAssistService(),
            fallback: MockJournalAssistService()
        )

        do {
            _ = try await service.draftReview(
                for: JournalAssistInput(albumTitle: "SOS", artistName: "SZA", rating: 4.0)
            )
            Issue.record("Cancellation should propagate instead of falling back.")
        } catch is CancellationError {
            #expect(true)
        } catch {
            Issue.record("Expected CancellationError, got \(error).")
        }
    }

    @Test func musicKitPreviewMapperSelectsFirstValidTrackPreviewURL() throws {
        let preview = try #require(
            MusicKitAlbumPreviewMapper.preview(
                albumCatalogID: "music.album",
                tracks: [
                    MusicKitPreviewTrackMetadata(title: "No Preview", previewAssetURLs: []),
                    MusicKitPreviewTrackMetadata(
                        title: "First Preview",
                        previewAssetURLs: [
                            URL(string: "not-a-valid-url")!,
                            URL(string: "https://example.com/preview.m4a")!
                        ]
                    ),
                    MusicKitPreviewTrackMetadata(
                        title: "Second Preview",
                        previewAssetURLs: [URL(string: "https://example.com/second.m4a")!]
                    )
                ]
            )
        )

        #expect(preview.albumCatalogID == "music.album")
        #expect(preview.trackTitle == "First Preview")
        #expect(preview.previewURL.absoluteString == "https://example.com/preview.m4a")
    }

    @Test func musicKitPreviewMapperReturnsNilWhenNoTrackHasPreviewURL() {
        let preview = MusicKitAlbumPreviewMapper.preview(
            albumCatalogID: "music.album",
            tracks: [
                MusicKitPreviewTrackMetadata(title: "No Preview", previewAssetURLs: []),
                MusicKitPreviewTrackMetadata(title: "Also No Preview", previewAssetURLs: [])
            ]
        )

        #expect(preview == nil)
    }

    @Test func fallbackPreviewServiceReturnsNilWhenPrimaryThrowsOrReturnsNil() async throws {
        let throwingService = FallbackAlbumPreviewService(
            primary: ThrowingAlbumPreviewService(),
            fallback: MockAlbumPreviewService()
        )
        let emptyService = FallbackAlbumPreviewService(
            primary: EmptyAlbumPreviewService(),
            fallback: MockAlbumPreviewService()
        )
        let lookup = AlbumPreviewLookup(albumCatalogID: "music.album", title: "Album", artistName: "Artist")

        let throwingPreview = try await throwingService.preview(for: lookup)
        let emptyPreview = try await emptyService.preview(for: lookup)

        #expect(throwingPreview == nil)
        #expect(emptyPreview == nil)
    }

    @Test func mockPreviewServiceReturnsNilWithoutThrowing() async throws {
        let lookup = AlbumPreviewLookup(albumCatalogID: "music.album", title: "Album", artistName: "Artist")
        let preview = try await MockAlbumPreviewService().preview(for: lookup)

        #expect(preview == nil)
    }

    @Test func previewLookupBuildsFromSearchResultAndStoredAlbum() {
        let searchResult = AlbumSearchResult(
            id: "music.search",
            title: "Search Album",
            artistName: "Search Artist",
            releaseYear: nil,
            genreName: nil
        )
        let storedAlbum = Album(
            appleMusicID: "music.stored",
            title: "Stored Album",
            artistName: "Stored Artist"
        )

        let searchLookup = AlbumPreviewLookup(album: searchResult)
        let storedLookup = AlbumPreviewLookup(album: storedAlbum)

        #expect(searchLookup.albumCatalogID == "music.search")
        #expect(searchLookup.title == "Search Album")
        #expect(searchLookup.artistName == "Search Artist")
        #expect(storedLookup.albumCatalogID == "music.stored")
        #expect(storedLookup.title == "Stored Album")
        #expect(storedLookup.artistName == "Stored Artist")
    }

    @Test func fallbackCatalogReturnsMockResultsWhenPrimaryThrows() async throws {
        let service = FallbackAlbumCatalogService(
            primary: ThrowingAlbumCatalogService(),
            fallback: MockAlbumCatalogService()
        )

        let results = try await service.searchAlbums(query: "SOS")

        #expect(results.map(\.catalogID).contains("mock.sza.sos"))
    }

    @Test func mockCatalogKeepsSOSIdentifierStable() async throws {
        let results = try await MockAlbumCatalogService().searchAlbums(query: "SOS")

        #expect(results.first?.catalogID == "mock.sza.sos")
    }

    @MainActor
    @Test func recommendationUpsertStoresAndRefreshesArtworkMetadata() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let anchorAlbum = Album(title: "Anchor", artistName: "Anchor Artist", releaseYear: 2021, genreName: "Art Pop")
        let existingCandidateAlbum = Album(
            title: "Artwork Pick",
            artistName: "Artwork Artist",
            releaseYear: 2020,
            genreName: "Art Pop",
            artworkURL: "https://example.com/old.jpg"
        )
        let anchorLog = LogEntry(album: anchorAlbum, rating: 4.5, tags: ["art"], sentimentScore: 0.8)
        let service = LocalRecommendationService(
            catalogAlbums: [
                AlbumSearchResult(
                    id: "music.real-artwork-pick",
                    title: "Artwork Pick",
                    artistName: "Artwork Artist",
                    releaseYear: 2020,
                    genreName: "Art Pop",
                    artworkURL: "https://example.com/new.jpg"
                )
            ]
        )

        modelContext.insert(anchorAlbum)
        modelContext.insert(existingCandidateAlbum)
        modelContext.insert(anchorLog)
        try modelContext.save()

        let recommendation = try await service.currentOrGenerateRecommendation(in: modelContext)

        #expect(recommendation.album?.id == existingCandidateAlbum.id)
        #expect(existingCandidateAlbum.appleMusicID == "music.real-artwork-pick")
        #expect(existingCandidateAlbum.artworkURL == "https://example.com/new.jpg")
    }

    @Test func recommendationCandidateProviderBuildsDeterministicQueries() {
        let logID = UUID()
        let queries = CatalogRecommendationCandidateProvider.searchQueries(
            anchors: [
                RecommendationAnchorInput(
                    logID: logID,
                    albumCatalogID: "mock.weyes-blood.titanic-rising",
                    albumTitle: "Titanic Rising",
                    artistName: "Weyes Blood",
                    genreName: "Art Pop",
                    tags: ["lush", "layered"]
                )
            ],
            evidence: [
                RecommendationEvidenceInput(
                    logEntryID: logID,
                    dimensionName: "vocalFocus",
                    strength: 0.9,
                    isPositiveEvidence: true
                )
            ]
        )

        #expect(queries == ["Art Pop", "Weyes Blood", "layered", "vocalFocus", "lush"])
    }

    @Test func recommendationCandidateProviderDedupesAndCapsCatalogResults() async {
        let service = RecordingAlbumCatalogService(
            resultsByQuery: [
                "Art Pop": [
                    AlbumSearchResult(id: "music.duplicate", title: "First", artistName: "Artist", releaseYear: 2022, genreName: "Art Pop"),
                    AlbumSearchResult(id: "music.duplicate", title: "Duplicate", artistName: "Artist", releaseYear: 2022, genreName: "Art Pop"),
                    AlbumSearchResult(id: "music.second", title: "Second", artistName: "Artist", releaseYear: 2021, genreName: "Art Pop")
                ]
            ]
        )
        let provider = CatalogRecommendationCandidateProvider(
            catalogService: service,
            fallbackCandidates: [],
            candidateLimit: 2
        )

        let candidates = await provider.candidates(
            anchors: [
                RecommendationAnchorInput(
                    logID: UUID(),
                    albumCatalogID: nil,
                    albumTitle: "Anchor",
                    artistName: "Anchor Artist",
                    genreName: "Art Pop",
                    tags: []
                )
            ],
            evidence: [],
            loggedAlbums: []
        )

        #expect(candidates.map(\.catalogID) == ["music.duplicate", "music.second"])
    }

    @Test func recommendationCandidateProviderFallsBackWhenCatalogThrowsOrReturnsEmpty() async {
        let fallback = [
            AlbumSearchResult(id: "mock.fallback", title: "Fallback", artistName: "Fallback Artist", releaseYear: nil, genreName: "Art Pop")
        ]
        let throwingProvider = CatalogRecommendationCandidateProvider(
            catalogService: RecordingAlbumCatalogService(error: ThrowingAlbumCatalogError.failed),
            fallbackCandidates: fallback
        )
        let emptyProvider = CatalogRecommendationCandidateProvider(
            catalogService: RecordingAlbumCatalogService(resultsByQuery: [:]),
            fallbackCandidates: fallback
        )
        let anchors = [
            RecommendationAnchorInput(
                logID: UUID(),
                albumCatalogID: nil,
                albumTitle: "Anchor",
                artistName: "Anchor Artist",
                genreName: "Art Pop",
                tags: []
            )
        ]

        let throwingCandidates = await throwingProvider.candidates(anchors: anchors, evidence: [], loggedAlbums: [])
        let emptyCandidates = await emptyProvider.candidates(anchors: anchors, evidence: [], loggedAlbums: [])

        #expect(throwingCandidates.map(\.catalogID) == ["mock.fallback"])
        #expect(emptyCandidates.map(\.catalogID) == ["mock.fallback"])
    }

    @Test func recommendationCandidateProviderStopsQueryingAfterCancellation() async {
        let service = RecordingAlbumCatalogService(error: CancellationError())
        let fallback = [
            AlbumSearchResult(id: "mock.fallback", title: "Fallback", artistName: "Fallback Artist", releaseYear: nil, genreName: "Art Pop")
        ]
        let provider = CatalogRecommendationCandidateProvider(
            catalogService: service,
            fallbackCandidates: fallback
        )

        let candidates = await provider.candidates(
            anchors: [
                RecommendationAnchorInput(
                    logID: UUID(),
                    albumCatalogID: nil,
                    albumTitle: "Anchor",
                    artistName: "Anchor Artist",
                    genreName: "Art Pop",
                    tags: ["lush"]
                )
            ],
            evidence: [],
            loggedAlbums: []
        )

        #expect(service.queries == ["Art Pop"])
        #expect(candidates.isEmpty)
    }

    @Test func recommendationCandidateProviderExcludesLoggedCatalogResults() async {
        let service = RecordingAlbumCatalogService(
            resultsByQuery: [
                "Art Pop": [
                    AlbumSearchResult(id: "music.logged", title: "Logged", artistName: "Logged Artist", releaseYear: 2020, genreName: "Art Pop"),
                    AlbumSearchResult(id: "music.new", title: "New", artistName: "New Artist", releaseYear: 2021, genreName: "Art Pop")
                ]
            ]
        )
        let provider = CatalogRecommendationCandidateProvider(catalogService: service, fallbackCandidates: [])

        let candidates = await provider.candidates(
            anchors: [
                RecommendationAnchorInput(
                    logID: UUID(),
                    albumCatalogID: nil,
                    albumTitle: "Anchor",
                    artistName: "Anchor Artist",
                    genreName: "Art Pop",
                    tags: []
                )
            ],
            evidence: [],
            loggedAlbums: [
                RecommendationLoggedAlbumInput(catalogID: "music.logged", title: "Logged", artistName: "Logged Artist")
            ]
        )

        #expect(candidates.map(\.catalogID) == ["music.new"])
    }

    @MainActor
    @Test func recommendationGenerationUsesLiveCatalogCandidatesAndReceipts() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let anchorAlbum = Album(title: "Titanic Rising", artistName: "Weyes Blood", releaseYear: 2019, genreName: "Art Pop")
        let anchorLog = LogEntry(album: anchorAlbum, rating: 4.5, tags: ["lush"], sentimentScore: 0.8)
        let catalogService = RecordingAlbumCatalogService(
            resultsByQuery: [
                "Art Pop": [
                    AlbumSearchResult(id: "music.live-pick", title: "Live Pick", artistName: "Live Artist", releaseYear: 2024, genreName: "Art Pop")
                ]
            ]
        )

        modelContext.insert(anchorAlbum)
        modelContext.insert(anchorLog)
        try modelContext.save()

        let recommendation = try await LocalRecommendationService(
            catalogService: catalogService,
            fallbackCandidates: []
        ).currentOrGenerateRecommendation(in: modelContext)
        let receipts = try modelContext.fetch(FetchDescriptor<RecommendationReceipt>())

        #expect(recommendation.album?.appleMusicID == "music.live-pick")
        #expect(recommendation.explanationText.contains("Titanic Rising"))
        #expect(receipts.first?.sourceAlbumTitle == "Titanic Rising")
    }

    @Test func appleMusicPersonalRecommendationMapperKeepsAlbumsAndDropsOtherItems() {
        let albums = AppleMusicPersonalRecommendationMapper.albumSearchResults(
            from: [
                AppleMusicPersonalRecommendationMetadata(
                    kind: .album,
                    id: "music.album",
                    title: "Apple Pick",
                    artistName: "Apple Artist",
                    releaseYear: 2025,
                    genreName: "Alternative",
                    artworkURL: "https://example.com/apple.jpg"
                ),
                AppleMusicPersonalRecommendationMetadata(
                    kind: .playlist,
                    id: "music.playlist",
                    title: "Playlist",
                    artistName: "Curator",
                    releaseYear: nil,
                    genreName: nil,
                    artworkURL: nil
                )
            ]
        )

        #expect(albums.map(\.catalogID) == ["music.album"])
        #expect(albums.first?.title == "Apple Pick")
        #expect(albums.first?.artworkURL == "https://example.com/apple.jpg")
    }

    @MainActor
    @Test func appleMusicFreshnessFilterBlocksRecentLibraryLoggedAndRollingSnapshotAlbums() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let loggedAlbum = Album(appleMusicID: "music.logged", title: "Logged", artistName: "Logged Artist", genreName: "Art Pop")
        let anchorAlbum = Album(title: "Anchor", artistName: "Anchor Artist", genreName: "Art Pop")
        let anchorLog = LogEntry(album: anchorAlbum, rating: 4.5, tags: ["art"], sentimentScore: 0.8)
        let service = RecordingAppleMusicRecommendationService(
            personalRecommendations: [
                AlbumSearchResult(id: "music.logged", title: "Logged", artistName: "Logged Artist", releaseYear: nil, genreName: "Art Pop"),
                AlbumSearchResult(id: "music.recent", title: "Recent", artistName: "Recent Artist", releaseYear: nil, genreName: "Art Pop"),
                AlbumSearchResult(id: "music.library", title: "Library", artistName: "Library Artist", releaseYear: nil, genreName: "Art Pop"),
                AlbumSearchResult(id: "music.snapshot", title: "Snapshot", artistName: "Snapshot Artist", releaseYear: nil, genreName: "Art Pop"),
                AlbumSearchResult(id: "music.available", title: "Available", artistName: "Available Artist", releaseYear: nil, genreName: "Art Pop")
            ],
            recentlyPlayedAlbums: [
                AlbumSearchResult(id: "music.recent", title: "Recent", artistName: "Recent Artist", releaseYear: nil, genreName: "Art Pop")
            ],
            libraryCatalogIDs: ["music.library"]
        )
        let recommendationService = LocalRecommendationService(
            catalogAlbums: [],
            appleMusicService: service
        )

        modelContext.insert(loggedAlbum)
        modelContext.insert(anchorAlbum)
        modelContext.insert(anchorLog)
        modelContext.insert(
            AppleMusicRecentPlaySnapshot(
                catalogID: "music.snapshot",
                title: "Snapshot",
                artistName: "Snapshot Artist",
                lastObservedAt: Date().addingTimeInterval(-30 * 86_400)
            )
        )
        try modelContext.save()

        let recommendation = try await recommendationService.currentOrGenerateRecommendation(in: modelContext)

        #expect(recommendation.album?.appleMusicID == "music.available")
        #expect(recommendation.source == RecommendationSource.applePersonalRecommendations.rawValue)
        #expect(recommendation.freshnessStatus == RecommendationFreshnessStatus.appleFreshnessChecked.rawValue)
    }

    @MainActor
    @Test func oldAppleMusicRecentPlaySnapshotDoesNotBlockCandidate() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let anchorAlbum = Album(title: "Anchor", artistName: "Anchor Artist", genreName: "Art Pop")
        let anchorLog = LogEntry(album: anchorAlbum, rating: 4.5, tags: ["art"], sentimentScore: 0.8)
        let candidate = AlbumSearchResult(id: "music.old-snapshot", title: "Old Snapshot", artistName: "Old Artist", releaseYear: nil, genreName: "Art Pop")
        let appleMusicService = RecordingAppleMusicRecommendationService(personalRecommendations: [candidate])

        modelContext.insert(anchorAlbum)
        modelContext.insert(anchorLog)
        modelContext.insert(
            AppleMusicRecentPlaySnapshot(
                catalogID: "music.old-snapshot",
                title: "Old Snapshot",
                artistName: "Old Artist",
                lastObservedAt: Date().addingTimeInterval(-120 * 86_400)
            )
        )
        try modelContext.save()

        let recommendation = try await LocalRecommendationService(
            catalogAlbums: [],
            appleMusicService: appleMusicService
        ).currentOrGenerateRecommendation(in: modelContext)

        #expect(recommendation.album?.appleMusicID == "music.old-snapshot")
        #expect(recommendation.freshnessStatus == RecommendationFreshnessStatus.appleFreshnessChecked.rawValue)
    }

    @MainActor
    @Test func appleMusicUnavailableFallsBackToListendRecommendationWithDisclosureMetadata() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let anchorAlbum = Album(title: "Anchor", artistName: "Anchor Artist", genreName: "Art Pop")
        let anchorLog = LogEntry(album: anchorAlbum, rating: 4.5, tags: ["art"], sentimentScore: 0.8)

        modelContext.insert(anchorAlbum)
        modelContext.insert(anchorLog)
        try modelContext.save()

        let recommendation = try await LocalRecommendationService(
            catalogAlbums: [
                AlbumSearchResult(id: "mock.listend-fallback", title: "Listend Fallback", artistName: "Fallback Artist", releaseYear: nil, genreName: "Art Pop")
            ],
            appleMusicService: ThrowingAppleMusicRecommendationService()
        ).currentOrGenerateRecommendation(in: modelContext)

        #expect(recommendation.album?.appleMusicID == "mock.listend-fallback")
        #expect(recommendation.source == RecommendationSource.listendFallback.rawValue)
        #expect(recommendation.freshnessStatus == RecommendationFreshnessStatus.appleFreshnessUnavailable.rawValue)
    }

    @MainActor
    @Test func recommendationGenerationDoesNotUseNegativeLogsAsLiveCatalogQueries() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let positiveAlbum = Album(title: "Positive Album", artistName: "Positive Artist", genreName: "Art Pop")
        let negativeAlbum = Album(title: "Negative Album", artistName: "Negative Artist", genreName: "Metal")
        let positiveLog = LogEntry(album: positiveAlbum, rating: 4.5, tags: ["lush"], sentimentScore: 0.8)
        let negativeLog = LogEntry(album: negativeAlbum, rating: 4.5, tags: ["heavy"], sentimentScore: -0.7)
        let catalogService = RecordingAlbumCatalogService(
            resultsByQuery: [
                "Art Pop": [
                    AlbumSearchResult(id: "music.live-pick", title: "Live Pick", artistName: "Live Artist", releaseYear: nil, genreName: "Art Pop")
                ],
                "Metal": [
                    AlbumSearchResult(id: "music.negative-pick", title: "Negative Pick", artistName: "Negative Artist", releaseYear: nil, genreName: "Metal")
                ]
            ]
        )

        modelContext.insert(positiveAlbum)
        modelContext.insert(negativeAlbum)
        modelContext.insert(positiveLog)
        modelContext.insert(negativeLog)
        try modelContext.save()

        _ = try await LocalRecommendationService(
            catalogService: catalogService,
            fallbackCandidates: []
        ).currentOrGenerateRecommendation(in: modelContext)

        #expect(catalogService.queries.contains("Art Pop"))
        #expect(!catalogService.queries.contains("Metal"))
        #expect(!catalogService.queries.contains("heavy"))
    }

    @MainActor
    @Test func recommendationScoringPrefersGenreAndTagMatchesDeterministically() throws {
        let service = LocalRecommendationService(
            catalogAlbums: [
                AlbumSearchResult(id: "mock.z.unrelated", title: "Unrelated", artistName: "Zed", releaseYear: 1991, genreName: "Metal"),
                AlbumSearchResult(id: "mock.a.match", title: "Vocals Forever", artistName: "Alpha", releaseYear: 2019, genreName: "Art Pop")
            ]
        )
        let anchorAlbum = Album(title: "Anchor", artistName: "Anchor Artist", releaseYear: 2019, genreName: "Art Pop")
        let anchorLog = LogEntry(
            album: anchorAlbum,
            rating: 4.5,
            reviewText: "Great vocals.",
            tags: ["vocals"],
            sentimentScore: 0.8
        )

        let candidate = service.bestCandidate(
            logs: [anchorLog],
            localAlbums: [anchorAlbum],
            evidence: [],
            recommendations: [],
            anchors: [anchorLog],
            allowDismissed: false
        )

        #expect(candidate?.album.catalogID == "mock.a.match")
    }

    @MainActor
    @Test func recommendationGenerationReusesOneActiveRecommendation() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let anchorAlbum = Album(title: "Anchor", artistName: "Anchor Artist", releaseYear: 2019, genreName: "Art Pop")
        let activeAlbum = Album(title: "Active Pick", artistName: "Active Artist")
        let anchorLog = LogEntry(album: anchorAlbum, rating: 4.5, tags: ["lush"], sentimentScore: 0.8)
        let activeRecommendation = Recommendation(album: activeAlbum, score: 0.8, confidence: 0.8, explanationText: "Already active.")

        modelContext.insert(anchorAlbum)
        modelContext.insert(activeAlbum)
        modelContext.insert(anchorLog)
        modelContext.insert(activeRecommendation)
        try modelContext.save()

        let returned = try await LocalRecommendationService().currentOrGenerateRecommendation(in: modelContext)
        let recommendations = try modelContext.fetch(FetchDescriptor<Recommendation>())

        #expect(returned.id == activeRecommendation.id)
        #expect(recommendations.count == 1)
    }

    @MainActor
    @Test func recommendationFeedbackPersistsAndMovesRecommendationAwayFromActive() throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let album = Album(title: "Pick", artistName: "Artist")
        let recommendation = Recommendation(album: album, score: 0.8, confidence: 0.8, explanationText: "Pick.")

        modelContext.insert(album)
        modelContext.insert(recommendation)
        try modelContext.save()

        try LocalRecommendationService().submitFeedback(.savedForLater, for: recommendation, in: modelContext)

        let feedback = try modelContext.fetch(FetchDescriptor<RecommendationFeedback>())

        #expect(recommendation.status == RecommendationStatus.saved.rawValue)
        #expect(feedback.count == 1)
        #expect(feedback[0].feedbackType == RecommendationFeedbackType.savedForLater.rawValue)
    }

    @MainActor
    @Test func dismissedRecommendationsAreSkippedUntilNoOtherCandidatesRemain() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let dismissedCandidate = Album(appleMusicID: "mock.a.dismissed", title: "Dismissed Pick", artistName: "Artist A", genreName: "Art Pop")
        let anchorAlbum = Album(title: "Anchor", artistName: "Anchor Artist", genreName: "Art Pop")
        let anchorLog = LogEntry(album: anchorAlbum, rating: 4.5, tags: ["art"], sentimentScore: 0.8)
        let dismissedRecommendation = Recommendation(
            album: dismissedCandidate,
            score: 0.9,
            confidence: 0.9,
            status: RecommendationStatus.dismissed.rawValue,
            explanationText: "Dismissed."
        )
        let service = LocalRecommendationService(
            catalogAlbums: [
                AlbumSearchResult(id: "mock.a.dismissed", title: "Dismissed Pick", artistName: "Artist A", releaseYear: nil, genreName: "Art Pop"),
                AlbumSearchResult(id: "mock.b.available", title: "Available Pick", artistName: "Artist B", releaseYear: nil, genreName: "Art Pop")
            ]
        )

        modelContext.insert(dismissedCandidate)
        modelContext.insert(anchorAlbum)
        modelContext.insert(anchorLog)
        modelContext.insert(dismissedRecommendation)
        try modelContext.save()

        let recommendation = try await service.currentOrGenerateRecommendation(in: modelContext)

        #expect(recommendation.album?.appleMusicID == "mock.b.available")
    }

    @MainActor
    @Test func dismissedOnlyRecommendationPoolReturnsNoCandidates() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let dismissedCandidate = Album(appleMusicID: "mock.a.dismissed", title: "Dismissed Pick", artistName: "Artist A", genreName: "Art Pop")
        let anchorAlbum = Album(title: "Anchor", artistName: "Anchor Artist", genreName: "Art Pop")
        let anchorLog = LogEntry(album: anchorAlbum, rating: 4.5, tags: ["art"], sentimentScore: 0.8)
        let dismissedRecommendation = Recommendation(
            album: dismissedCandidate,
            score: 0.9,
            confidence: 0.9,
            status: RecommendationStatus.dismissed.rawValue,
            explanationText: "Dismissed."
        )
        let service = LocalRecommendationService(
            catalogAlbums: [
                AlbumSearchResult(id: "mock.a.dismissed", title: "Dismissed Pick", artistName: "Artist A", releaseYear: nil, genreName: "Art Pop")
            ]
        )

        modelContext.insert(dismissedCandidate)
        modelContext.insert(anchorAlbum)
        modelContext.insert(anchorLog)
        modelContext.insert(dismissedRecommendation)
        try modelContext.save()

        do {
            _ = try await service.currentOrGenerateRecommendation(in: modelContext)
            Issue.record("Dismissed albums should not be immediately recycled.")
        } catch let error as LocalRecommendationError {
            #expect(error == .noCandidates)
        }
    }

    @MainActor
    @Test func receiptSnapshotSurvivesSourceLogDeletion() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let album = Album(appleMusicID: "mock.frank-ocean.blonde", title: "Blonde", artistName: "Frank Ocean", genreName: "Alternative R&B")
        let log = LogEntry(album: album, rating: 5.0, tags: ["vocals"], sentimentScore: 0.8)

        modelContext.insert(album)
        modelContext.insert(log)
        try modelContext.save()

        _ = try await LocalRecommendationService().currentOrGenerateRecommendation(in: modelContext)
        modelContext.delete(log)
        try modelContext.save()

        let receipts = try modelContext.fetch(FetchDescriptor<RecommendationReceipt>())

        #expect(receipts.first?.sourceAlbumTitle == "Blonde")
        #expect(receipts.first?.sourceArtistName == "Frank Ocean")
        #expect(receipts.first?.snippet.contains("Blonde") == true)
    }

    @Test func soundPrintOutputValidatorRejectsEachBannedPhrase() {
        for phrase in SoundPrintOutputValidator.bannedPhrases {
            let text = "You seem drawn to \(phrase) whenever the mood strikes. This is the second sentence."
            let outcome = SoundPrintOutputValidator.validatePersona(
                text,
                context: .init(concreteSignals: ["mood"])
            )

            #expect(!outcome.isValid, "Expected banned phrase to be rejected: \(phrase)")
        }
    }

    @Test func soundPrintOutputValidatorAcceptsCleanTwoSentencePersona() {
        let text = "You tend to trust albums with a clear emotional temperature. When the songs feel padded, your patience drops quickly."
        let outcome = SoundPrintOutputValidator.validatePersona(
            text,
            context: .init(concreteSignals: ["emotional temperature", "padded"])
        )

        #expect(outcome.isValid)
    }

    @Test func soundPrintOutputValidatorRejectsOverLongPersona() {
        let longSentence = Array(repeating: "word", count: 60).joined(separator: " ")
        let text = "\(longSentence). Second sentence here."
        let outcome = SoundPrintOutputValidator.validatePersona(
            text,
            context: .init(concreteSignals: ["word"])
        )

        #expect(!outcome.isValid)
    }

    @Test func soundPrintOutputValidatorAcceptsAnySentenceCountUnderWordLimit() {
        let oneSentence = SoundPrintOutputValidator.validatePersona(
            "You tend to reward records with a clear emotional temperature and real replay value throughout.",
            context: .init(concreteSignals: ["emotional temperature"])
        )
        let threeSentences = SoundPrintOutputValidator.validatePersona(
            "You tend to reward emotional temperature. You lose patience with filler. Replay value matters most.",
            context: .init(concreteSignals: ["emotional temperature"])
        )

        #expect(oneSentence.isValid)
        #expect(threeSentences.isValid)
    }

    @Test func soundPrintOutputValidatorRejectsYouAreOpener() {
        let outcome = SoundPrintOutputValidator.validatePersona(
            "You are an eclectic listener who rewards emotional temperature. Filler drops your patience fast.",
            context: .init(concreteSignals: ["emotional temperature"])
        )

        #expect(!outcome.isValid)
    }

    @Test func soundPrintOutputValidatorRejectsEmptyOutput() {
        let outcome = SoundPrintOutputValidator.validatePersona(
            "   ",
            context: .init(concreteSignals: ["emotional temperature"])
        )

        #expect(!outcome.isValid)
    }

    @Test func soundPrintOutputValidatorRejectsGenericFillerWithNoConcreteSignal() {
        let outcome = SoundPrintOutputValidator.validatePersona(
            "Your logs point toward records with real staying power. The pattern so far is fairly consistent overall.",
            context: .init(concreteSignals: ["emotional temperature", "Blonde", "Frank Ocean"])
        )

        #expect(!outcome.isValid)
    }

    @Test func soundPrintOutputValidatorRejectsOverconfidenceForLowLogCount() {
        let outcome = SoundPrintOutputValidator.validatePersona(
            "You are never satisfied unless emotional temperature runs high. Filler always drops your patience fast.",
            context: .init(concreteSignals: ["emotional temperature"], logCount: 3)
        )

        #expect(!outcome.isValid)
    }

    @Test func soundPrintPersonaToneDecodesRawValuesAndDefaultsToBalanced() {
        // Typed as String? so overload resolution picks the custom init(rawValue: String?)
        // rather than the enum's synthesized init?(rawValue: String).
        func decode(_ rawValue: String?) -> SoundPrintPersonaTone {
            SoundPrintPersonaTone(rawValue: rawValue)
        }

        #expect(decode(nil) == .balanced)
        #expect(decode("not-a-tone") == .balanced)
        #expect(decode("analyst") == .analyst)
        #expect(decode("wrapped") == .wrapped)

        for tone in SoundPrintPersonaTone.allCases {
            #expect(!tone.userFacingTitle.isEmpty)
            #expect(!tone.userFacingDescription.isEmpty)
        }
    }

    @Test func soundPrintOutputValidatorBannedPhrasesAreToneAware() {
        let vibesText = "You keep chasing big Energy Bias vibes. Filler tracks never make the cut."

        let underWrapped = SoundPrintOutputValidator.validatePersona(
            vibesText,
            context: .init(concreteSignals: ["Energy Bias"], tone: .wrapped)
        )
        let underAnalyst = SoundPrintOutputValidator.validatePersona(
            vibesText,
            context: .init(concreteSignals: ["Energy Bias"], tone: .analyst)
        )
        let underBalanced = SoundPrintOutputValidator.validatePersona(
            vibesText,
            context: .init(concreteSignals: ["Energy Bias"], tone: .balanced)
        )

        #expect(underWrapped.isValid)
        #expect(!underAnalyst.isValid)
        #expect(!underBalanced.isValid)

        // Core filler phrases stay banned in every tone, including Wrapped.
        let eclecticText = "You have eclectic taste around Energy Bias. Filler tracks never make the cut."
        let eclecticUnderWrapped = SoundPrintOutputValidator.validatePersona(
            eclecticText,
            context: .init(concreteSignals: ["Energy Bias"], tone: .wrapped)
        )
        #expect(!eclecticUnderWrapped.isValid)
    }

    @Test func soundPrintOutputValidatorAnalystToneEnforcesOverconfidenceRegardlessOfLogCount() {
        let text = "You never settle unless Energy Bias runs high. Filler always drops your patience fast."

        let underAnalystHighLogCount = SoundPrintOutputValidator.validatePersona(
            text,
            context: .init(concreteSignals: ["Energy Bias"], logCount: 50, tone: .analyst)
        )
        let underBalancedHighLogCount = SoundPrintOutputValidator.validatePersona(
            text,
            context: .init(concreteSignals: ["Energy Bias"], logCount: 50, tone: .balanced)
        )

        #expect(!underAnalystHighLogCount.isValid)
        #expect(underBalancedHighLogCount.isValid)
    }

    @Test func soundPrintOutputValidatorRejectsCriticStyleMetaCommentary() {
        // The exact text observed leaking from a misused critic-rewrite field in production.
        let leakedCritique = "This persona conflates genre preferences with unsupported claims about skip-free listening and vague lyrical praise. Energy Bias should reflect concrete production choices, not emotional claims. Avoid generic language like 'futurist' or 'type of country music.'"

        for tone in SoundPrintPersonaTone.allCases {
            let outcome = SoundPrintOutputValidator.validatePersona(
                leakedCritique,
                context: .init(concreteSignals: ["Energy Bias"], tone: tone)
            )
            #expect(!outcome.isValid, "Expected critique leakage to be rejected under \(tone)")
        }

        let thirdPerson = SoundPrintOutputValidator.validatePersona(
            "The user rewards Energy Bias and loses patience with filler tracks quickly.",
            context: .init(concreteSignals: ["Energy Bias"])
        )
        #expect(!thirdPerson.isValid)

        let normalPersona = SoundPrintOutputValidator.validatePersona(
            "You reward Energy Bias above almost everything else. Filler tracks lose your patience fast.",
            context: .init(concreteSignals: ["Energy Bias"])
        )
        #expect(normalPersona.isValid)
    }

    @Test func soundPrintOutputValidatorRejectsVagueUnnamedAlbumReference() {
        let vagueThis = SoundPrintOutputValidator.validatePersona(
            "You reward Energy Bias most of the time, but this album didn't land the way your other picks do.",
            context: .init(concreteSignals: ["Energy Bias"])
        )
        let vagueThat = SoundPrintOutputValidator.validatePersona(
            "You reward Energy Bias most of the time, but that album didn't land the way your other picks do.",
            context: .init(concreteSignals: ["Energy Bias"])
        )
        let named = SoundPrintOutputValidator.validatePersona(
            "You reward Energy Bias most of the time, but Blonde didn't land the way your other picks do.",
            context: .init(concreteSignals: ["Energy Bias", "Blonde"])
        )

        #expect(!vagueThis.isValid)
        #expect(!vagueThat.isValid)
        #expect(named.isValid)
    }

    @Test func mockPersonaTemplatesRespectTone() async throws {
        let provider = MockSoundPrintProvider()

        var textsByTone: [SoundPrintPersonaTone: String] = [:]
        for tone in SoundPrintPersonaTone.allCases {
            let result = try await provider.generatePersona(input: personaInput(tone: tone))
            let concreteSignals = FoundationModelsSoundPrintValidator.concreteSignals(from: personaInput(tone: tone))
            let outcome = SoundPrintOutputValidator.validatePersona(
                result.text,
                context: .init(concreteSignals: concreteSignals, tone: tone)
            )

            #expect(outcome.isValid, "Expected \(tone) persona to validate: \(String(describing: outcome))")
            textsByTone[tone] = result.text
        }

        #expect(Set(textsByTone.values).count == SoundPrintPersonaTone.allCases.count)
    }

    @Test func mockCompactSummaryTemplatesRespectTone() {
        let dimensions = [
            TasteDimension(name: "energy", label: "Energy Bias", weight: 0.9, confidence: 0.8, summary: "Leans energetic.")
        ]

        var headlinesByTone: [SoundPrintPersonaTone: String] = [:]
        for tone in SoundPrintPersonaTone.allCases {
            let result = MockSoundPrintProvider.generateCompactSummary(
                input: CompactSummaryInput(dimensions: dimensions, avoidanceSignals: [], tone: tone)
            )
            let outcome = SoundPrintOutputValidator.validateCompactSummary(
                headline: result.headline,
                summary: result.summary,
                bullets: result.bullets,
                tone: tone
            )

            #expect(outcome.isValid, "Expected \(tone) compact summary to validate: \(String(describing: outcome))")
            headlinesByTone[tone] = result.headline
        }

        #expect(Set(headlinesByTone.values).count == SoundPrintPersonaTone.allCases.count)
    }

    @Test func soundPrintOutputValidatorCompactSummaryRespectsLimits() {
        let valid = SoundPrintOutputValidator.validateCompactSummary(
            headline: "Emotional Temperature Over Everything",
            summary: "You tend to reward emotional temperature and lose patience with filler-heavy tracklists.",
            bullets: ["Rewards emotional temperature", "Loses patience with filler", "High replay value overall"]
        )
        let tooManyBullets = SoundPrintOutputValidator.validateCompactSummary(
            headline: "Emotional Temperature Over Everything",
            summary: "You tend to reward emotional temperature and lose patience with filler-heavy tracklists.",
            bullets: ["One", "Two", "Three", "Four"]
        )
        let bannedHeadline = SoundPrintOutputValidator.validateCompactSummary(
            headline: "Your Eclectic Sonic Journey",
            summary: "You tend to reward emotional temperature and lose patience with filler-heavy tracklists.",
            bullets: ["Rewards emotional temperature", "Loses patience with filler", "High replay value overall"]
        )

        #expect(valid.isValid)
        #expect(!tooManyBullets.isValid)
        #expect(!bannedHeadline.isValid)
    }

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
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
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func personaInput(tone: SoundPrintPersonaTone = .balanced) -> PersonaInput {
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
            averageRating: 4.4,
            tone: tone
        )
    }

    private func tasteExtractionInput(sentimentScore: Double?) -> TasteExtractionInput {
        TasteExtractionInput(
            logID: UUID(),
            albumTitle: "Blonde",
            artistName: "Frank Ocean",
            genreName: "Alternative R&B",
            releaseYear: 2016,
            rating: 4.5,
            reviewText: "Sparse intimate vocals with replay value.",
            tags: ["vocals"],
            sentimentScore: sentimentScore
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

private enum ThrowingSoundPrintOperation {
    case sentiment
    case tasteExtraction
    case persona
    case compactSummary
}

private enum ThrowingSoundPrintError: Error {
    case failed
}

private enum ThrowingAlbumCatalogError: Error {
    case failed
}

private enum ThrowingAlbumPreviewError: Error {
    case failed
}

private enum ThrowingJournalAssistError: Error {
    case failed
}

private enum ThrowingAppleMusicRecommendationError: Error {
    case failed
}

private struct ThrowingAlbumCatalogService: AlbumCatalogServiceProtocol {
    func searchAlbums(query: String) async throws -> [AlbumSearchResult] {
        throw ThrowingAlbumCatalogError.failed
    }

    func albumDetails(id: String) async throws -> AlbumSearchResult? {
        throw ThrowingAlbumCatalogError.failed
    }
}

private struct ThrowingAlbumPreviewService: AlbumPreviewServiceProtocol {
    func preview(for lookup: AlbumPreviewLookup) async throws -> AlbumPreview? {
        throw ThrowingAlbumPreviewError.failed
    }
}

private struct EmptyAlbumPreviewService: AlbumPreviewServiceProtocol {
    func preview(for lookup: AlbumPreviewLookup) async throws -> AlbumPreview? {
        nil
    }
}

private struct ThrowingJournalAssistService: JournalAssistServiceProtocol {
    let reflectionPrompts: [JournalAssistPrompt] = JournalAssistPrompt.defaults

    func draftReview(for input: JournalAssistInput) async throws -> JournalAssistDraftResult {
        throw ThrowingJournalAssistError.failed
    }

    func suggestedTags(for input: JournalAssistInput) async throws -> [String] {
        throw ThrowingJournalAssistError.failed
    }
}

private struct CancellingJournalAssistService: JournalAssistServiceProtocol {
    let reflectionPrompts: [JournalAssistPrompt] = JournalAssistPrompt.defaults

    func draftReview(for input: JournalAssistInput) async throws -> JournalAssistDraftResult {
        throw CancellationError()
    }

    func suggestedTags(for input: JournalAssistInput) async throws -> [String] {
        throw CancellationError()
    }
}

private final class RecordingAlbumCatalogService: AlbumCatalogServiceProtocol {
    private let resultsByQuery: [String: [AlbumSearchResult]]
    private let error: Error?
    private(set) var queries: [String] = []

    init(resultsByQuery: [String: [AlbumSearchResult]] = [:], error: Error? = nil) {
        self.resultsByQuery = resultsByQuery
        self.error = error
    }

    func searchAlbums(query: String) async throws -> [AlbumSearchResult] {
        queries.append(query)

        if let error {
            throw error
        }

        return resultsByQuery[query] ?? []
    }

    func albumDetails(id: String) async throws -> AlbumSearchResult? {
        if let error {
            throw error
        }

        return resultsByQuery.values.flatMap { $0 }.first { $0.catalogID == id }
    }
}

private struct RecordingAppleMusicRecommendationService: AppleMusicRecommendationServiceProtocol {
    let personalRecommendations: [AlbumSearchResult]
    let recentlyPlayedAlbums: [AlbumSearchResult]
    let libraryCatalogIDs: Set<String>

    init(
        personalRecommendations: [AlbumSearchResult],
        recentlyPlayedAlbums: [AlbumSearchResult] = [],
        libraryCatalogIDs: Set<String> = []
    ) {
        self.personalRecommendations = personalRecommendations
        self.recentlyPlayedAlbums = recentlyPlayedAlbums
        self.libraryCatalogIDs = libraryCatalogIDs
    }

    func recommendedAlbums(limit: Int) async throws -> [AlbumSearchResult] {
        Array(personalRecommendations.prefix(limit))
    }

    func recentlyPlayedAlbums(limit: Int) async throws -> [AlbumSearchResult] {
        Array(recentlyPlayedAlbums.prefix(limit))
    }

    func containsInLibrary(_ album: AlbumSearchResult) async throws -> Bool {
        libraryCatalogIDs.contains(album.catalogID)
    }
}

private struct ThrowingAppleMusicRecommendationService: AppleMusicRecommendationServiceProtocol {
    func recommendedAlbums(limit: Int) async throws -> [AlbumSearchResult] {
        throw ThrowingAppleMusicRecommendationError.failed
    }

    func recentlyPlayedAlbums(limit: Int) async throws -> [AlbumSearchResult] {
        throw ThrowingAppleMusicRecommendationError.failed
    }

    func containsInLibrary(_ album: AlbumSearchResult) async throws -> Bool {
        throw ThrowingAppleMusicRecommendationError.failed
    }
}

private struct ThrowingSoundPrintProvider: SoundPrintProvider {
    let failingOperation: ThrowingSoundPrintOperation

    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult {
        if failingOperation == .sentiment {
            throw ThrowingSoundPrintError.failed
        }

        return try await MockSoundPrintProvider().analyzeSentiment(input: input)
    }

    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult {
        if failingOperation == .tasteExtraction {
            throw ThrowingSoundPrintError.failed
        }

        return try await MockSoundPrintProvider().extractTasteSignals(input: input)
    }

    func generatePersona(input: PersonaInput) async throws -> PersonaResult {
        if failingOperation == .persona {
            throw ThrowingSoundPrintError.failed
        }

        return try await MockSoundPrintProvider().generatePersona(input: input)
    }

    func generateCompactSummary(input: CompactSummaryInput) async throws -> CompactSummaryResult {
        if failingOperation == .compactSummary {
            throw ThrowingSoundPrintError.failed
        }

        return try await MockSoundPrintProvider().generateCompactSummary(input: input)
    }
}

private struct SuccessfulSoundPrintProvider: SoundPrintProvider {
    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult {
        SentimentResult(score: 0.42, confidence: 0.91)
    }

    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult {
        TasteExtractionResult(
            signals: [
                TasteSignal(
                    dimensionName: "energy",
                    label: "Energy",
                    summary: "Primary energy signal.",
                    weight: 0.7,
                    confidence: 0.8,
                    evidenceSnippet: "Primary evidence.",
                    isPositiveEvidence: true
                )
            ],
            avoidanceSignals: [
                AvoidanceSignal(
                    signalName: "skipHeavyAlbums",
                    label: "Skip-Heavy Albums",
                    summary: "Primary avoidance signal.",
                    strength: 0.6,
                    confidence: 0.7,
                    evidenceSnippet: "Primary avoidance evidence."
                )
            ]
        )
    }

    func generatePersona(input: PersonaInput) async throws -> PersonaResult {
        PersonaResult(
            text: "You tend to reward vocal focus. Blonde by Frank Ocean is the clearest example so far.",
            generationSource: .localFallback
        )
    }

    func generateCompactSummary(input: CompactSummaryInput) async throws -> CompactSummaryResult {
        CompactSummaryResult(
            headline: "Vocal Focus Leads",
            summary: "You tend to reward vocal focus and lose patience with filler.",
            bullets: ["Rewards vocal focus", "Loses patience with filler", "High replay value"]
        )
    }
}

private struct SourceTrackingSoundPrintProvider: SoundPrintProvider {
    let source: SoundPrintGenerationSource
    var failsPersonaGeneration = false

    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult {
        try await MockSoundPrintProvider().analyzeSentiment(input: input)
    }

    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult {
        try await MockSoundPrintProvider().extractTasteSignals(input: input)
    }

    func generatePersona(input: PersonaInput) async throws -> PersonaResult {
        if failsPersonaGeneration {
            throw ThrowingSoundPrintError.failed
        }

        return PersonaResult(
            text: "You tend to reward vocal focus. Blonde by Frank Ocean is the clearest example so far.",
            generationSource: source
        )
    }

    func generateCompactSummary(input: CompactSummaryInput) async throws -> CompactSummaryResult {
        try await MockSoundPrintProvider().generateCompactSummary(input: input)
    }
}

private struct CancellingSoundPrintProvider: SoundPrintProvider {
    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult {
        throw CancellationError()
    }

    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult {
        throw CancellationError()
    }

    func generatePersona(input: PersonaInput) async throws -> PersonaResult {
        throw CancellationError()
    }

    func generateCompactSummary(input: CompactSummaryInput) async throws -> CompactSummaryResult {
        throw CancellationError()
    }
}

private enum ThrowingAlbumTrackServiceError: Error {
    case failed
}

private struct ThrowingAlbumTrackService: AlbumTrackServiceProtocol {
    func tracks(for album: Album, in modelContext: ModelContext) async throws -> [AlbumTrackCandidate] {
        throw ThrowingAlbumTrackServiceError.failed
    }
}

private struct SuccessfulAlbumTrackService: AlbumTrackServiceProtocol {
    let tracks: [AlbumTrackCandidate]

    func tracks(for album: Album, in modelContext: ModelContext) async throws -> [AlbumTrackCandidate] {
        tracks
    }
}

private extension AlbumTrackCandidate {
    static func sosTrack(title: String, trackNumber: Int) -> AlbumTrackCandidate {
        AlbumTrackCandidate(
            albumAppleMusicID: "mock.sza.sos",
            appleMusicTrackID: "mock.sza.sos.\(trackNumber)",
            title: title,
            artistName: "SZA",
            trackNumber: trackNumber,
            discNumber: 1,
            durationMilliseconds: 180_000,
            previewURL: nil,
            returnedOrder: trackNumber
        )
    }
}
