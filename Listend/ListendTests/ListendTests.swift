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
                payloadSignals: [
                    FoundationModelsTasteSignalPayload(
                        dimensionName: "inventedDimension",
                        summary: "Invented.",
                        weight: 0.8,
                        confidence: 0.8,
                        evidenceSnippet: "Invented evidence."
                    )
                ],
                input: input
            )
            Issue.record("Unknown dimensions should be rejected.")
        } catch let error as FoundationModelsSoundPrintProviderError {
            #expect(error == .validationFailed)
        }
    }

    @Test func foundationModelsTasteValidationCreatesNoPositiveEvidenceFromNegativeSentiment() throws {
        let result = try FoundationModelsSoundPrintValidator.validatedTasteExtraction(
            payloadSignals: [
                FoundationModelsTasteSignalPayload(
                    dimensionName: "energy",
                    summary: "Energetic.",
                    weight: 0.8,
                    confidence: 0.8,
                    evidenceSnippet: "Intense momentum."
                )
            ],
            input: tasteExtractionInput(sentimentScore: -0.4)
        )

        #expect(result.signals.isEmpty)
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

    @MainActor
    private func makeInMemoryContainer() throws -> ModelContainer {
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
            ]
        )
    }

    func generatePersona(input: PersonaInput) async throws -> PersonaResult {
        PersonaResult(text: "Across five logs, Blonde by Frank Ocean anchors a vocal focus profile with enough concrete detail to pass the existing quality guard.")
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
}
