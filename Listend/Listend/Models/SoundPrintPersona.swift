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

    init(
        id: UUID = UUID(),
        personaText: String,
        generatedAt: Date = Date(),
        logCountAtGeneration: Int
    ) {
        self.id = id
        self.personaText = personaText
        self.generatedAt = generatedAt
        self.logCountAtGeneration = logCountAtGeneration
    }
}
