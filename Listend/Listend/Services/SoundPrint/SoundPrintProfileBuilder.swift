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
}

private extension Array where Element == Double {
    var average: Double {
        guard !isEmpty else {
            return 0.0
        }

        return reduce(0.0, +) / Double(count)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
