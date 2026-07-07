//
//  CompactSummaryInput.swift
//  Listend
//

struct CompactSummaryInput {
    let dimensions: [TasteDimension]
    let avoidanceSignals: [TasteAvoidanceSignal]
    let recentChanges: String?
    let tone: SoundPrintPersonaTone

    init(
        dimensions: [TasteDimension],
        avoidanceSignals: [TasteAvoidanceSignal],
        recentChanges: String? = nil,
        tone: SoundPrintPersonaTone = .balanced
    ) {
        self.dimensions = dimensions
        self.avoidanceSignals = avoidanceSignals
        self.recentChanges = recentChanges
        self.tone = tone
    }
}
