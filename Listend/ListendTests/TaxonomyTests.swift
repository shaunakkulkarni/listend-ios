//
//  TaxonomyTests.swift
//  ListendTests
//

import Foundation
import Testing
@testable import Listend

nonisolated struct TaxonomyTests {
    @Test func bundledApplicationCatalogLoadsWithCorrectedTotals() throws {
        let catalog = try loadBundledCatalog()

        #expect(catalog.reactions.taxonomyVersion == "1.0.0-draft")
        #expect(catalog.reactions.tags.count == 243)
        #expect(catalog.reactions.tags.filter(\.isPrimarySuggestion).count == 169)
        #expect(catalog.reactions.tags.reduce(0) { $0 + $1.aliases.count } == 723)
        #expect(catalog.ambiguousAliases.aliases.count == 20)
        #expect(catalog.genres.styles.count == 355)
        #expect(catalog.genres.styles.reduce(0) { $0 + $1.aliases.count } == 156)
        #expect(catalog.genres.families.count == 20)
        #expect(!catalog.isEmpty)
        #expect(TaxonomyCatalogLoader.shared.reactions.tags.count == 243)
    }

    @Test func shareExtensionBundleContainsAndLoadsTheSameCatalog() throws {
        let appBundle = try applicationBundle()
        let pluginsURL = try required(
            appBundle.builtInPlugInsURL,
            message: "The hosted app bundle has no PlugIns directory."
        )
        let extensionBundle = try required(
            Bundle(url: pluginsURL.appendingPathComponent("ListendShareExtension.appex")),
            message: "The built Share extension bundle is unavailable."
        )

        let catalog = try TaxonomyCatalogLoader.load(from: extensionBundle)

        #expect(catalog.reactions.tags.count == 243)
        #expect(catalog.genres.styles.count == 355)
        #expect(catalog.ambiguousAliases.aliases.count == 20)
        for filename in TaxonomyCatalogLoader.resourceFilenames {
            let components = filename.split(separator: ".", maxSplits: 1).map(String.init)
            #expect(
                extensionBundle.url(
                    forResource: components[0],
                    withExtension: components[1]
                ) != nil
            )
        }
    }

    @Test func displayAndComparisonNormalizationRemainSeparate() {
        let input = "  K-R&B \n  déjà—vu   música  "

        #expect(TagTextNormalizer.displayValue(input) == "K-R&B déjà—vu música")
        #expect(TagTextNormalizer.comparisonKey(input) == "k-r&b deja-vu musica")
        #expect(TagTextNormalizer.comparisonKey("ﬂoaty") == "floaty")
        #expect(
            TagTextNormalizer.comparisonKey("música mexicana")
                == TagTextNormalizer.comparisonKey("MUSICA MEXICANA")
        )
    }

    @MainActor
    @Test func existingLogStringStoragePreservesDisplayValuesAndLegacyDecoding() {
        let log = LogEntry(
            album: nil,
            rating: 4,
            tags: ["  música   mexicana ", "MUSICA MEXICANA", " K–R&B "]
        )

        #expect(log.tags == ["música mexicana", "K–R&B"])
        #expect(log.tagsRawValue == "[\"música mexicana\",\"K–R&B\"]")

        log.tagsRawValue = "floaty, Élite, late   night"
        #expect(log.tags == ["floaty", "Élite", "late night"])

        log.tagsRawValue = "[\"floaty\",\"música mexicana\"]"
        #expect(log.tags == ["floaty", "música mexicana"])

        log.tagsRawValue = "[floaty,música mexicana"
        #expect(log.tags.isEmpty)
    }

    @Test func exactResolverUsesCanonicalThenAmbiguousThenExactAlias() throws {
        let catalog = try loadBundledCatalog()
        let resolver = LocalReactionTagResolver(catalog: catalog)

        guard case .canonical(let canonical) = resolver.resolveExact("  HYPÉ  ") else {
            Issue.record("A comparison-normalized canonical name should resolve first.")
            return
        }
        #expect(canonical.id == "mood.hype")

        guard case .ambiguous(let alias, let candidates) = resolver.resolveExact("icy") else {
            Issue.record("An explicitly ambiguous term should return its declared choices.")
            return
        }
        #expect(alias.term == "icy")
        #expect(candidates.map(\.id) == [
            "sonic.cold-production",
            "mood.confident",
            "mood.menacing"
        ])

        guard case .exactAlias(let alias, let tag) = resolver.resolveExact("turnt") else {
            Issue.record("A nonambiguous exact alias should resolve locally.")
            return
        }
        #expect(alias == "turnt")
        #expect(tag.id == "mood.hype")

        guard case .unresolved(let custom) = resolver.resolveExact("  graduation   summer ") else {
            Issue.record("Unknown input should remain a cleaned custom value.")
            return
        }
        #expect(custom == "graduation summer")
        #expect(resolver.canonicalTag(forPersistedDisplayValue: "hype")?.id == "mood.hype")
        #expect(resolver.canonicalTag(forPersistedDisplayValue: "HYPE") == nil)
        #expect(resolver.canonicalTag(forPersistedDisplayValue: "turnt") == nil)
        #expect(resolver.canonicalTag(forPersistedDisplayValue: "floaty") == nil)
    }

    @Test func genreResolverPreservesCanonicalDisplayNamesAndDiacritics() throws {
        let resolver = LocalGenreStyleResolver(catalog: try loadBundledCatalog())

        guard case .canonical(let musicaMexicana) = resolver.resolveExact("musica mexicana") else {
            Issue.record("Comparison normalization should restore the canonical genre display.")
            return
        }
        #expect(musicaMexicana.id == "genre.musica-mexicana")
        #expect(musicaMexicana.displayName == "música mexicana")

        guard case .canonical(let koreanRNB) = resolver.resolveExact("K–R&B") else {
            Issue.record("Dash variants should match the canonical genre.")
            return
        }
        #expect(koreanRNB.id == "genre.k-rnb")
        #expect(koreanRNB.displayName == "K-R&B")
    }

    @Test func localSearchRanksPrefixesAliasesTokensAndTyposDeterministically() throws {
        let index = ReactionTagSearchIndex(catalog: try loadBundledCatalog())

        let prefixResults = index.search("cold prod")
        #expect(prefixResults.first?.tag.id == "sonic.cold-production")
        #expect(prefixResults.first?.matchKind == .displayName)

        let displayPrefixResults = index.search("lyri")
        #expect(displayPrefixResults.first?.tag.id == "craft.lyricism")
        #expect(displayPrefixResults.first?.matchKind == .displayName)

        let aliasResults = index.search("pen game")
        #expect(aliasResults.first?.tag.id == "craft.bars")
        #expect(aliasResults.first?.matchKind == .alias)

        let categoryResults = index.search("friction critique")
        #expect(categoryResults.contains(where: { $0.tag.category == .frictionCritique }))
        #expect(categoryResults.count <= 20)

        let typoResults = index.search("replayble")
        #expect(typoResults.first?.tag.id == "reaction.replayable")
        #expect(typoResults.first?.matchKind == .typo)
        #expect(typoResults == index.search("replayble"))
    }

    @Test func deterministicRankerRespectsPolarityDiversityContextAndEvidence() throws {
        let ranker = ReactionTagRanker(catalog: try loadBundledCatalog())
        let high = ranker.rank(.init(rating: 5))
        let low = ranker.rank(.init(rating: 2))

        #expect(high.count == 6)
        #expect(high.contains(where: { $0.tag.category == .personalReaction }))
        #expect(high.allSatisfy { $0.tag.category != .listeningContext })
        #expect(maximumCategoryCount(in: high) <= 2)

        #expect(low.count == 6)
        #expect(low.first?.tag.polarity == .negative)
        #expect(low.filter { $0.tag.category == .frictionCritique }.count == 3)
        #expect(maximumCategoryCount(in: low, excluding: .frictionCritique) <= 2)

        let evidence = ranker.rank(
            .init(
                rating: 4.5,
                reviewText: "The pen game and cold production kept pulling me back."
            )
        )
        #expect(evidence.contains(where: { $0.tag.id == "craft.bars" }))
        #expect(evidence.contains(where: { $0.tag.id == "sonic.cold-production" }))

        let contextual = ranker.rank(
            .init(
                rating: 4.5,
                priorCanonicalTagCounts: ["context.gym": 4]
            )
        )
        #expect(contextual.contains(where: { $0.tag.id == "context.gym" }))

        let replayGroup = Set([
            "reaction.replayable",
            "reaction.on-repeat",
            "reaction.no-skips"
        ])
        #expect(high.filter { replayGroup.contains($0.tag.id) }.count <= 1)
        #expect(high == ranker.rank(.init(rating: 5)))
    }

    @Test func validatorRejectsAmbiguousVersusExactAliasOverlap() throws {
        let catalog = try loadBundledCatalog()
        let firstTag = try required(catalog.reactions.tags.first, message: "Reaction catalog is empty.")
        let modifiedTag = replacing(firstTag, aliases: firstTag.aliases + ["icy"])
        let reactions = replacing(
            catalog.reactions,
            tags: [modifiedTag] + Array(catalog.reactions.tags.dropFirst())
        )

        let error = validationError(
            reactions: reactions,
            genres: catalog.genres,
            ambiguousAliases: catalog.ambiguousAliases
        )

        #expect(error.issues.contains(.ambiguousAliasOverlapsExactAlias("icy")))
    }

    @Test func validatorRejectsDuplicateCanonicalValuesAndAliasCollisions() throws {
        let catalog = try loadBundledCatalog()
        let first = try required(catalog.reactions.tags.first, message: "Reaction catalog is empty.")
        let second = try required(catalog.reactions.tags.dropFirst().first, message: "Reaction catalog has fewer than two tags.")
        let sharedAlias = try required(first.aliases.first, message: "The first reaction has no alias.")
        let collidingSecond = replacing(second, aliases: second.aliases + [sharedAlias])
        let reactions = replacing(
            catalog.reactions,
            tags: catalog.reactions.tags + [first, collidingSecond]
        )

        let error = validationError(
            reactions: reactions,
            genres: catalog.genres,
            ambiguousAliases: catalog.ambiguousAliases
        )

        #expect(error.issues.contains(.duplicateIdentifier(kind: "reaction", value: first.id)))
        #expect(
            error.issues.contains(
                .duplicateDisplayName(
                    kind: "reaction",
                    key: TagTextNormalizer.comparisonKey(first.displayName)
                )
            )
        )
        #expect(
            error.issues.contains(
                .duplicateExactAlias(
                    kind: "reaction",
                    key: TagTextNormalizer.comparisonKey(sharedAlias)
                )
            )
        )
    }

    @Test func validatorRejectsUnknownMappingsAndInvalidLabels() throws {
        let catalog = try loadBundledCatalog()
        let first = try required(catalog.reactions.tags.first, message: "Reaction catalog is empty.")
        let invalid = replacing(
            first,
            displayName: "this label, is intentionally far too long",
            genreAffinityFamilies: ["unknown-family"],
            soundPrintDimensions: ["unknownDimension"],
            avoidanceSignals: ["unknownSignal"]
        )
        let reactions = replacing(
            catalog.reactions,
            tags: [invalid] + Array(catalog.reactions.tags.dropFirst())
        )

        let error = validationError(
            reactions: reactions,
            genres: catalog.genres,
            ambiguousAliases: catalog.ambiguousAliases
        )

        #expect(error.issues.contains(.invalidLabel(id: first.id, reason: "exceeds 28 characters")))
        #expect(error.issues.contains(.invalidLabel(id: first.id, reason: "contains a comma")))
        #expect(error.issues.contains(.unknownReference(kind: "genre affinity family", owner: first.id, value: "unknown-family")))
        #expect(error.issues.contains(.unknownReference(kind: "SoundPrint dimension", owner: first.id, value: "unknownDimension")))
        #expect(error.issues.contains(.unknownReference(kind: "avoidance signal", owner: first.id, value: "unknownSignal")))
    }

    @Test func validatorRejectsUnknownGenreParentsAndAmbiguousCandidates() throws {
        let catalog = try loadBundledCatalog()
        let firstStyle = try required(catalog.genres.styles.first, message: "Genre catalog is empty.")
        let invalidStyle = replacing(firstStyle, parentID: "genre.not-real")
        let genres = replacing(
            catalog.genres,
            styles: [invalidStyle] + Array(catalog.genres.styles.dropFirst())
        )

        let firstAlias = try required(
            catalog.ambiguousAliases.aliases.first,
            message: "Ambiguous alias catalog is empty."
        )
        let invalidAlias = AmbiguousTagAlias(
            term: firstAlias.term,
            candidateIDs: firstAlias.candidateIDs + ["reaction.not-real"],
            prompt: firstAlias.prompt
        )
        let aliases = AmbiguousAliasCatalog(
            taxonomyVersion: catalog.ambiguousAliases.taxonomyVersion,
            generatedDate: catalog.ambiguousAliases.generatedDate,
            purpose: catalog.ambiguousAliases.purpose,
            aliases: [invalidAlias] + Array(catalog.ambiguousAliases.aliases.dropFirst())
        )

        let error = validationError(
            reactions: catalog.reactions,
            genres: genres,
            ambiguousAliases: aliases
        )

        #expect(error.issues.contains(.unknownReference(kind: "genre parent", owner: firstStyle.id, value: "genre.not-real")))
        #expect(error.issues.contains(.invalidAmbiguousCandidateCount(term: firstAlias.term, count: 4)))
        #expect(error.issues.contains(.unknownReference(kind: "ambiguous candidate", owner: firstAlias.term, value: "reaction.not-real")))
    }

    private func loadBundledCatalog() throws -> TaxonomyCatalog {
        try TaxonomyCatalogLoader.load(from: applicationBundle())
    }

    private func applicationBundle() throws -> Bundle {
        let candidates = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        return try required(
            candidates.first {
                $0.url(
                    forResource: TaxonomyCatalogLoader.reactionResourceName,
                    withExtension: "json"
                ) != nil
                    && $0.bundleURL.pathExtension == "app"
            },
            message: "Could not locate the hosted Listend app bundle."
        )
    }

    private func validationError(
        reactions: ReactionTagCatalog,
        genres: GenreStyleCatalog,
        ambiguousAliases: AmbiguousAliasCatalog
    ) -> TaxonomyValidationError {
        do {
            try TaxonomyValidator.validate(
                reactions: reactions,
                genres: genres,
                ambiguousAliases: ambiguousAliases
            )
            Issue.record("Expected taxonomy validation to fail.")
            return TaxonomyValidationError(issues: [])
        } catch let error as TaxonomyValidationError {
            return error
        } catch {
            Issue.record("Unexpected validation error: \(error)")
            return TaxonomyValidationError(issues: [])
        }
    }

    private func maximumCategoryCount(
        in tags: [RankedReactionTag],
        excluding excludedCategory: ReactionTagCategory? = nil
    ) -> Int {
        Dictionary(grouping: tags.map(\.tag), by: \.category)
            .filter { $0.key != excludedCategory }
            .values
            .map(\.count)
            .max() ?? 0
    }

    private func required<Value>(_ value: Value?, message: String) throws -> Value {
        guard let value else {
            throw TaxonomyTestError.missingFixture(message)
        }

        return value
    }

    private func replacing(
        _ catalog: ReactionTagCatalog,
        tags: some Sequence<ReactionTagDefinition>
    ) -> ReactionTagCatalog {
        ReactionTagCatalog(
            taxonomyVersion: catalog.taxonomyVersion,
            generatedDate: catalog.generatedDate,
            purpose: catalog.purpose,
            categories: catalog.categories,
            allowedPolarities: catalog.allowedPolarities,
            allowedRecommendationRoles: catalog.allowedRecommendationRoles,
            soundPrintDimensions: catalog.soundPrintDimensions,
            avoidanceSignals: catalog.avoidanceSignals,
            tags: Array(tags)
        )
    }

    private func replacing(
        _ tag: ReactionTagDefinition,
        displayName: String? = nil,
        aliases: [String]? = nil,
        genreAffinityFamilies: [String]? = nil,
        soundPrintDimensions: [String]? = nil,
        avoidanceSignals: [String]? = nil
    ) -> ReactionTagDefinition {
        ReactionTagDefinition(
            id: tag.id,
            displayName: displayName ?? tag.displayName,
            category: tag.category,
            definition: tag.definition,
            aliases: aliases ?? tag.aliases,
            polarity: tag.polarity,
            genreAffinityFamilies: genreAffinityFamilies ?? tag.genreAffinityFamilies,
            soundPrintDimensions: soundPrintDimensions ?? tag.soundPrintDimensions,
            avoidanceSignals: avoidanceSignals ?? tag.avoidanceSignals,
            recommendationRole: tag.recommendationRole,
            isPrimarySuggestion: tag.isPrimarySuggestion
        )
    }

    private func replacing(
        _ catalog: GenreStyleCatalog,
        styles: some Sequence<GenreStyleDefinition>
    ) -> GenreStyleCatalog {
        GenreStyleCatalog(
            taxonomyVersion: catalog.taxonomyVersion,
            generatedDate: catalog.generatedDate,
            purpose: catalog.purpose,
            families: catalog.families,
            styles: Array(styles)
        )
    }

    private func replacing(
        _ style: GenreStyleDefinition,
        parentID: String
    ) -> GenreStyleDefinition {
        GenreStyleDefinition(
            id: style.id,
            displayName: style.displayName,
            family: style.family,
            aliases: style.aliases,
            parentID: parentID,
            recommendationRole: style.recommendationRole
        )
    }
}

private nonisolated enum TaxonomyTestError: Error {
    case missingFixture(String)
}
