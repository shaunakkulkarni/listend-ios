//
//  ReactionTagSearchIndex.swift
//  Listend
//

import Foundation

nonisolated enum ReactionTagSearchMatchKind: String, Equatable, Sendable {
    case displayName
    case alias
    case category
    case definition
    case typo
}

nonisolated struct ReactionTagSearchResult: Identifiable, Equatable, Sendable {
    var id: String { tag.id }

    let tag: ReactionTagDefinition
    let matchKind: ReactionTagSearchMatchKind
    let matchedText: String
    let score: Int
}

nonisolated struct ReactionTagSearchIndex: Sendable {
    private nonisolated struct IndexedTag: Sendable {
        let tag: ReactionTagDefinition
        let displayKey: String
        let aliases: [(display: String, key: String)]
        let categoryDisplayName: String
        let categoryKey: String
        let definitionKey: String
    }

    private let entries: [IndexedTag]

    init(catalog: TaxonomyCatalog) {
        self.entries = catalog.reactions.tags.map { tag in
            let categoryDisplayName = tag.category.displayName
            return IndexedTag(
                tag: tag,
                displayKey: TagTextNormalizer.comparisonKey(tag.displayName),
                aliases: tag.aliases.map {
                    (display: $0, key: TagTextNormalizer.comparisonKey($0))
                },
                categoryDisplayName: categoryDisplayName,
                categoryKey: TagTextNormalizer.comparisonKey(categoryDisplayName),
                definitionKey: TagTextNormalizer.comparisonKey(tag.definition)
            )
        }
    }

    func search(_ query: String, limit: Int = 20) -> [ReactionTagSearchResult] {
        let queryKey = TagTextNormalizer.comparisonKey(query)
        let resultLimit = min(max(limit, 0), 20)

        guard !queryKey.isEmpty, resultLimit > 0 else {
            return []
        }

        return entries
            .compactMap { bestMatch(for: $0, queryKey: queryKey) }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }

                let leftDisplay = TagTextNormalizer.comparisonKey($0.tag.displayName)
                let rightDisplay = TagTextNormalizer.comparisonKey($1.tag.displayName)
                if leftDisplay != rightDisplay {
                    return leftDisplay < rightDisplay
                }

                return $0.tag.id < $1.tag.id
            }
            .prefix(resultLimit)
            .map { $0 }
    }

    private func bestMatch(
        for entry: IndexedTag,
        queryKey: String
    ) -> ReactionTagSearchResult? {
        var best: ReactionTagSearchResult?

        func consider(
            score: Int,
            kind: ReactionTagSearchMatchKind,
            matchedText: String
        ) {
            guard best == nil || score > (best?.score ?? 0) else {
                return
            }

            best = ReactionTagSearchResult(
                tag: entry.tag,
                matchKind: kind,
                matchedText: matchedText,
                score: score
            )
        }

        if entry.displayKey == queryKey {
            consider(score: 1_000, kind: .displayName, matchedText: entry.tag.displayName)
        } else if entry.displayKey.hasPrefix(queryKey) {
            consider(score: 900, kind: .displayName, matchedText: entry.tag.displayName)
        }

        for alias in entry.aliases {
            if alias.key == queryKey {
                consider(score: 850, kind: .alias, matchedText: alias.display)
            } else if alias.key.hasPrefix(queryKey) {
                consider(score: 800, kind: .alias, matchedText: alias.display)
            }
        }

        if containsWholePhrase(entry.displayKey, queryKey: queryKey) {
            consider(score: 700, kind: .displayName, matchedText: entry.tag.displayName)
        }

        for alias in entry.aliases where containsWholePhrase(alias.key, queryKey: queryKey) {
            consider(score: 650, kind: .alias, matchedText: alias.display)
        }

        if containsWholePhrase(entry.categoryKey, queryKey: queryKey) {
            consider(score: 600, kind: .category, matchedText: entry.categoryDisplayName)
        }

        if containsWholePhrase(entry.definitionKey, queryKey: queryKey) {
            consider(score: 550, kind: .definition, matchedText: entry.tag.definition)
        }

        if entry.displayKey.contains(queryKey) {
            consider(score: 500, kind: .displayName, matchedText: entry.tag.displayName)
        }

        for alias in entry.aliases where alias.key.contains(queryKey) {
            consider(score: 450, kind: .alias, matchedText: alias.display)
        }

        if entry.categoryKey.contains(queryKey) {
            consider(score: 400, kind: .category, matchedText: entry.categoryDisplayName)
        }

        if entry.definitionKey.contains(queryKey) {
            consider(score: 350, kind: .definition, matchedText: entry.tag.definition)
        }

        if best == nil,
           let typo = closestTypoMatch(in: entry, queryKey: queryKey) {
            consider(
                score: 200 - (typo.distance * 25),
                kind: .typo,
                matchedText: typo.display
            )
        }

        return best
    }

    private func containsWholePhrase(_ value: String, queryKey: String) -> Bool {
        let searchable = tokenized(value)
        let query = tokenized(queryKey)

        guard !query.isEmpty else {
            return false
        }

        return " \(searchable) ".contains(" \(query) ")
    }

    private func tokenized(_ value: String) -> String {
        value.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func closestTypoMatch(
        in entry: IndexedTag,
        queryKey: String
    ) -> (display: String, distance: Int)? {
        let queryLength = queryKey.count
        guard queryLength >= 4 else {
            return nil
        }

        let maximumDistance = queryLength >= 8 ? 2 : 1
        let candidates = [(entry.tag.displayName, entry.displayKey)]
            + entry.aliases.map { ($0.display, $0.key) }
        var closest: (display: String, distance: Int)?

        for (display, key) in candidates where key.count >= 4 {
            guard abs(key.count - queryLength) <= maximumDistance else {
                continue
            }

            let distance = editDistance(queryKey, key)
            guard distance <= maximumDistance else {
                continue
            }

            if closest == nil
                || distance < (closest?.distance ?? .max)
                || (distance == closest?.distance && display < (closest?.display ?? "")) {
                closest = (display, distance)
            }
        }

        return closest
    }

    private func editDistance(_ left: String, _ right: String) -> Int {
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)
        var previous = Array(0...rightCharacters.count)

        for (leftIndex, leftCharacter) in leftCharacters.enumerated() {
            var current = [leftIndex + 1]

            for (rightIndex, rightCharacter) in rightCharacters.enumerated() {
                current.append(
                    min(
                        current[rightIndex] + 1,
                        previous[rightIndex + 1] + 1,
                        previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                    )
                )
            }

            previous = current
        }

        return previous[rightCharacters.count]
    }
}
