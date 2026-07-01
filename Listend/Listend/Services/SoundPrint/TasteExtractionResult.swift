//
//  TasteExtractionResult.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

struct TasteExtractionResult {
    let signals: [TasteSignal]
    let avoidanceSignals: [AvoidanceSignal]

    init(signals: [TasteSignal], avoidanceSignals: [AvoidanceSignal] = []) {
        self.signals = signals
        self.avoidanceSignals = avoidanceSignals
    }
}
