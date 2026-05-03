//
//  FallbackSoundPrintProvider.swift
//  Listend
//
//  Created by Codex on 5/3/26.
//

struct FallbackSoundPrintProvider: SoundPrintProvider {
    let primary: SoundPrintProvider
    let fallback: SoundPrintProvider

    init(
        primary: SoundPrintProvider = FoundationModelsSoundPrintProvider(),
        fallback: SoundPrintProvider = MockSoundPrintProvider()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult {
        do {
            return try await primary.analyzeSentiment(input: input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.analyzeSentiment(input: input)
        }
    }

    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult {
        do {
            return try await primary.extractTasteSignals(input: input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.extractTasteSignals(input: input)
        }
    }

    func generatePersona(input: PersonaInput) async throws -> PersonaResult {
        do {
            return try await primary.generatePersona(input: input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.generatePersona(input: input)
        }
    }
}
