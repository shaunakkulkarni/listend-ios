//
//  TasteEvidence.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

import Foundation
import SwiftData

@Model
final class TasteEvidence {
    var id: UUID
    var dimensionName: String
    var logEntryID: UUID
    var snippet: String
    var evidenceType: String
    var strength: Double
    var confidence: Double
    var isPositiveEvidence: Bool

    init(
        id: UUID = UUID(),
        dimensionName: String,
        logEntryID: UUID,
        snippet: String,
        evidenceType: String,
        strength: Double,
        confidence: Double,
        isPositiveEvidence: Bool
    ) {
        self.id = id
        self.dimensionName = dimensionName
        self.logEntryID = logEntryID
        self.snippet = snippet
        self.evidenceType = evidenceType
        self.strength = strength
        self.confidence = confidence
        self.isPositiveEvidence = isPositiveEvidence
    }
}
