//
//  ReactionIntegrationTests.swift
//  ListendTests
//

import Foundation
import SwiftData
import Testing
@testable import Listend

@MainActor
struct ReactionIntegrationTests {
    @Test func canonicalPositiveMappingsUseTaxonomyAndIgnoreDisplayOnlyContext() {
        let result = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(
                tags: ["hype", "bars", "cold production", "gym", "writing"]
            )
        )
        let contextOnly = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(tags: ["writing"])
        )
        let dimensions = result.signals.map(\.dimensionName)

        #expect(Set(dimensions) == [
            "mood",
            "energy",
            "lyricFocus",
            "productionStyle",
            "texturePreference"
        ])
        #expect(dimensions.count == Set(dimensions).count)
        #expect(result.avoidanceSignals.isEmpty)
        #expect(contextOnly.signals.isEmpty)
        #expect(contextOnly.avoidanceSignals.isEmpty)
    }

    @Test func canonicalCritiquesProduceOnlyDeclaredAvoidanceSignals() {
        let result = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(
                rating: 3.0,
                tags: ["bloated", "weak writing"],
                sentimentScore: 0.1
            )
        )

        #expect(Set(result.avoidanceSignals.map(\.signalName)) == [
            "fillerSensitivity",
            "weakWriting"
        ])
        #expect(!result.avoidanceSignals.contains { $0.signalName == "skipHeavyAlbums" })
    }

    @Test func canonicalAndLegacyEvidenceCoexistWithoutDuplicateDimensions() throws {
        let review = "Lush and layered production carried the whole album."
        let result = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(
                reviewText: review,
                tags: ["layered", "energetic", "repeat"]
            )
        )
        let dimensions = result.signals.map(\.dimensionName)
        let arrangement = try #require(
            result.signals.first { $0.dimensionName == "instrumentalRichness" }
        )

        #expect(dimensions.count == Set(dimensions).count)
        #expect(Set(dimensions).isSuperset(of: [
            "instrumentalRichness",
            "texturePreference",
            "energy",
            "replayability"
        ]))
        #expect(arrangement.evidenceSnippet == review)
    }

    @Test func explicitCanonicalEvidenceOutweighsLooseKeywordButNotDetailedMoment() throws {
        let loose = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(tags: ["energetic"])
        )
        let explicit = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(tags: ["hype"])
        )
        let detailed = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(
                reviewText: "The energetic pacing held my attention.",
                standoutMoment: "The energetic final stretch."
            )
        )

        let looseEnergy = try #require(loose.signals.first { $0.dimensionName == "energy" })
        let explicitEnergy = try #require(explicit.signals.first { $0.dimensionName == "energy" })
        let detailedEnergy = try #require(detailed.signals.first { $0.dimensionName == "energy" })
        let looseStrength = looseEnergy.weight * looseEnergy.confidence
        let explicitStrength = explicitEnergy.weight * explicitEnergy.confidence
        let detailedStrength = detailedEnergy.weight * detailedEnergy.confidence

        #expect(explicitStrength > looseStrength)
        #expect(detailedStrength > explicitStrength)
    }

    @Test func multipleCanonicalMappingsStrengthenConfidenceWithoutDuplicates() throws {
        let single = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(tags: ["hype"])
        )
        let multiple = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(tags: ["hype", "euphoric"])
        )
        let duplicated = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(tags: ["hype", "hype"])
        )
        let singleEnergy = try #require(single.signals.first { $0.dimensionName == "energy" })
        let multipleEnergySignals = multiple.signals.filter { $0.dimensionName == "energy" }
        let multipleEnergy = try #require(multipleEnergySignals.first)
        let duplicatedEnergy = try #require(
            duplicated.signals.first { $0.dimensionName == "energy" }
        )

        #expect(multipleEnergySignals.count == 1)
        #expect(multipleEnergy.confidence > singleEnergy.confidence)
        #expect(multipleEnergy.confidence <= 0.86)
        #expect(duplicatedEnergy.weight == singleEnergy.weight)
        #expect(duplicatedEnergy.confidence == singleEnergy.confidence)
    }

    @Test func lowRatedPositiveCraftAndHighRatedCritiqueStayScoped() throws {
        let lowRatedCraft = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(
                rating: 2.0,
                tags: ["bars"],
                sentimentScore: 0.1
            )
        )
        let lyricFocus = try #require(
            lowRatedCraft.signals.first { $0.dimensionName == "lyricFocus" }
        )
        let looseLyricKeyword = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(
                rating: 2.0,
                tags: ["lyrics"],
                sentimentScore: 0.1
            )
        )
        let looseLyricFocus = try #require(
            looseLyricKeyword.signals.first { $0.dimensionName == "lyricFocus" }
        )
        let detailedLyricReview = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(
                rating: 2.0,
                reviewText: "The lyrics stayed sharp from start to finish.",
                sentimentScore: 0.1
            )
        )
        let detailedLyricFocus = try #require(
            detailedLyricReview.signals.first { $0.dimensionName == "lyricFocus" }
        )
        let highRatedCritique = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(
                rating: 4.5,
                tags: ["bloated"],
                sentimentScore: 0.8
            )
        )
        let filler = try #require(
            highRatedCritique.avoidanceSignals.first { $0.signalName == "fillerSensitivity" }
        )

        #expect(lyricFocus.weight <= 0.3)
        #expect(lyricFocus.confidence <= 0.35)
        #expect(
            lyricFocus.weight * lyricFocus.confidence
                > looseLyricFocus.weight * looseLyricFocus.confidence
        )
        #expect(
            detailedLyricFocus.weight * detailedLyricFocus.confidence
                > lyricFocus.weight * lyricFocus.confidence
        )
        #expect(filler.strength <= 0.4)
        #expect(filler.confidence <= 0.68)
    }

    @Test func explicitCanonicalAvoidanceOutweighsLooseKeywordButNotDetailedReview() throws {
        let explicit = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(rating: 4.5, tags: ["bloated"])
        )
        let loose = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(rating: 4.5, reviewText: "padded")
        )
        let detailed = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(
                rating: 4.5,
                reviewText: "The album felt padded, too long, and dragged."
            )
        )
        let combined = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(rating: 4.5, tags: ["bloated", "padded"])
        )

        let explicitFiller = try #require(
            explicit.avoidanceSignals.first { $0.signalName == "fillerSensitivity" }
        )
        let looseFiller = try #require(
            loose.avoidanceSignals.first { $0.signalName == "fillerSensitivity" }
        )
        let detailedFiller = try #require(
            detailed.avoidanceSignals.first { $0.signalName == "fillerSensitivity" }
        )
        let combinedFiller = combined.avoidanceSignals.filter {
            $0.signalName == "fillerSensitivity"
        }

        #expect(
            explicitFiller.strength * explicitFiller.confidence
                > looseFiller.strength * looseFiller.confidence
        )
        #expect(
            detailedFiller.strength * detailedFiller.confidence
                > explicitFiller.strength * explicitFiller.confidence
        )
        #expect(combinedFiller.count == 1)
        #expect(combinedFiller[0].confidence > explicitFiller.confidence)
    }

    @Test func legacyCustomTagsReviewsAndStandoutMomentsStillUseKeywordAnalysis() {
        let result = MockSoundPrintProvider.extractTasteSignals(
            input: tasteInput(
                reviewText: "Polished vocals from front to back.",
                tags: ["energetic", "repeat"],
                standoutMoment: "The layered bridge."
            )
        )
        let dimensions = Set(result.signals.map(\.dimensionName))

        #expect(dimensions.isSuperset(of: [
            "productionStyle",
            "vocalFocus",
            "energy",
            "replayability",
            "instrumentalRichness"
        ]))
    }

    @Test func canonicalEvidencePersistsOnceAndUsesExistingTodayPickPath() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let album = Album(
            appleMusicID: "music.reaction.anchor",
            title: "Reaction Anchor",
            artistName: "Anchor Artist",
            genreName: "Art Pop"
        )
        let log = LogEntry(
            album: album,
            rating: 4.5,
            tags: ["hype"],
            sentimentScore: 0.8,
            sentimentConfidence: 0.9
        )
        modelContext.insert(album)
        modelContext.insert(log)
        try modelContext.save()

        try await SoundPrintProfileBuilder().rebuildProfile(in: modelContext, mode: .signalsOnly)

        let evidence = try modelContext.fetch(FetchDescriptor<TasteEvidence>())
            .filter { $0.logEntryID == log.id }
        let energyEvidence = evidence.filter { $0.dimensionName == "energy" }
        let profile = try #require(
            LocalRecommendationService()
                .recommendationAnchorProfiles(from: [log], evidence: evidence)
                .first
        )
        let queries = CatalogRecommendationCandidateProvider.searchQueries(
            anchors: [
                RecommendationAnchorInput(
                    logIDs: [log.id],
                    albumCatalogID: album.appleMusicID,
                    albumTitle: album.title,
                    artistName: album.artistName,
                    genreName: album.genreName,
                    tags: log.tags,
                    strength: profile.strength
                )
            ],
            evidence: evidence.map {
                RecommendationEvidenceInput(
                    logEntryID: $0.logEntryID,
                    dimensionName: $0.dimensionName,
                    strength: $0.strength * $0.confidence,
                    isPositiveEvidence: $0.isPositiveEvidence
                )
            },
            limit: 8
        )

        #expect(energyEvidence.count == 1)
        #expect(profile.positiveEvidenceDimensions.contains("energy"))
        #expect(profile.strengthBreakdown.positiveEvidenceBoost > 0)
        #expect(queries.contains("energy"))
        #expect(!queries.contains("hype"))
    }

    @Test func canonicalAvoidancePersistsOnceAndUsesExistingTodayPickPenaltyPath() async throws {
        let container = try makeInMemoryContainer()
        let modelContext = container.mainContext
        let album = Album(
            appleMusicID: "music.reaction.avoidance",
            title: "Reaction Avoidance",
            artistName: "Avoidance Artist",
            genreName: "Art Pop"
        )
        let log = LogEntry(
            album: album,
            rating: 3.0,
            tags: ["bloated"],
            sentimentScore: 0.0,
            sentimentConfidence: 0.9
        )
        modelContext.insert(album)
        modelContext.insert(log)
        try modelContext.save()

        try await SoundPrintProfileBuilder().rebuildProfile(in: modelContext, mode: .signalsOnly)

        let avoidanceSignals = try modelContext.fetch(
            FetchDescriptor<TasteAvoidanceSignal>()
        )
        let fillerSignals = avoidanceSignals.filter {
            $0.name == "fillerSensitivity"
                && $0.evidenceLogEntryIDs.contains(log.id)
        }
        let profile = try #require(
            LocalRecommendationService()
                .recommendationAnchorProfiles(
                    from: [log],
                    evidence: [],
                    avoidanceSignals: avoidanceSignals
                )
                .first
        )

        #expect(fillerSignals.count == 1)
        #expect(profile.hasAvoidanceEvidence)
        #expect(profile.strengthBreakdown.avoidancePenalty > 0)
    }

    @Test func journalAssistSeparatesCanonicalReactionsFromCustomTags() {
        let state = ReactionSelectionState(
            persistedDisplayValues: ["hype", "graduation summer", "bars"],
            catalog: TaxonomyCatalogLoader.shared
        )

        #expect(state.selectedCanonicalDisplayValues == ["hype", "bars"])
        #expect(state.customDisplayValues == ["graduation summer"])
        #expect(state.persistedDisplayValues == ["hype", "graduation summer", "bars"])
    }

    @Test func journalAssistFallbackUsesSelectedReactionNamesWithoutDroppingDetailedCues() async throws {
        let result = try await MockJournalAssistService().draftReview(
            for: JournalAssistInput(
                albumTitle: "SOS",
                artistName: "SZA",
                rating: 4.5,
                notes: "The hook stayed with me.",
                existingTags: ["graduation summer"],
                selectedReactionDisplayNames: ["hype", "bars"]
            )
        )

        #expect(
            result.draftReview
                == "I rated SOS by SZA 4.5/5. My notes point to The hook stayed with me, graduation summer; the reactions I chose were hype, bars."
        )
    }

    @Test func journalAssistPromptLabelsReactionsAndForbidsInventedSpecifics() {
        let prompt = JournalAssistPromptBuilder.draftPrompt(
            for: JournalAssistInput(
                albumTitle: "SOS",
                artistName: "SZA",
                rating: 4.5,
                selectedReactionDisplayNames: ["hype", "night drive"]
            )
        )

        #expect(prompt.contains("1-2 concise"))
        #expect(prompt.contains("Selected reactions (user-authored evidence): hype, night drive"))
        #expect(prompt.contains("Do not invent lyrics, sounds, production details, track moments, emotions, listening contexts, or reasons"))
    }

    @Test func journalAssistValidatorAllowsSelectedNoSkipsButRejectsUnsupportedHype() throws {
        let input = JournalAssistInput(
            albumTitle: "SOS",
            artistName: "SZA",
            selectedReactionDisplayNames: ["no skips"]
        )

        #expect(
            try JournalAssistValidator.validatedDraft(
                "I came away feeling like this had no skips.",
                input: input
            ) == "I came away feeling like this had no skips."
        )
        #expect(throws: JournalAssistServiceError.validationFailed) {
            _ = try JournalAssistValidator.validatedDraft(
                "This was a flawless masterpiece.",
                input: input
            )
        }
    }

    @Test func journalAssistTagValidationDeduplicatesSelectedReactions() {
        let input = JournalAssistInput(
            albumTitle: "SOS",
            artistName: "SZA",
            selectedReactionDisplayNames: ["hype"]
        )

        #expect(
            JournalAssistValidator.validatedTags(["Hype", "Vocals"], input: input)
                == ["Vocals"]
        )
    }

    @Test func journalAssistFallbackServicePreservesCanonicalEvidence() async throws {
        let service = FallbackJournalAssistService(
            primary: ThrowingReactionJournalAssistService(),
            fallback: MockJournalAssistService()
        )
        let result = try await service.draftReview(
            for: JournalAssistInput(
                albumTitle: "SOS",
                artistName: "SZA",
                rating: 4.5,
                selectedReactionDisplayNames: ["hype"]
            )
        )

        #expect(
            result.draftReview
                == "I rated SOS by SZA 4.5/5. The reactions I chose were hype."
        )
    }

    private func tasteInput(
        rating: Double = 4.5,
        reviewText: String = "",
        tags: [String] = [],
        sentimentScore: Double? = 0.8,
        favoriteTracks: [String] = [],
        skipTracks: [String] = [],
        standoutMoment: String? = nil
    ) -> TasteExtractionInput {
        TasteExtractionInput(
            logID: UUID(),
            albumTitle: "Test Album",
            artistName: "Test Artist",
            genreName: nil,
            releaseYear: nil,
            rating: rating,
            reviewText: reviewText,
            tags: tags,
            sentimentScore: sentimentScore,
            favoriteTracks: favoriteTracks,
            skipTracks: skipTracks,
            standoutMoment: standoutMoment
        )
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = ListendModelSchema.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

private struct ThrowingReactionJournalAssistService: JournalAssistServiceProtocol {
    let reflectionPrompts = JournalAssistPrompt.defaults

    func draftReview(for input: JournalAssistInput) async throws -> JournalAssistDraftResult {
        throw JournalAssistServiceError.unavailable
    }

    func suggestedTags(for input: JournalAssistInput) async throws -> [String] {
        throw JournalAssistServiceError.unavailable
    }
}
