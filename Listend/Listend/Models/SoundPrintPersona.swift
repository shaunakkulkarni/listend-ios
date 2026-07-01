//
//  SoundPrintPersona.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

import Foundation
import SwiftData

@Model
final class SoundPrintPersona {
    var id: UUID
    var personaText: String
    var generatedAt: Date
    var logCountAtGeneration: Int
    var headline: String?
    var summaryText: String?
    var bulletsRawValue: String?

    var bullets: [String] {
        get {
            guard let bulletsRawValue else {
                return []
            }

            return (try? JSONDecoder().decode([String].self, from: Data(bulletsRawValue.utf8))) ?? []
        }
        set {
            guard !newValue.isEmpty else {
                bulletsRawValue = nil
                return
            }

            bulletsRawValue = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? nil
        }
    }

    init(
        id: UUID = UUID(),
        personaText: String,
        generatedAt: Date = Date(),
        logCountAtGeneration: Int,
        headline: String? = nil,
        summaryText: String? = nil,
        bullets: [String] = []
    ) {
        self.id = id
        self.personaText = personaText
        self.generatedAt = generatedAt
        self.logCountAtGeneration = logCountAtGeneration
        self.headline = headline
        self.summaryText = summaryText
        self.bulletsRawValue = bullets.isEmpty ? nil : (try? String(data: JSONEncoder().encode(bullets), encoding: .utf8))
    }
}
