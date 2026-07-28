//
//  ReactionTagRanker.swift
//  Listend
//

import Foundation

nonisolated struct ReactionTagRankingInput: Equatable, Sendable {
    let rating: Double?
    let genreFamilyIDs: Set<String>
    let reviewText: String
    let selectedReactionIDs: Set<String>
    let priorCanonicalTagCounts: [String: Int]
    let limit: Int

    init(
        rating: Double?,
        genreFamilyIDs: Set<String> = [],
        reviewText: String = "",
        selectedReactionIDs: Set<String> = [],
        priorCanonicalTagCounts: [String: Int] = [:],
        limit: Int = 6
    ) {
        self.rating = rating
        self.genreFamilyIDs = genreFamilyIDs
        self.reviewText = reviewText
        self.selectedReactionIDs = selectedReactionIDs
        self.priorCanonicalTagCounts = priorCanonicalTagCounts
        self.limit = limit
    }
}

nonisolated struct RankedReactionTag: Identifiable, Equatable, Sendable {
    var id: String { tag.id }

    let tag: ReactionTagDefinition
    let score: Double
}

nonisolated struct ReactionTagRanker: Sendable {
    private nonisolated struct Candidate: Sendable {
        let rankedTag: RankedReactionTag
        let catalogOrder: Int
        let hasUserEvidence: Bool
        let historyCount: Int
    }

    private let tags: [ReactionTagDefinition]

    init(catalog: TaxonomyCatalog) {
        self.tags = catalog.reactions.tags
    }

    func rank(_ input: ReactionTagRankingInput) -> [RankedReactionTag] {
        let limit = min(max(input.limit, 0), 6)
        guard limit > 0 else {
            return []
        }

        let reviewKey = TagTextNormalizer.comparisonKey(input.reviewText)
        let candidates = tags.enumerated()
            .compactMap { index, tag -> Candidate? in
                guard tag.isPrimarySuggestion,
                      !input.selectedReactionIDs.contains(tag.id) else {
                    return nil
                }

                let reviewMatchStrength = Self.reviewMatchStrength(tag: tag, reviewKey: reviewKey)
                let historyCount = max(input.priorCanonicalTagCounts[tag.id] ?? 0, 0)
                let hasUserEvidence = reviewMatchStrength > 0 || historyCount > 0

                guard tag.category != .listeningContext || hasUserEvidence else {
                    return nil
                }

                let matchingGenreFamilies = input.genreFamilyIDs.intersection(tag.genreAffinityFamilies).count
                let score = (
                    100 * Self.ratingMultiplier(for: tag.polarity, rating: input.rating)
                ) + reviewMatchStrength
                    + min(Double(historyCount) * 12, 60)
                    + (Double(matchingGenreFamilies) * 5)

                return Candidate(
                    rankedTag: RankedReactionTag(tag: tag, score: score),
                    catalogOrder: index,
                    hasUserEvidence: hasUserEvidence,
                    historyCount: historyCount
                )
            }
            .sorted(by: Self.isHigherPriority)

        var selected: [Candidate] = []
        var categoryCounts: [ReactionTagCategory: Int] = [:]

        func canSelect(_ candidate: Candidate) -> Bool {
            guard !selected.contains(where: { $0.rankedTag.tag.id == candidate.rankedTag.tag.id }) else {
                return false
            }

            let category = candidate.rankedTag.tag.category
            let categoryLimit = category == .frictionCritique && (input.rating ?? 3) < 3 ? 3 : 2
            guard categoryCounts[category, default: 0] < categoryLimit else {
                return false
            }

            if let group = Self.nearSynonymGroup(containing: candidate.rankedTag.tag.id),
               selected.contains(where: { group.contains($0.rankedTag.tag.id) }),
               candidate.historyCount < 3 {
                return false
            }

            return true
        }

        func select(_ candidate: Candidate) {
            selected.append(candidate)
            categoryCounts[candidate.rankedTag.tag.category, default: 0] += 1
        }

        if let descriptiveEvidence = candidates.first(where: {
            $0.hasUserEvidence
                && ($0.rankedTag.tag.category == .craftPerformance
                    || $0.rankedTag.tag.category == .sonicCharacter)
        }), canSelect(descriptiveEvidence) {
            select(descriptiveEvidence)
        }

        if (input.rating ?? 0) >= 3,
           let personalReaction = candidates.first(where: {
               $0.rankedTag.tag.category == .personalReaction
           }),
           canSelect(personalReaction) {
            select(personalReaction)
        }

        for candidate in candidates where selected.count < limit {
            if canSelect(candidate) {
                select(candidate)
            }
        }

        let priorityByID = Dictionary(
            uniqueKeysWithValues: candidates.enumerated().map { ($0.element.rankedTag.tag.id, $0.offset) }
        )

        return selected
            .sorted {
                (priorityByID[$0.rankedTag.tag.id] ?? .max)
                    < (priorityByID[$1.rankedTag.tag.id] ?? .max)
            }
            .prefix(limit)
            .map(\.rankedTag)
    }

    private static func isHigherPriority(_ left: Candidate, _ right: Candidate) -> Bool {
        if left.rankedTag.score != right.rankedTag.score {
            return left.rankedTag.score > right.rankedTag.score
        }

        if left.catalogOrder != right.catalogOrder {
            return left.catalogOrder < right.catalogOrder
        }

        return left.rankedTag.tag.id < right.rankedTag.tag.id
    }

    private static func reviewMatchStrength(
        tag: ReactionTagDefinition,
        reviewKey: String
    ) -> Double {
        guard !reviewKey.isEmpty else {
            return 0
        }

        if containsWholePhrase(
            TagTextNormalizer.comparisonKey(tag.displayName),
            in: reviewKey
        ) {
            return 120
        }

        if tag.aliases.contains(where: {
            containsWholePhrase(TagTextNormalizer.comparisonKey($0), in: reviewKey)
        }) {
            return 105
        }

        return 0
    }

    private static func containsWholePhrase(_ phrase: String, in value: String) -> Bool {
        let searchable = tokenized(value)
        let query = tokenized(phrase)
        guard !query.isEmpty else {
            return false
        }

        return " \(searchable) ".contains(" \(query) ")
    }

    private static func tokenized(_ value: String) -> String {
        value.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func ratingMultiplier(
        for polarity: ReactionTagPolarity,
        rating: Double?
    ) -> Double {
        guard let rating else {
            switch polarity {
            case .positive:
                return 0.80
            case .neutral:
                return 1.00
            case .mixed:
                return 0.90
            case .negative:
                return 0.55
            }
        }

        if rating >= 4 {
            switch polarity {
            case .positive:
                return 1.00
            case .neutral:
                return 0.80
            case .mixed:
                return 0.55
            case .negative:
                return 0.30
            }
        }

        if rating >= 3 {
            switch polarity {
            case .positive:
                return 0.80
            case .neutral:
                return 0.90
            case .mixed:
                return 1.00
            case .negative:
                return 0.80
            }
        }

        switch polarity {
        case .positive:
            return 0.35
        case .neutral:
            return 0.70
        case .mixed:
            return 0.85
        case .negative:
            return 1.00
        }
    }

    private static func nearSynonymGroup(containing id: String) -> Set<String>? {
        nearSynonymGroups.first { $0.contains(id) }
    }

    private static let nearSynonymGroups: [Set<String>] = [
        [
            "reaction.replayable",
            "reaction.on-repeat",
            "reaction.no-skips"
        ]
    ]
}
