//
//  SoundPrintProvider.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

protocol SoundPrintProvider {
    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult
    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult
    func generatePersona(input: PersonaInput) async throws -> PersonaResult
}
