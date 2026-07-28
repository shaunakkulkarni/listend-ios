//
//  TaxonomyValidator.swift
//  Listend
//

import Foundation

nonisolated struct TaxonomyExpectedCounts: Equatable, Sendable {
    let taxonomyVersion: String
    let reactionTags: Int
    let primaryReactionTags: Int
    let reactionAliases: Int
    let ambiguousAliases: Int
    let genreStyles: Int
    let genreAliases: Int
    let genreFamilies: Int
    let reactionsByCategory: [ReactionTagCategory: Int]
    let genresByFamily: [String: Int]

    static let canonicalV1 = TaxonomyExpectedCounts(
        taxonomyVersion: "1.0.0-draft",
        reactionTags: 243,
        primaryReactionTags: 169,
        reactionAliases: 723,
        ambiguousAliases: 20,
        genreStyles: 355,
        genreAliases: 156,
        genreFamilies: 20,
        reactionsByCategory: [
            .moodVibe: 36,
            .energyMovement: 16,
            .sonicCharacter: 39,
            .craftPerformance: 51,
            .listeningContext: 37,
            .personalReaction: 22,
            .frictionCritique: 42
        ],
        genresByFamily: [
            "hip-hop-rap": 16,
            "rnb-soul-funk": 14,
            "pop": 19,
            "rock": 21,
            "punk-hardcore-metal": 22,
            "electronic-dance": 33,
            "jazz-blues": 18,
            "country-folk-americana": 17,
            "caribbean": 11,
            "african": 16,
            "latin": 22,
            "brazilian": 12,
            "south-asian": 20,
            "east-asian": 20,
            "mena": 16,
            "classical": 16,
            "ambient-experimental": 16,
            "soundtrack-stage": 9,
            "spiritual-religious": 12,
            "global-traditional": 25
        ]
    )
}

nonisolated enum TaxonomyValidationIssue: Equatable, Sendable {
    case versionMismatch(catalog: String, expected: String, actual: String)
    case countMismatch(name: String, expected: Int, actual: Int)
    case duplicateIdentifier(kind: String, value: String)
    case duplicateDisplayName(kind: String, key: String)
    case duplicateExactAlias(kind: String, key: String)
    case aliasShadowsCanonical(kind: String, key: String)
    case ambiguousAliasOverlapsExactAlias(String)
    case ambiguousAliasOverlapsCanonical(String)
    case invalidAmbiguousCandidateCount(term: String, count: Int)
    case duplicateAmbiguousCandidate(term: String, id: String)
    case unknownReference(kind: String, owner: String, value: String)
    case invalidLabel(id: String, reason: String)
    case invalidValue(kind: String, owner: String, value: String)
}

nonisolated struct TaxonomyValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    let issues: [TaxonomyValidationIssue]

    var description: String {
        issues.map(String.init(describing:)).joined(separator: "\n")
    }
}

nonisolated enum TaxonomyValidator {
    nonisolated static func validate(
        reactions: ReactionTagCatalog,
        genres: GenreStyleCatalog,
        ambiguousAliases: AmbiguousAliasCatalog,
        expectedCounts: TaxonomyExpectedCounts? = nil
    ) throws {
        var issues: [TaxonomyValidationIssue] = []

        validateVersions(
            reactions: reactions,
            genres: genres,
            ambiguousAliases: ambiguousAliases,
            expectedCounts: expectedCounts,
            issues: &issues
        )
        validateReactionCatalog(reactions, genres: genres, issues: &issues)
        validateGenreCatalog(genres, issues: &issues)
        validateAmbiguousAliases(
            ambiguousAliases,
            reactions: reactions,
            issues: &issues
        )

        if let expectedCounts {
            validateExpectedCounts(
                expectedCounts,
                reactions: reactions,
                genres: genres,
                ambiguousAliases: ambiguousAliases,
                issues: &issues
            )
        }

        guard issues.isEmpty else {
            throw TaxonomyValidationError(issues: issues)
        }
    }

    private nonisolated static func validateVersions(
        reactions: ReactionTagCatalog,
        genres: GenreStyleCatalog,
        ambiguousAliases: AmbiguousAliasCatalog,
        expectedCounts: TaxonomyExpectedCounts?,
        issues: inout [TaxonomyValidationIssue]
    ) {
        let expectedVersion = expectedCounts?.taxonomyVersion ?? reactions.taxonomyVersion

        for (catalog, version) in [
            ("reactions", reactions.taxonomyVersion),
            ("genres", genres.taxonomyVersion),
            ("ambiguous aliases", ambiguousAliases.taxonomyVersion)
        ] where version != expectedVersion {
            issues.append(.versionMismatch(catalog: catalog, expected: expectedVersion, actual: version))
        }
    }

    private nonisolated static func validateReactionCatalog(
        _ catalog: ReactionTagCatalog,
        genres: GenreStyleCatalog,
        issues: inout [TaxonomyValidationIssue]
    ) {
        var categoryIDs = Set<ReactionTagCategory>()
        for category in catalog.categories {
            guard categoryIDs.insert(category.id).inserted else {
                issues.append(.duplicateIdentifier(kind: "reaction category", value: category.id.rawValue))
                continue
            }

            if category.displayName != category.id.displayName {
                issues.append(
                    .invalidValue(
                        kind: "reaction category display name",
                        owner: category.id.rawValue,
                        value: category.displayName
                    )
                )
            }
        }

        for category in ReactionTagCategory.allCases where !categoryIDs.contains(category) {
            issues.append(.unknownReference(kind: "reaction category definition", owner: "catalog", value: category.rawValue))
        }

        if Set(catalog.allowedPolarities) != Set(ReactionTagPolarity.allCases)
            || catalog.allowedPolarities.count != ReactionTagPolarity.allCases.count {
            issues.append(.invalidValue(kind: "allowed polarities", owner: "catalog", value: "incomplete or duplicated"))
        }

        if Set(catalog.allowedRecommendationRoles) != Set(RecommendationTagRole.allCases)
            || catalog.allowedRecommendationRoles.count != RecommendationTagRole.allCases.count {
            issues.append(.invalidValue(kind: "allowed recommendation roles", owner: "catalog", value: "incomplete or duplicated"))
        }

        validateUniqueStrings(catalog.soundPrintDimensions, kind: "SoundPrint dimension", issues: &issues)
        validateUniqueStrings(catalog.avoidanceSignals, kind: "avoidance signal", issues: &issues)

        let allowedDimensions = Set(catalog.soundPrintDimensions)
        let allowedAvoidanceSignals = Set(catalog.avoidanceSignals)
        let allowedFamilies = Set(genres.families.map(\.id))
        let allowedPolarities = Set(catalog.allowedPolarities)
        let allowedRoles = Set(catalog.allowedRecommendationRoles)

        var identifiers = Set<String>()
        var displayOwners: [String: String] = [:]
        var aliasOwners: [String: String] = [:]

        for tag in catalog.tags {
            if !identifiers.insert(tag.id).inserted {
                issues.append(.duplicateIdentifier(kind: "reaction", value: tag.id))
            }

            if !tag.id.contains(".") {
                issues.append(.invalidValue(kind: "reaction identifier", owner: tag.id, value: "not namespaced"))
            }

            let displayKey = TagTextNormalizer.comparisonKey(tag.displayName)
            if displayKey.isEmpty {
                issues.append(.invalidLabel(id: tag.id, reason: "empty after normalization"))
            } else if displayOwners.updateValue(tag.id, forKey: displayKey) != nil {
                issues.append(.duplicateDisplayName(kind: "reaction", key: displayKey))
            }

            if tag.displayName.count > 28 {
                issues.append(.invalidLabel(id: tag.id, reason: "exceeds 28 characters"))
            }

            if tag.displayName.contains(",") {
                issues.append(.invalidLabel(id: tag.id, reason: "contains a comma"))
            }

            if tag.displayName.contains("\n") || tag.displayName.contains("\r") {
                issues.append(.invalidLabel(id: tag.id, reason: "contains a line break"))
            }

            if !categoryIDs.contains(tag.category) {
                issues.append(.unknownReference(kind: "reaction category", owner: tag.id, value: tag.category.rawValue))
            }

            if !allowedPolarities.contains(tag.polarity) {
                issues.append(.invalidValue(kind: "reaction polarity", owner: tag.id, value: tag.polarity.rawValue))
            }

            if !allowedRoles.contains(tag.recommendationRole) {
                issues.append(.invalidValue(kind: "reaction recommendation role", owner: tag.id, value: tag.recommendationRole.rawValue))
            }

            for family in tag.genreAffinityFamilies where !allowedFamilies.contains(family) {
                issues.append(.unknownReference(kind: "genre affinity family", owner: tag.id, value: family))
            }

            for dimension in tag.soundPrintDimensions where !allowedDimensions.contains(dimension) {
                issues.append(.unknownReference(kind: "SoundPrint dimension", owner: tag.id, value: dimension))
            }

            for signal in tag.avoidanceSignals where !allowedAvoidanceSignals.contains(signal) {
                issues.append(.unknownReference(kind: "avoidance signal", owner: tag.id, value: signal))
            }

            for alias in tag.aliases {
                let aliasKey = TagTextNormalizer.comparisonKey(alias)
                guard !aliasKey.isEmpty else {
                    issues.append(.invalidValue(kind: "reaction alias", owner: tag.id, value: "empty"))
                    continue
                }

                if let existingOwner = aliasOwners[aliasKey], existingOwner != tag.id {
                    issues.append(.duplicateExactAlias(kind: "reaction", key: aliasKey))
                } else {
                    aliasOwners[aliasKey] = tag.id
                }
            }
        }

        for (aliasKey, aliasOwner) in aliasOwners {
            if let displayOwner = displayOwners[aliasKey], displayOwner != aliasOwner {
                issues.append(.aliasShadowsCanonical(kind: "reaction", key: aliasKey))
            }
        }
    }

    private nonisolated static func validateGenreCatalog(
        _ catalog: GenreStyleCatalog,
        issues: inout [TaxonomyValidationIssue]
    ) {
        var familyIDs = Set<String>()
        var familyDisplayKeys = Set<String>()

        for family in catalog.families {
            if !familyIDs.insert(family.id).inserted {
                issues.append(.duplicateIdentifier(kind: "genre family", value: family.id))
            }

            let displayKey = TagTextNormalizer.comparisonKey(family.displayName)
            if !familyDisplayKeys.insert(displayKey).inserted {
                issues.append(.duplicateDisplayName(kind: "genre family", key: displayKey))
            }
        }

        var identifiers = Set<String>()
        var displayOwners: [String: String] = [:]
        var aliasOwners: [String: String] = [:]

        for style in catalog.styles {
            if !identifiers.insert(style.id).inserted {
                issues.append(.duplicateIdentifier(kind: "genre style", value: style.id))
            }

            if !style.id.contains(".") {
                issues.append(.invalidValue(kind: "genre identifier", owner: style.id, value: "not namespaced"))
            }

            let displayKey = TagTextNormalizer.comparisonKey(style.displayName)
            if displayKey.isEmpty {
                issues.append(.invalidLabel(id: style.id, reason: "empty after normalization"))
            } else if displayOwners.updateValue(style.id, forKey: displayKey) != nil {
                issues.append(.duplicateDisplayName(kind: "genre style", key: displayKey))
            }

            if !familyIDs.contains(style.family) {
                issues.append(.unknownReference(kind: "genre family", owner: style.id, value: style.family))
            }

            for alias in style.aliases {
                let aliasKey = TagTextNormalizer.comparisonKey(alias)
                guard !aliasKey.isEmpty else {
                    issues.append(.invalidValue(kind: "genre alias", owner: style.id, value: "empty"))
                    continue
                }

                if let existingOwner = aliasOwners[aliasKey], existingOwner != style.id {
                    issues.append(.duplicateExactAlias(kind: "genre style", key: aliasKey))
                } else {
                    aliasOwners[aliasKey] = style.id
                }
            }
        }

        for style in catalog.styles {
            if let parentID = style.parentID, !identifiers.contains(parentID) {
                issues.append(.unknownReference(kind: "genre parent", owner: style.id, value: parentID))
            }
        }

        for (aliasKey, aliasOwner) in aliasOwners {
            if let displayOwner = displayOwners[aliasKey], displayOwner != aliasOwner {
                issues.append(.aliasShadowsCanonical(kind: "genre style", key: aliasKey))
            }
        }
    }

    private nonisolated static func validateAmbiguousAliases(
        _ catalog: AmbiguousAliasCatalog,
        reactions: ReactionTagCatalog,
        issues: inout [TaxonomyValidationIssue]
    ) {
        let reactionIDs = Set(reactions.tags.map(\.id))
        let canonicalKeys = Set(reactions.tags.map { TagTextNormalizer.comparisonKey($0.displayName) })
        let exactAliasKeys = Set(reactions.tags.flatMap(\.aliases).map(TagTextNormalizer.comparisonKey))
        var ambiguousKeys = Set<String>()

        for alias in catalog.aliases {
            let termKey = TagTextNormalizer.comparisonKey(alias.term)

            if !ambiguousKeys.insert(termKey).inserted {
                issues.append(.duplicateIdentifier(kind: "ambiguous alias", value: termKey))
            }

            if exactAliasKeys.contains(termKey) {
                issues.append(.ambiguousAliasOverlapsExactAlias(termKey))
            }

            if canonicalKeys.contains(termKey) {
                issues.append(.ambiguousAliasOverlapsCanonical(termKey))
            }

            if !(2...3).contains(alias.candidateIDs.count) {
                issues.append(.invalidAmbiguousCandidateCount(term: alias.term, count: alias.candidateIDs.count))
            }

            var candidateIDs = Set<String>()
            for candidateID in alias.candidateIDs {
                if !candidateIDs.insert(candidateID).inserted {
                    issues.append(.duplicateAmbiguousCandidate(term: alias.term, id: candidateID))
                }

                if !reactionIDs.contains(candidateID) {
                    issues.append(.unknownReference(kind: "ambiguous candidate", owner: alias.term, value: candidateID))
                }
            }
        }
    }

    private nonisolated static func validateExpectedCounts(
        _ expected: TaxonomyExpectedCounts,
        reactions: ReactionTagCatalog,
        genres: GenreStyleCatalog,
        ambiguousAliases: AmbiguousAliasCatalog,
        issues: inout [TaxonomyValidationIssue]
    ) {
        validateCount("reaction tags", actual: reactions.tags.count, expected: expected.reactionTags, issues: &issues)
        validateCount(
            "primary reaction tags",
            actual: reactions.tags.filter(\.isPrimarySuggestion).count,
            expected: expected.primaryReactionTags,
            issues: &issues
        )
        validateCount(
            "reaction aliases",
            actual: reactions.tags.reduce(0) { $0 + $1.aliases.count },
            expected: expected.reactionAliases,
            issues: &issues
        )
        validateCount("ambiguous aliases", actual: ambiguousAliases.aliases.count, expected: expected.ambiguousAliases, issues: &issues)
        validateCount("genre styles", actual: genres.styles.count, expected: expected.genreStyles, issues: &issues)
        validateCount(
            "genre aliases",
            actual: genres.styles.reduce(0) { $0 + $1.aliases.count },
            expected: expected.genreAliases,
            issues: &issues
        )
        validateCount("genre families", actual: genres.families.count, expected: expected.genreFamilies, issues: &issues)

        for category in ReactionTagCategory.allCases {
            validateCount(
                "reaction category \(category.rawValue)",
                actual: reactions.tags.filter { $0.category == category }.count,
                expected: expected.reactionsByCategory[category] ?? 0,
                issues: &issues
            )
        }

        for family in genres.families {
            validateCount(
                "genre family \(family.id)",
                actual: genres.styles.filter { $0.family == family.id }.count,
                expected: expected.genresByFamily[family.id] ?? 0,
                issues: &issues
            )
        }
    }

    private nonisolated static func validateCount(
        _ name: String,
        actual: Int,
        expected: Int,
        issues: inout [TaxonomyValidationIssue]
    ) {
        if actual != expected {
            issues.append(.countMismatch(name: name, expected: expected, actual: actual))
        }
    }

    private nonisolated static func validateUniqueStrings(
        _ values: [String],
        kind: String,
        issues: inout [TaxonomyValidationIssue]
    ) {
        var seen = Set<String>()

        for value in values {
            let key = TagTextNormalizer.comparisonKey(value)
            if key.isEmpty {
                issues.append(.invalidValue(kind: kind, owner: "catalog", value: "empty"))
            } else if !seen.insert(key).inserted {
                issues.append(.duplicateIdentifier(kind: kind, value: key))
            }
        }
    }
}
