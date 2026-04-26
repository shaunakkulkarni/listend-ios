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
        let logs = try modelContext.fetch(FetchDescriptor<LogEntry>())
        let logInputs = logs.compactMap(SoundPrintLogInput.init(log:))
        var signalsByDimension: [String: [TasteSignal]] = [:]
        var pendingEvidence: [PendingTasteEvidence] = []

        for logInput in logInputs where logInput.isPositiveSignal {
            let extraction = try await provider.extractTasteSignals(
                input: TasteExtractionInput(
                    logID: logInput.logID,
                    albumTitle: logInput.albumTitle,
                    artistName: logInput.artistName,
                    genreName: logInput.genreName,
                    releaseYear: logInput.releaseYear,
                    rating: logInput.rating,
                    reviewText: logInput.reviewText,
                    tags: logInput.tags,
                    sentimentScore: logInput.sentimentScore
                )
            )

            for signal in extraction.signals where signal.isPositiveEvidence {
                signalsByDimension[signal.dimensionName, default: []].append(signal)
                pendingEvidence.append(
                    PendingTasteEvidence(
                        dimensionName: signal.dimensionName,
                        logEntryID: logInput.logID,
                        snippet: signal.evidenceSnippet,
                        strength: signal.weight,
                        confidence: signal.confidence
                    )
                )
            }
        }

        let pendingDimensions = makeDimensions(from: signalsByDimension)
        try replaceProfileData(
            dimensions: pendingDimensions,
            evidence: pendingEvidence,
            in: modelContext
        )
        try modelContext.save()
        await refreshPersona(in: modelContext, logs: logs, dimensions: pendingDimensions)
    }

    private func makeDimensions(from signalsByDimension: [String: [TasteSignal]]) -> [PendingTasteDimension] {
        signalsByDimension.compactMap { dimensionName, signals in
            guard !signals.isEmpty else {
                return nil
            }

            let weight = signals.map(\.weight).average.clamped(to: 0.0...1.0)
            let confidence = signals.map(\.confidence).average.clamped(to: 0.0...1.0)
            let representative = signals.sorted {
                if $0.weight == $1.weight {
                    return $0.label < $1.label
                }

                return $0.weight > $1.weight
            }[0]

            return PendingTasteDimension(
                name: dimensionName,
                label: representative.label,
                weight: weight,
                confidence: confidence,
                summary: representative.summary
            )
        }
        .sorted {
            if $0.weight == $1.weight {
                return $0.label < $1.label
            }

            return $0.weight > $1.weight
        }
    }

    @MainActor
    private func replaceProfileData(
        dimensions: [PendingTasteDimension],
        evidence: [PendingTasteEvidence],
        in modelContext: ModelContext
    ) throws {
        let existingEvidence = try modelContext.fetch(FetchDescriptor<TasteEvidence>())
        let existingDimensions = try modelContext.fetch(FetchDescriptor<TasteDimension>())

        for evidence in existingEvidence {
            modelContext.delete(evidence)
        }

        for dimension in existingDimensions {
            modelContext.delete(dimension)
        }

        for dimension in dimensions {
            modelContext.insert(
                TasteDimension(
                    name: dimension.name,
                    label: dimension.label,
                    weight: dimension.weight,
                    confidence: dimension.confidence,
                    summary: dimension.summary
                )
            )
        }

        for evidence in evidence {
            modelContext.insert(
                TasteEvidence(
                    dimensionName: evidence.dimensionName,
                    logEntryID: evidence.logEntryID,
                    snippet: evidence.snippet,
                    evidenceType: "reviewOrTag",
                    strength: evidence.strength,
                    confidence: evidence.confidence,
                    isPositiveEvidence: true
                )
            )
        }
    }

    @MainActor
    private func refreshPersona(
        in modelContext: ModelContext,
        logs: [LogEntry],
        dimensions pendingDimensions: [PendingTasteDimension]
    ) async {
        do {
            let existingPersonas = try modelContext.fetch(
                FetchDescriptor<SoundPrintPersona>(
                    sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
                )
            )

            guard logs.count >= 5 else {
                for persona in existingPersonas {
                    modelContext.delete(persona)
                }

                try modelContext.save()
                return
            }

            let recentLogs = logs
                .sorted { $0.loggedAt > $1.loggedAt }
                .prefix(10)
                .compactMap(PersonaLogInput.init(log:))
            let topTags = topTags(from: logs)
            let averageRating = logs.isEmpty ? nil : logs.map(\.rating).average
            let result = try await provider.generatePersona(
                input: PersonaInput(
                    dimensions: pendingDimensions.map(\.tasteDimension),
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

private struct SoundPrintLogInput {
    let logID: UUID
    let albumTitle: String
    let artistName: String
    let genreName: String?
    let releaseYear: Int?
    let rating: Double
    let reviewText: String
    let tags: [String]
    let sentimentScore: Double?
    let isPositiveSignal: Bool

    init?(log: LogEntry) {
        guard let album = log.album else {
            return nil
        }

        logID = log.id
        albumTitle = album.title
        artistName = album.artistName
        genreName = album.genreName
        releaseYear = album.releaseYear
        rating = log.rating
        reviewText = log.reviewText
        tags = log.tags
        sentimentScore = log.sentimentScore
        isPositiveSignal = log.isPositiveSignal
    }
}

private struct PendingTasteDimension {
    let name: String
    let label: String
    let weight: Double
    let confidence: Double
    let summary: String

    var tasteDimension: TasteDimension {
        TasteDimension(
            name: name,
            label: label,
            weight: weight,
            confidence: confidence,
            summary: summary
        )
    }
}

private struct PendingTasteEvidence {
    let dimensionName: String
    let logEntryID: UUID
    let snippet: String
    let strength: Double
    let confidence: Double
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
