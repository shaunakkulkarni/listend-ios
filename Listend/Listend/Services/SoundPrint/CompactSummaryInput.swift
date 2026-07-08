//
//  CompactSummaryInput.swift
//  Listend
//

struct CompactSummaryInput {
    let dimensions: [TasteDimension]
    let avoidanceSignals: [TasteAvoidanceSignal]
    let userFacingSignals: [String]
    let recentChanges: String?
    let tone: SoundPrintPersonaTone

    init(
        dimensions: [TasteDimension],
        avoidanceSignals: [TasteAvoidanceSignal],
        userFacingSignals: [String] = [],
        recentChanges: String? = nil,
        tone: SoundPrintPersonaTone = .balanced
    ) {
        self.dimensions = dimensions
        self.avoidanceSignals = avoidanceSignals
        self.userFacingSignals = userFacingSignals
        self.recentChanges = recentChanges
        self.tone = tone
    }
}
