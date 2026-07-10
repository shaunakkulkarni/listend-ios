//
//  TasteDimension.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

import Foundation
import SwiftData

@Model
final class TasteDimension {
    var id: UUID
    var name: String
    var label: String
    var weight: Double
    var confidence: Double
    var summary: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        label: String,
        weight: Double,
        confidence: Double,
        summary: String,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.label = label
        self.weight = weight
        self.confidence = confidence
        self.summary = summary
        self.updatedAt = updatedAt
    }
}
