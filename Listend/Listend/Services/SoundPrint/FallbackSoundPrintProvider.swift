//
//  FallbackSoundPrintProvider.swift
//  Listend
//
//  Created by Codex on 5/3/26.
//

import os

/// Tries the primary (FoundationModels) provider and, on any failure other than
/// cancellation, recovers with the deterministic local fallback so logging and
/// SoundPrint are never blocked by an AI failure. Fallback results carry the
/// `.localFallback` source — never `.unavailable`.
struct FallbackSoundPrintProvider: SoundPrintProvider {
    let primary: SoundPrintProvider
    let fallback: SoundPrintProvider
    private static let logger = Logger(subsystem: "com.shaunakkulkarni.Listend", category: "SoundPrint")

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
            Self.logger.error("SoundPrint sentiment primary failed; using local fallback: \(String(describing: error), privacy: .public)")
            return try await fallback.analyzeSentiment(input: input)
        }
    }

    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult {
        do {
            return try await primary.extractTasteSignals(input: input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("SoundPrint extraction primary failed; using local fallback: \(String(describing: error), privacy: .public)")
            return try await fallback.extractTasteSignals(input: input)
        }
    }

    func generatePersona(input: PersonaInput) async throws -> PersonaResult {
        do {
            return try await primary.generatePersona(input: input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("SoundPrint persona primary failed; using local fallback: \(String(describing: error), privacy: .public)")
            return try await fallback.generatePersona(input: input)
        }
    }

    func generateCompactSummary(input: CompactSummaryInput) async throws -> CompactSummaryResult {
        do {
            return try await primary.generateCompactSummary(input: input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Self.logger.error("SoundPrint compact summary primary failed; using local fallback: \(String(describing: error), privacy: .public)")
            return try await fallback.generateCompactSummary(input: input)
        }
    }
}
