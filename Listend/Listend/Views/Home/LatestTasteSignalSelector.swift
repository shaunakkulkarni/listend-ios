//
//  LatestTasteSignalSelector.swift
//  Listend
//

import Foundation

struct LatestTasteSignal: Equatable {
    let dimensionName: String
    let displayLabel: String
}

enum LatestTasteSignalSelector {
    static func hasFreshProfile(
        logUpdatedAt: Date,
        profileUpdatedAt: Date?
    ) -> Bool {
        guard let profileUpdatedAt else {
            return false
        }

        return profileUpdatedAt >= logUpdatedAt
    }

    static func select(
        latestLogID: UUID?,
        evidence: [TasteEvidence],
        dimensions: [TasteDimension],
        limit: Int = 2
    ) -> [LatestTasteSignal] {
        guard let latestLogID else {
            return []
        }

        let resultLimit = min(max(limit, 0), 2)
        guard resultLimit > 0 else {
            return []
        }

        let displayLabelByDimensionName = dimensions.reduce(into: [String: String]()) { result, dimension in
            let displayLabel = dimension.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayLabel.isEmpty else {
                return
            }

            if let existingLabel = result[dimension.name] {
                result[dimension.name] = min(existingLabel, displayLabel)
            } else {
                result[dimension.name] = displayLabel
            }
        }

        let rankedEvidence = evidence
            .filter { $0.logEntryID == latestLogID && $0.isPositiveEvidence }
            .sorted(by: ranksBefore)

        var selectedSignals: [LatestTasteSignal] = []
        var selectedLabels = Set<String>()

        for item in rankedEvidence {
            guard let displayLabel = displayLabelByDimensionName[item.dimensionName],
                  selectedLabels.insert(displayLabel).inserted else {
                continue
            }

            selectedSignals.append(
                LatestTasteSignal(
                    dimensionName: item.dimensionName,
                    displayLabel: displayLabel
                )
            )

            if selectedSignals.count == resultLimit {
                break
            }
        }

        return selectedSignals
    }

    private static func ranksBefore(_ lhs: TasteEvidence, _ rhs: TasteEvidence) -> Bool {
        if lhs.strength != rhs.strength {
            return lhs.strength > rhs.strength
        }

        if lhs.confidence != rhs.confidence {
            return lhs.confidence > rhs.confidence
        }

        let lhsText = stableText(for: lhs)
        let rhsText = stableText(for: rhs)
        return lhsText < rhsText
    }

    private static func stableText(for evidence: TasteEvidence) -> String {
        [
            evidence.dimensionName,
            evidence.snippet,
            evidence.evidenceType,
            evidence.id.uuidString
        ].joined(separator: "\u{0}")
    }
}
