//
//  ReactionPickerStateTests.swift
//  ListendTests
//

import Testing
@testable import Listend

nonisolated struct ReactionPickerStateTests {
    private let catalog = TaxonomyCatalogLoader.shared

    @Test func adaptivePromptUsesEveryHalfStarBand() {
        #expect(ReactionPrompt(rating: nil) == nil)

        for rating in stride(from: 0.5, through: 2.5, by: 0.5) {
            #expect(ReactionPrompt(rating: rating) == .negative)
        }

        for rating in stride(from: 3.0, through: 3.5, by: 0.5) {
            #expect(ReactionPrompt(rating: rating) == .mixed)
        }

        for rating in stride(from: 4.0, through: 5.0, by: 0.5) {
            #expect(ReactionPrompt(rating: rating) == .positive)
        }
    }

    @Test func orderedSelectionTogglesAndPersistsDisplayValues() throws {
        let hype = try requiredReaction("mood.hype")
        let bars = try requiredReaction("craft.bars")
        var state = ReactionSelectionState()

        state.addCanonical(hype)
        #expect(state.addCustom("  graduation   summer ") == .valid(displayValue: "graduation summer"))
        state.addCanonical(bars)
        #expect(state.persistedDisplayValues == ["hype", "graduation summer", "bars"])

        state.toggleCanonical(hype)
        #expect(state.persistedDisplayValues == ["graduation summer", "bars"])

        state.toggleCanonical(hype)
        #expect(state.persistedDisplayValues == ["graduation summer", "bars", "hype"])

        state.remove(try #require(state.selections.first))
        #expect(state.persistedDisplayValues == ["bars", "hype"])
    }

    @Test func selectionDeduplicatesByComparisonKeyWithoutReordering() throws {
        let hype = try requiredReaction("mood.hype")
        let bars = try requiredReaction("craft.bars")
        var state = ReactionSelectionState(selections: [
            .custom("Graduation Summer"),
            .custom("graduation   summer"),
            .canonical(bars)
        ])

        #expect(state.persistedDisplayValues == ["Graduation Summer", "bars"])
        #expect(state.addCustom("BARS") == .valid(displayValue: "BARS"))
        #expect(state.persistedDisplayValues == ["Graduation Summer", "bars"])

        var caseShapedCustom = ReactionSelectionState(
            persistedDisplayValues: ["HYPE"],
            catalog: catalog
        )
        #expect(caseShapedCustom.selections.first?.isCustom == true)

        caseShapedCustom.addCanonical(hype)
        #expect(caseShapedCustom.persistedDisplayValues == ["hype"])
        #expect(caseShapedCustom.selections.first?.canonicalID == hype.id)
    }

    @Test func persistedRestorationCanonicalizesOnlyExactDisplayNames() throws {
        let exact = ReactionSelectionState(
            persistedDisplayValues: ["hype"],
            catalog: catalog
        )
        #expect(exact.selections.first?.canonicalID == "mood.hype")

        for customValue in ["HYPE", "turnt", "floaty", "graduation summer"] {
            let restored = ReactionSelectionState(
                persistedDisplayValues: [customValue],
                catalog: catalog
            )

            #expect(restored.persistedDisplayValues == [customValue])
            #expect(restored.selections.first?.isCustom == true)
            #expect(restored.selections.first?.canonicalID == nil)
        }
    }

    @MainActor
    @Test func logEntryPersistsCanonicalAndCustomSelectionStringsWithoutSchemaChanges() throws {
        let hype = try requiredReaction("mood.hype")
        var state = ReactionSelectionState()
        state.addCanonical(hype)
        state.addCustom("graduation summer")

        let log = LogEntry(
            album: nil,
            rating: 4.5,
            tags: state.persistedDisplayValues
        )

        #expect(log.tags == ["hype", "graduation summer"])
        #expect(log.tagsRawValue == "[\"hype\",\"graduation summer\"]")
    }

    @Test func customValidationUsesExistingPracticalTagConstraints() {
        #expect(ReactionSelectionState.validateCustom("   ") == .empty)
        #expect(ReactionSelectionState.validateCustom("night, drive") == .containsSeparator)
        #expect(ReactionSelectionState.validateCustom("123") == .missingLetters)
        #expect(
            ReactionSelectionState.validateCustom(String(repeating: "a", count: 29))
                == .tooLong(maximum: 28)
        )
        #expect(
            ReactionSelectionState.validateCustom("  déjà   vu  ")
                == .valid(displayValue: "déjà vu")
        )
    }

    @Test func browserSearchResolvesCanonicalAliasAndCustomInLocalOrder() {
        let engine = ReactionBrowserSearchEngine(catalog: catalog)

        guard case .canonical(let canonical) = engine.presentation(for: "hype").exactMatch else {
            Issue.record("Expected exact canonical result.")
            return
        }
        #expect(canonical.id == "mood.hype")
        #expect(engine.presentation(for: "hype").customDisplayValue == nil)

        let aliasPresentation = engine.presentation(for: "turnt")
        guard case .alias(let alias, let aliasTag) = aliasPresentation.exactMatch else {
            Issue.record("Expected exact local alias result.")
            return
        }
        #expect(alias == "turnt")
        #expect(aliasTag.id == "mood.hype")
        #expect(aliasPresentation.customDisplayValue == "turnt")

        let custom = engine.presentation(for: "  graduation   summer ")
        #expect(custom.exactMatch == nil)
        #expect(custom.customDisplayValue == "graduation summer")
    }

    @Test func browserSearchUsesEveryCorrectedExplicitAmbiguityChoiceInDeclaredOrder() {
        let engine = ReactionBrowserSearchEngine(catalog: catalog)
        let expectedCandidates = [
            "warm": ["mood.comforting", "sonic.warm-production"],
            "icy": ["sonic.cold-production", "mood.confident", "mood.menacing"],
            "floaty": ["mood.dreamy", "mood.ethereal", "sonic.airy"],
            "easygoing": ["mood.carefree", "energy.laid-back"],
            "emotional": ["reaction.moving", "reaction.emotionally-resonant", "mood.vulnerable"],
            "clean": ["sonic.polished", "sonic.spacious", "critique.too-polished"]
        ]

        for (term, expectedIDs) in expectedCandidates {
            let presentation = engine.presentation(for: term)
            guard case .ambiguous(let alias, let candidates) = presentation.exactMatch else {
                Issue.record("Expected explicit ambiguity for \(term).")
                continue
            }

            #expect(alias.term == term)
            #expect(!alias.prompt.isEmpty)
            #expect(candidates.map(\.id) == expectedIDs)
            #expect(presentation.results.isEmpty)
            #expect(presentation.customDisplayValue == term)
        }
    }

    @Test func mixedRankerRemainsDeterministicAndExcludesSelectedCanonicalIDs() throws {
        let ranker = ReactionTagRanker(catalog: catalog)
        let mixed = ranker.rank(.init(rating: 3.5))
        let first = try #require(mixed.first)

        #expect(mixed.count == 6)
        #expect(mixed == ranker.rank(.init(rating: 3.5)))

        let excludingFirst = ranker.rank(.init(
            rating: 3.5,
            selectedReactionIDs: [first.tag.id]
        ))
        #expect(excludingFirst.count == 6)
        #expect(!excludingFirst.contains(where: { $0.tag.id == first.tag.id }))
    }

    private func requiredReaction(_ id: String) throws -> ReactionTagDefinition {
        try #require(catalog.reaction(id: id))
    }
}
