//
//  LocalReactionTagResolver.swift
//  Listend
//

import Foundation

nonisolated enum LocalReactionTagResolution: Equatable, Sendable {
    case canonical(ReactionTagDefinition)
    case ambiguous(alias: AmbiguousTagAlias, candidates: [ReactionTagDefinition])
    case exactAlias(alias: String, tag: ReactionTagDefinition)
    case unresolved(customDisplayValue: String)
}

nonisolated struct LocalReactionTagResolver: Sendable {
    private let canonicalByKey: [String: ReactionTagDefinition]
    private let ambiguousByKey: [String: AmbiguousTagAlias]
    private let exactAliasByKey: [String: (alias: String, tag: ReactionTagDefinition)]
    private let reactionsByID: [String: ReactionTagDefinition]

    init(catalog: TaxonomyCatalog) {
        let reactionsByID = Dictionary(
            uniqueKeysWithValues: catalog.reactions.tags.map { ($0.id, $0) }
        )
        self.reactionsByID = reactionsByID
        self.canonicalByKey = Dictionary(
            uniqueKeysWithValues: catalog.reactions.tags.map {
                (TagTextNormalizer.comparisonKey($0.displayName), $0)
            }
        )
        self.ambiguousByKey = Dictionary(
            uniqueKeysWithValues: catalog.ambiguousAliases.aliases.map {
                (TagTextNormalizer.comparisonKey($0.term), $0)
            }
        )
        var exactAliasByKey: [String: (alias: String, tag: ReactionTagDefinition)] = [:]
        for tag in catalog.reactions.tags {
            for alias in tag.aliases {
                let key = TagTextNormalizer.comparisonKey(alias)
                if exactAliasByKey[key] == nil {
                    exactAliasByKey[key] = (alias: alias, tag: tag)
                }
            }
        }
        self.exactAliasByKey = exactAliasByKey
    }

    func resolveExact(_ input: String) -> LocalReactionTagResolution {
        let displayValue = TagTextNormalizer.displayValue(input)
        let key = TagTextNormalizer.comparisonKey(displayValue)

        if let canonical = canonicalByKey[key] {
            return .canonical(canonical)
        }

        if let ambiguous = ambiguousByKey[key] {
            let candidates = ambiguous.candidateIDs.compactMap { reactionsByID[$0] }
            return .ambiguous(alias: ambiguous, candidates: candidates)
        }

        if let match = exactAliasByKey[key] {
            return .exactAlias(alias: match.alias, tag: match.tag)
        }

        return .unresolved(customDisplayValue: displayValue)
    }

    func canonicalTag(forPersistedDisplayValue value: String) -> ReactionTagDefinition? {
        canonicalByKey[TagTextNormalizer.comparisonKey(value)]
    }
}

nonisolated enum LocalGenreStyleResolution: Equatable, Sendable {
    case canonical(GenreStyleDefinition)
    case exactAlias(alias: String, style: GenreStyleDefinition)
    case unresolved(String)
}

nonisolated struct LocalGenreStyleResolver: Sendable {
    private let canonicalByKey: [String: GenreStyleDefinition]
    private let exactAliasByKey: [String: (alias: String, style: GenreStyleDefinition)]

    init(catalog: TaxonomyCatalog) {
        self.canonicalByKey = Dictionary(
            uniqueKeysWithValues: catalog.genres.styles.map {
                (TagTextNormalizer.comparisonKey($0.displayName), $0)
            }
        )
        var exactAliasByKey: [String: (alias: String, style: GenreStyleDefinition)] = [:]
        for style in catalog.genres.styles {
            for alias in style.aliases {
                let key = TagTextNormalizer.comparisonKey(alias)
                if exactAliasByKey[key] == nil {
                    exactAliasByKey[key] = (alias: alias, style: style)
                }
            }
        }
        self.exactAliasByKey = exactAliasByKey
    }

    func resolveExact(_ input: String) -> LocalGenreStyleResolution {
        let displayValue = TagTextNormalizer.displayValue(input)
        let key = TagTextNormalizer.comparisonKey(displayValue)

        if let canonical = canonicalByKey[key] {
            return .canonical(canonical)
        }

        if let match = exactAliasByKey[key] {
            return .exactAlias(alias: match.alias, style: match.style)
        }

        return .unresolved(displayValue)
    }
}
