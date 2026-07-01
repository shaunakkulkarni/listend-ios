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
        var avoidanceSignalsByCategory: [String: [AvoidanceSignal]] = [:]
        var avoidanceLogIDsByCategory: [String: Set<UUID>] = [:]

        for logInput in logInputs {
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
                    sentimentScore: logInput.sentimentScore,
                    favoriteTracks: logInput.favoriteTracks,
                    skipTracks: logInput.skipTracks,
                    standoutMoment: logInput.standoutMoment,
                    existingDimensions: Array(signalsByDimension.keys).sorted()
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

            for avoidanceSignal in extraction.avoidanceSignals {
                avoidanceSignalsByCategory[avoidanceSignal.signalName, default: []].append(avoidanceSignal)
                avoidanceLogIDsByCategory[avoidanceSignal.signalName, default: []].insert(logInput.logID)
            }
        }

        let pendingDimensions = makeDimensions(from: signalsByDimension)
        let pendingAvoidanceSignals = makeAvoidanceSignals(
            from: avoidanceSignalsByCategory,
            logIDsByCategory: avoidanceLogIDsByCategory
        )

        try replaceProfileData(
            dimensions: pendingDimensions,
            evidence: pendingEvidence,
            avoidanceSignals: pendingAvoidanceSignals,
            in: modelContext
        )
        try modelContext.save()
        await refreshPersona(
            in: modelContext,
            logs: logs,
            dimensions: pendingDimensions,
            avoidanceSignals: pendingAvoidanceSignals
        )
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

    private func makeAvoidanceSignals(
        from signalsByCategory: [String: [AvoidanceSignal]],
        logIDsByCategory: [String: Set<UUID>]
    ) -> [PendingTasteAvoidanceSignal] {
        signalsByCategory.compactMap { signalName, signals in
            guard !signals.isEmpty else {
                return nil
            }

            let strength = signals.map(\.strength).average.clamped(to: 0.0...1.0)
            let confidence = signals.map(\.confidence).average.clamped(to: 0.0...1.0)
            let representative = signals.sorted {
                if $0.strength == $1.strength {
                    return $0.label < $1.label
                }

                return $0.strength > $1.strength
            }[0]

            return PendingTasteAvoidanceSignal(
                name: signalName,
                label: representative.label,
                summary: representative.summary,
                strength: strength,
                confidence: confidence,
                evidenceLogEntryIDs: Array(logIDsByCategory[signalName] ?? [])
            )
        }
        .sorted {
            if $0.strength == $1.strength {
                return $0.label < $1.label
            }

            return $0.strength > $1.strength
        }
    }

    @MainActor
    private func replaceProfileData(
        dimensions: [PendingTasteDimension],
        evidence: [PendingTasteEvidence],
        avoidanceSignals: [PendingTasteAvoidanceSignal],
        in modelContext: ModelContext
    ) throws {
        let existingEvidence = try modelContext.fetch(FetchDescriptor<TasteEvidence>())
        let existingDimensions = try modelContext.fetch(FetchDescriptor<TasteDimension>())
        let existingAvoidanceSignals = try modelContext.fetch(FetchDescriptor<TasteAvoidanceSignal>())

        for evidence in existingEvidence {
            modelContext.delete(evidence)
        }

        for dimension in existingDimensions {
            modelContext.delete(dimension)
        }

        for avoidanceSignal in existingAvoidanceSignals {
            modelContext.delete(avoidanceSignal)
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

        for avoidanceSignal in avoidanceSignals {
            modelContext.insert(
                TasteAvoidanceSignal(
                    name: avoidanceSignal.name,
                    label: avoidanceSignal.label,
                    summary: avoidanceSignal.summary,
                    strength: avoidanceSignal.strength,
                    confidence: avoidanceSignal.confidence,
                    evidenceLogEntryIDs: avoidanceSignal.evidenceLogEntryIDs
                )
            )
        }
    }

    @MainActor
    private func refreshPersona(
        in modelContext: ModelContext,
        logs: [LogEntry],
        dimensions pendingDimensions: [PendingTasteDimension],
        avoidanceSignals pendingAvoidanceSignals: [PendingTasteAvoidanceSignal]
    ) async {
        do {
            let existingPersonas = try modelContext.fetch(
                FetchDescriptor<SoundPrintPersona>(
                    sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
                )
            )

            guard logs.count >= SoundPrintProfileThresholds.personaMinimumLogCount else {
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
            let avoidanceLabels = pendingAvoidanceSignals.map(\.label)
            let result = try await provider.generatePersona(
                input: PersonaInput(
                    dimensions: pendingDimensions.map(\.tasteDimension),
                    recentLogs: Array(recentLogs),
                    totalLogCount: logs.count,
                    topTags: topTags,
                    averageRating: averageRating,
                    avoidanceSignals: avoidanceLabels
                )
            )

            let validationContext = SoundPrintOutputValidator.PersonaValidationContext(
                concreteSignals: pendingDimensions.map(\.label)
                    + topTags
                    + recentLogs.map(\.albumTitle)
                    + recentLogs.map(\.artistName)
                    + avoidanceLabels,
                logCount: logs.count
            )

            // Defense in depth: even a provider that returns a technically-successful
            // PersonaResult must still pass the same always-on local gate before we persist it.
            guard SoundPrintOutputValidator.validatePersona(result.text, context: validationContext).isValid else {
                return
            }

            for persona in existingPersonas.dropFirst() {
                modelContext.delete(persona)
            }

            let currentPersona: SoundPrintPersona
            if let existing = existingPersonas.first {
                existing.personaText = result.text
                existing.generatedAt = Date()
                existing.logCountAtGeneration = logs.count
                currentPersona = existing
            } else {
                let inserted = SoundPrintPersona(personaText: result.text, logCountAtGeneration: logs.count)
                modelContext.insert(inserted)
                currentPersona = inserted
            }

            try modelContext.save()

            // Compact summary generation is independent of persona persistence: a failure or
            // invalid result here must not roll back the persona update that already succeeded.
            await refreshCompactSummary(
                for: currentPersona,
                in: modelContext,
                dimensions: pendingDimensions,
                avoidanceSignals: pendingAvoidanceSignals
            )
        } catch {
            return
        }
    }

    @MainActor
    private func refreshCompactSummary(
        for persona: SoundPrintPersona,
        in modelContext: ModelContext,
        dimensions pendingDimensions: [PendingTasteDimension],
        avoidanceSignals pendingAvoidanceSignals: [PendingTasteAvoidanceSignal]
    ) async {
        do {
            let result = try await provider.generateCompactSummary(
                input: CompactSummaryInput(
                    dimensions: pendingDimensions.map(\.tasteDimension),
                    avoidanceSignals: pendingAvoidanceSignals.map(\.tasteAvoidanceSignal)
                )
            )

            guard SoundPrintOutputValidator.validateCompactSummary(
                headline: result.headline,
                summary: result.summary,
                bullets: result.bullets
            ).isValid else {
                return
            }

            persona.headline = result.headline
            persona.summaryText = result.summary
            persona.bullets = result.bullets
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
    let favoriteTracks: [String]
    let skipTracks: [String]
    let standoutMoment: String?

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
        favoriteTracks = log.favoriteTracks
        skipTracks = log.skipTracks
        standoutMoment = log.normalizedStandoutMoment
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

private struct PendingTasteAvoidanceSignal {
    let name: String
    let label: String
    let summary: String
    let strength: Double
    let confidence: Double
    let evidenceLogEntryIDs: [UUID]

    var tasteAvoidanceSignal: TasteAvoidanceSignal {
        TasteAvoidanceSignal(
            name: name,
            label: label,
            summary: summary,
            strength: strength,
            confidence: confidence,
            evidenceLogEntryIDs: evidenceLogEntryIDs
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
            isPositiveSignal: log.isPositiveSignal,
            favoriteTracks: log.favoriteTracks,
            hasStandoutMoment: log.normalizedStandoutMoment != nil
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
