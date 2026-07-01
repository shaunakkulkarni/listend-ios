//
//  CompactSummaryInput.swift
//  Listend
//

struct CompactSummaryInput {
    let dimensions: [TasteDimension]
    let avoidanceSignals: [TasteAvoidanceSignal]
    let recentChanges: String?

    init(
        dimensions: [TasteDimension],
        avoidanceSignals: [TasteAvoidanceSignal],
        recentChanges: String? = nil
    ) {
        self.dimensions = dimensions
        self.avoidanceSignals = avoidanceSignals
        self.recentChanges = recentChanges
    }
}
