//
//  SoundPrintProfileBuilder.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

import Foundation
import SwiftData

struct SoundPrintProfileBuilder {
    let provider: SoundPrintProvider

    init(provider: SoundPrintProvider = MockSoundPrintProvider()) {
        self.provider = provider
    }

    @MainActor
    func rebuildProfile(in modelContext: ModelContext) async throws {
        let existingEvidence = try modelContext.fetch(FetchDescriptor<TasteEvidence>())
        let existingDimensions = try modelContext.fetch(FetchDescriptor<TasteDimension>())

        for evidence in existingEvidence {
            modelContext.delete(evidence)
        }

        for dimension in existingDimensions {
            modelContext.delete(dimension)
        }

        let logs = try modelContext.fetch(FetchDescriptor<LogEntry>())
        var signalsByDimension: [String: [TasteSignal]] = [:]

        for log in logs where log.isPositiveSignal {
            guard let album = log.album else {
                continue
            }

            let extraction = try await provider.extractTasteSignals(
                input: TasteExtractionInput(
                    logID: log.id,
                    albumTitle: album.title,
                    artistName: album.artistName,
                    genreName: album.genreName,
                    releaseYear: album.releaseYear,
                    rating: log.rating,
                    reviewText: log.reviewText,
                    tags: log.tags,
                    sentimentScore: log.sentimentScore
                )
            )

            for signal in extraction.signals where signal.isPositiveEvidence {
                signalsByDimension[signal.dimensionName, default: []].append(signal)
                modelContext.insert(
                    TasteEvidence(
                        dimensionName: signal.dimensionName,
                        logEntryID: log.id,
                        snippet: signal.evidenceSnippet,
                        evidenceType: "reviewOrTag",
                        strength: signal.weight,
                        confidence: signal.confidence,
                        isPositiveEvidence: true
                    )
                )
            }
        }

        insertDimensions(from: signalsByDimension, in: modelContext)
        try modelContext.save()
        await refreshPersona(in: modelContext)
    }

    @MainActor
    private func insertDimensions(from signalsByDimension: [String: [TasteSignal]], in modelContext: ModelContext) {
        for (dimensionName, signals) in signalsByDimension {
            guard !signals.isEmpty else {
                continue
            }

            let weight = signals.map(\.weight).average.clamped(to: 0.0...1.0)
            let confidence = signals.map(\.confidence).average.clamped(to: 0.0...1.0)
            let representative = signals.sorted {
                if $0.weight == $1.weight {
                    return $0.label < $1.label
                }

                return $0.weight > $1.weight
            }[0]

            modelContext.insert(
                TasteDimension(
                    name: dimensionName,
                    label: representative.label,
                    weight: weight,
                    confidence: confidence,
                    summary: representative.summary
                )
            )
        }
    }

    @MainActor
    private func refreshPersona(in modelContext: ModelContext) async {
        do {
            let logs = try modelContext.fetch(FetchDescriptor<LogEntry>())
            let existingPersonas = try modelContext.fetch(FetchDescriptor<SoundPrintPersona>())

            guard logs.count >= 5 else {
                for persona in existingPersonas {
                    modelContext.delete(persona)
                }

                try modelContext.save()
                return
            }

            let dimensions = try modelContext.fetch(
                FetchDescriptor<TasteDimension>(
                    sortBy: [SortDescriptor(\.weight, order: .reverse)]
                )
            )
            let recentLogs = logs
                .sorted { $0.loggedAt > $1.loggedAt }
                .prefix(10)
                .compactMap(PersonaLogInput.init(log:))
            let topTags = topTags(from: logs)
            let averageRating = logs.isEmpty ? nil : logs.map(\.rating).average
            let result = try await provider.generatePersona(
                input: PersonaInput(
                    dimensions: dimensions,
                    recentLogs: Array(recentLogs),
                    totalLogCount: logs.count,
                    topTags: topTags,
                    averageRating: averageRating
                )
            )

            for persona in existingPersonas.dropFirst() {
                modelContext.delete(persona)
            }

            if let currentPersona = existingPersonas.first {
                currentPersona.personaText = result.text
                currentPersona.generatedAt = Date()
                currentPersona.logCountAtGeneration = logs.count
            } else {
                modelContext.insert(
                    SoundPrintPersona(
                        personaText: result.text,
                        logCountAtGeneration: logs.count
                    )
                )
            }

            try modelContext.save()
        } catch {
            return
        }
    }

    private func topTags(from logs: [LogEntry]) -> [String] {
        logs
            .flatMap(\.tags)
            .reduce(into: [String: Int]()) { counts, tag in
                counts[tag, default: 0] += 1
            }
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }

                return $0.value > $1.value
            }
            .prefix(3)
            .map(\.key)
    }
}

private extension PersonaLogInput {
    init?(log: LogEntry) {
        guard let album = log.album else {
            return nil
        }

        self.init(
            albumTitle: album.title,
            artistName: album.artistName,
            rating: log.rating,
            reviewSnippet: log.reviewText.trimmedPersonaSnippet,
            tags: log.tags,
            isPositiveSignal: log.isPositiveSignal
        )
    }
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else {
            return 0.0
        }

        return reduce(0.0, +) / Double(count)
    }
}

private extension String {
    var trimmedPersonaSnippet: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count > 120 else {
            return trimmed
        }

        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 120)
        return String(trimmed[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
