//
//  ReactionBrowsing.swift
//  ListendShared
//

import Foundation

nonisolated enum ReactionPrompt: String, Equatable, Sendable {
    case positive
    case mixed
    case negative

    init?(rating: Double?) {
        guard let rating else {
            return nil
        }

        if rating >= 4 {
            self = .positive
        } else if rating >= 3 {
            self = .mixed
        } else {
            self = .negative
        }
    }

    var title: String {
        switch self {
        case .positive:
            return "What made it hit?"
        case .mixed:
            return "What worked—and what didn’t?"
        case .negative:
            return "What lost you?"
        }
    }
}

nonisolated struct ReactionBrowserSearchPresentation: Equatable, Sendable {
    nonisolated enum ExactMatch: Equatable, Sendable {
        case canonical(ReactionTagDefinition)
        case alias(alias: String, tag: ReactionTagDefinition)
        case ambiguous(alias: AmbiguousTagAlias, candidates: [ReactionTagDefinition])
    }

    let exactMatch: ExactMatch?
    let results: [ReactionTagSearchResult]
    let customDisplayValue: String?

    var isBrowsing: Bool {
        exactMatch == nil && results.isEmpty && customDisplayValue == nil
    }

    var allowsSemanticLookup: Bool {
        guard exactMatch == nil, customDisplayValue != nil else {
            return false
        }

        let hasSuitableLocalResult = results.contains { result in
            result.matchKind == .typo || result.score >= 650
        }
        return !hasSuitableLocalResult
    }
}

nonisolated struct ReactionBrowserSearchEngine: Sendable {
    private let resolver: LocalReactionTagResolver
    private let searchIndex: ReactionTagSearchIndex

    init(catalog: TaxonomyCatalog) {
        resolver = LocalReactionTagResolver(catalog: catalog)
        searchIndex = ReactionTagSearchIndex(catalog: catalog)
    }

    func presentation(for query: String) -> ReactionBrowserSearchPresentation {
        let displayValue = TagTextNormalizer.displayValue(query)
        guard !displayValue.isEmpty else {
            return ReactionBrowserSearchPresentation(
                exactMatch: nil,
                results: [],
                customDisplayValue: nil
            )
        }

        switch resolver.resolveExact(displayValue) {
        case .canonical(let tag):
            return ReactionBrowserSearchPresentation(
                exactMatch: .canonical(tag),
                results: [],
                customDisplayValue: nil
            )
        case .ambiguous(let alias, let candidates):
            return ReactionBrowserSearchPresentation(
                exactMatch: .ambiguous(alias: alias, candidates: candidates),
                results: [],
                customDisplayValue: displayValue
            )
        case .exactAlias(let alias, let tag):
            return ReactionBrowserSearchPresentation(
                exactMatch: .alias(alias: alias, tag: tag),
                results: [],
                customDisplayValue: displayValue
            )
        case .unresolved(let customDisplayValue):
            return ReactionBrowserSearchPresentation(
                exactMatch: nil,
                results: searchIndex.search(displayValue),
                customDisplayValue: customDisplayValue
            )
        }
    }
}
