//
//  ReactionTagResolutionState.swift
//  Listend
//

import Foundation

nonisolated enum ReactionTagResolutionState: Equatable, Sendable {
    case idle
    case resolving(phrase: String)
    case confirmation(phrase: String, options: [ReactionTagDefinition])

    var canonicalOptions: [ReactionTagDefinition] {
        guard case .confirmation(_, let options) = self else {
            return []
        }
        return options
    }

    var customDisplayValue: String? {
        guard case .confirmation(let phrase, _) = self else {
            return nil
        }
        return phrase
    }

    static func confirmation(
        for resolution: ReactionTagResolution,
        originalPhrase: String
    ) -> ReactionTagResolutionState {
        switch resolution {
        case .canonical(let tag):
            return .confirmation(phrase: originalPhrase, options: [tag])
        case .choices(let choices):
            return .confirmation(phrase: originalPhrase, options: Array(choices.prefix(3)))
        case .custom:
            return .confirmation(phrase: originalPhrase, options: [])
        }
    }

    static func resolve(
        phrase: String,
        currentCategory: ReactionTagCategory? = nil,
        rating: Double?,
        selectedCanonicalIDs: Set<String>,
        reviewExcerpt: String,
        catalog: TaxonomyCatalog,
        semanticResolver: any ReactionTagResolving
    ) async -> ReactionTagResolution {
        let displayValue = TagTextNormalizer.displayValue(phrase)
        let localResolver = LocalReactionTagResolver(catalog: catalog)

        switch localResolver.resolveExact(displayValue) {
        case .canonical(let tag), .exactAlias(_, let tag):
            return .canonical(tag)
        case .ambiguous(_, let candidates):
            return .choices(Array(candidates.prefix(3)))
        case .unresolved:
            break
        }

        let localResults = ReactionTagSearchIndex(catalog: catalog).search(displayValue)
        let typoMatches = localResults.filter { $0.matchKind == .typo }
        if let firstTypo = typoMatches.first,
           !typoMatches.dropFirst().contains(where: { $0.score == firstTypo.score }) {
            return .canonical(firstTypo.tag)
        }

        var shortlisted = localResults.map(\.tag)
        shortlisted.append(contentsOf: ReactionTagRanker(catalog: catalog).rank(.init(
            rating: rating,
            reviewText: reviewExcerpt,
            selectedReactionIDs: selectedCanonicalIDs
        )).map(\.tag))

        if let currentCategory {
            shortlisted.append(contentsOf: catalog.reactions.tags.filter {
                $0.category == currentCategory
            })
        }

        let input = ReactionTagResolutionInput(
            phrase: displayValue,
            currentCategory: currentCategory,
            rating: rating,
            selectedCanonicalIDs: selectedCanonicalIDs,
            reviewExcerpt: reviewExcerpt,
            candidates: shortlisted
        )
        guard !input.candidates.isEmpty else {
            return .custom(displayValue: displayValue)
        }

        do {
            let semanticResult = try await semanticResolver.resolve(input)
            return validated(semanticResult, input: input)
                ?? .custom(displayValue: displayValue)
        } catch {
            return .custom(displayValue: displayValue)
        }
    }

    private static func validated(
        _ resolution: ReactionTagResolution,
        input: ReactionTagResolutionInput
    ) -> ReactionTagResolution? {
        let candidatesByID = Dictionary(
            uniqueKeysWithValues: input.candidates.map { ($0.id, $0) }
        )

        switch resolution {
        case .canonical(let tag):
            guard let candidate = candidatesByID[tag.id] else {
                return nil
            }
            return .canonical(candidate)

        case .choices(let choices):
            guard (1...3).contains(choices.count) else {
                return nil
            }

            var seen = Set<String>()
            let validatedChoices = choices.compactMap { choice -> ReactionTagDefinition? in
                guard seen.insert(choice.id).inserted else {
                    return nil
                }
                return candidatesByID[choice.id]
            }
            guard validatedChoices.count == choices.count else {
                return nil
            }
            return .choices(validatedChoices)

        case .custom:
            return .custom(displayValue: input.phrase)
        }
    }
}
