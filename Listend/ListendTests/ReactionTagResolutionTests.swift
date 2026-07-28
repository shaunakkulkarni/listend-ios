//
//  ReactionTagResolutionTests.swift
//  ListendTests
//

import Testing
@testable import Listend

nonisolated struct ReactionTagResolutionTests {
    private let catalog = TaxonomyCatalogLoader.shared

    @Test func resolverOrderStaysLocalBeforeOptionalSemanticLookup() async throws {
        let semanticResolver = RecordingReactionTagResolver(
            resolution: .custom(displayValue: "graduation summer")
        )

        let canonical = await resolve(" HYPE ", using: semanticResolver)
        guard case .canonical(let canonicalTag) = canonical else {
            Issue.record("Expected canonical formatting match.")
            return
        }
        #expect(canonicalTag.id == "mood.hype")

        let alias = await resolve("turnt", using: semanticResolver)
        guard case .canonical(let aliasTag) = alias else {
            Issue.record("Expected exact alias match.")
            return
        }
        #expect(aliasTag.id == "mood.hype")

        let ambiguous = await resolve("icy", using: semanticResolver)
        guard case .choices(let ambiguousChoices) = ambiguous else {
            Issue.record("Expected explicit ambiguous alias choices.")
            return
        }
        #expect(ambiguousChoices.map(\.id) == [
            "sonic.cold-production",
            "mood.confident",
            "mood.menacing"
        ])

        let typo = await resolve("hyppe", using: semanticResolver)
        guard case .canonical(let typoTag) = typo else {
            Issue.record("Expected safe local typo match.")
            return
        }
        #expect(typoTag.id == "mood.hype")
        #expect(await semanticResolver.recordedInputs().isEmpty)

        let custom = await resolve("graduation summer", using: semanticResolver)
        #expect(custom == .custom(displayValue: "graduation summer"))
        #expect(await semanticResolver.recordedInputs().count == 1)
    }

    @Test func parserAcceptsDocumentedShapesAndRejectsUntrustedOutput() throws {
        let hype = try requiredReaction("mood.hype")
        let cold = try requiredReaction("sonic.cold-production")
        let confident = try requiredReaction("mood.confident")
        let menacing = try requiredReaction("mood.menacing")
        let bars = try requiredReaction("craft.bars")
        let input = ReactionTagResolutionInput(
            phrase: "icy",
            candidates: [hype, cold, confident, menacing]
        )
        let parser = ReactionTagResolutionParser(catalog: catalog)

        #expect(try parser.parse(
            "RESULT | MATCH\nMATCH | mood.hype",
            input: input
        ) == .canonical(hype))
        #expect(try parser.parse(
            """
            RESULT | AMBIGUOUS
            MATCH | sonic.cold-production
            ALTERNATIVE | mood.confident
            ALTERNATIVE | mood.menacing
            """,
            input: input
        ) == .choices([cold, confident, menacing]))
        #expect(try parser.parse(
            "RESULT | NONE",
            input: input
        ) == .custom(displayValue: "icy"))

        let rejectedOutputs = [
            "",
            "RESULT | MATCH\nMATCH | mood.hype\nCOMMENT | closest",
            "RESULT | MATCH\nMATCH | mood.not-real",
            "RESULT | MATCH\nMATCH | \(bars.id)",
            """
            RESULT | AMBIGUOUS
            MATCH | sonic.cold-production
            ALTERNATIVE | sonic.cold-production
            """,
            """
            RESULT | AMBIGUOUS
            MATCH | mood.hype
            ALTERNATIVE | sonic.cold-production
            ALTERNATIVE | mood.confident
            ALTERNATIVE | mood.menacing
            """,
            "MATCH | mood.hype",
            "RESULT MATCH mood.hype"
        ]

        for output in rejectedOutputs {
            #expect(throws: ReactionTagResolutionError.self) {
                try parser.parse(output, input: input)
            }
        }
    }

    @Test func resolutionInputBoundsAndDeduplicatesLocalCandidates() throws {
        let selected = try requiredReaction("mood.hype")
        let input = ReactionTagResolutionInput(
            phrase: "graduation summer",
            rating: 4.5,
            selectedCanonicalIDs: [selected.id],
            reviewExcerpt: String(repeating: "sound ", count: 100),
            candidates: catalog.reactions.tags + catalog.reactions.tags
        )

        #expect(input.candidates.count == ReactionTagResolutionInput.maximumCandidateCount)
        #expect(Set(input.candidates.map(\.id)).count == input.candidates.count)
        #expect(!input.candidates.contains(where: { $0.id == selected.id }))
        #expect(input.candidates.count < catalog.reactions.tags.count)
        #expect(input.reviewExcerpt.count == ReactionTagResolutionInput.maximumReviewExcerptLength)
    }

    @Test func fallbackAndCancellationAlwaysLeaveCustomSavingAvailable() async throws {
        let hype = try requiredReaction("mood.hype")
        let input = ReactionTagResolutionInput(
            phrase: "graduation summer",
            candidates: [hype]
        )
        let fallback = FallbackReactionTagResolver(
            primary: ThrowingReactionTagResolver(error: .failure),
            fallback: MockReactionTagResolver(resolution: .canonical(hype))
        )
        #expect(try await fallback.resolve(input) == .canonical(hype))

        let cancellingFallback = FallbackReactionTagResolver(
            primary: ThrowingReactionTagResolver(error: .cancellation),
            fallback: MockReactionTagResolver(resolution: .canonical(hype))
        )
        do {
            _ = try await cancellingFallback.resolve(input)
            Issue.record("Expected cancellation to propagate from the provider.")
        } catch is CancellationError {
            // The picker state converts cancellation to the user's custom phrase.
        }

        let result = await resolve(
            "graduation summer",
            using: ThrowingReactionTagResolver(error: .cancellation)
        )
        #expect(result == .custom(displayValue: "graduation summer"))
    }

    @Test func pickerConfirmationKeepsCanonicalOptionsAndOriginalPhraseExplicit() throws {
        let hype = try requiredReaction("mood.hype")
        let confident = try requiredReaction("mood.confident")
        let menacing = try requiredReaction("mood.menacing")

        let match = ReactionTagResolutionState.confirmation(
            for: .canonical(hype),
            originalPhrase: "turnt"
        )
        #expect(match.canonicalOptions == [hype])
        #expect(match.customDisplayValue == "turnt")

        let choices = ReactionTagResolutionState.confirmation(
            for: .choices([hype, confident, menacing, hype]),
            originalPhrase: "main character energy"
        )
        #expect(choices.canonicalOptions == [hype, confident, menacing])
        #expect(choices.customDisplayValue == "main character energy")

        let custom = ReactionTagResolutionState.confirmation(
            for: .custom(displayValue: "graduation summer"),
            originalPhrase: "graduation summer"
        )
        #expect(custom.canonicalOptions.isEmpty)
        #expect(custom.customDisplayValue == "graduation summer")
    }

    private func resolve(
        _ phrase: String,
        using semanticResolver: any ReactionTagResolving
    ) async -> ReactionTagResolution {
        await ReactionTagResolutionState.resolve(
            phrase: phrase,
            rating: 4.5,
            selectedCanonicalIDs: [],
            reviewExcerpt: "",
            catalog: catalog,
            semanticResolver: semanticResolver
        )
    }

    private func requiredReaction(_ id: String) throws -> ReactionTagDefinition {
        try #require(catalog.reaction(id: id))
    }
}

private actor RecordingReactionTagResolver: ReactionTagResolving {
    private let resolution: ReactionTagResolution
    private var inputs: [ReactionTagResolutionInput] = []

    init(resolution: ReactionTagResolution) {
        self.resolution = resolution
    }

    func resolve(_ input: ReactionTagResolutionInput) async throws -> ReactionTagResolution {
        inputs.append(input)
        return resolution
    }

    func recordedInputs() -> [ReactionTagResolutionInput] {
        inputs
    }
}

private enum ReactionTagResolverTestError: Error, Sendable {
    case failure
    case cancellation
}

private struct ThrowingReactionTagResolver: ReactionTagResolving {
    let error: ReactionTagResolverTestError

    func resolve(_ input: ReactionTagResolutionInput) async throws -> ReactionTagResolution {
        switch error {
        case .failure:
            throw ReactionTagResolverTestError.failure
        case .cancellation:
            throw CancellationError()
        }
    }
}
