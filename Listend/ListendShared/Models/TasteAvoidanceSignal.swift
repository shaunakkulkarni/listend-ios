//
//  TasteAvoidanceSignal.swift
//  Listend
//

import Foundation
import SwiftData

@Model
final class TasteAvoidanceSignal {
    var id: UUID
    var name: String
    var label: String
    var summary: String
    var strength: Double
    var confidence: Double
    var evidenceLogEntryIDsRawValue: String
    var updatedAt: Date

    var evidenceLogEntryIDs: [UUID] {
        get {
            (try? JSONDecoder().decode([UUID].self, from: Data(evidenceLogEntryIDsRawValue.utf8))) ?? []
        }
        set {
            evidenceLogEntryIDsRawValue = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        label: String,
        summary: String,
        strength: Double,
        confidence: Double,
        evidenceLogEntryIDs: [UUID] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.label = label
        self.summary = summary
        self.strength = strength
        self.confidence = confidence
        self.evidenceLogEntryIDsRawValue = (try? String(data: JSONEncoder().encode(evidenceLogEntryIDs), encoding: .utf8)) ?? "[]"
        self.updatedAt = updatedAt
    }
}
