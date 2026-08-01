//
//  SoundPrintProfileBuilder.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

import Foundation
import SwiftData

enum SoundPrintProfileBuildMode: Equatable {
    case signalsOnly
    case generateReflection
}

enum SoundPrintProfileBuildError: Error, Equatable {
    case insufficientLogs
    case invalidReflection
    case unavailable
}

struct SoundPrintProfileBuilder {
    let provider: SoundPrintProvider

    init(provider: SoundPrintProvider = MockSoundPrintProvider()) {
        self.provider = provider
    }

    @MainActor
    func rebuildProfile(
        in modelContext: ModelContext,
        mode: SoundPrintProfileBuildMode
    ) async throws {
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

        guard logs.count >= SoundPrintProfileThresholds.personaMinimumLogCount else {
            try invalidateReflection(in: modelContext)

            if mode == .generateReflection {
                throw SoundPrintProfileBuildError.insufficientLogs
            }

            return
        }

        switch mode {
        case .signalsOnly:
            try clearRefreshFlagWhenNoReflectionExists(in: modelContext)
        case .generateReflection:
            try await generateReflection(
                in: modelContext,
                logs: logs,
                dimensions: pendingDimensions,
                avoidanceSignals: pendingAvoidanceSignals
            )
        }
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
    private func invalidateReflection(in modelContext: ModelContext) throws {
        let existingPersonas = try modelContext.fetch(FetchDescriptor<SoundPrintPersona>())

        for persona in existingPersonas {
            modelContext.delete(persona)
        }

        if !existingPersonas.isEmpty {
            try modelContext.save()
        }

        UserDefaults.standard.set(false, forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh)
    }

    @MainActor
    private func clearRefreshFlagWhenNoReflectionExists(in modelContext: ModelContext) throws {
        let personaCount = try modelContext.fetchCount(FetchDescriptor<SoundPrintPersona>())
        if personaCount == 0 {
            UserDefaults.standard.set(false, forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh)
        }
    }

    @MainActor
    private func generateReflection(
        in modelContext: ModelContext,
        logs: [LogEntry],
        dimensions pendingDimensions: [PendingTasteDimension],
        avoidanceSignals pendingAvoidanceSignals: [PendingTasteAvoidanceSignal]
    ) async throws {
        let existingPersonas = try modelContext.fetch(
            FetchDescriptor<SoundPrintPersona>(
                sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
            )
        )
        let boundedDimensions = Array(pendingDimensions.prefix(5))
        let boundedAvoidanceSignals = Array(pendingAvoidanceSignals.prefix(3))
        let recentLogs = logs
            .sorted { $0.loggedAt > $1.loggedAt }
            .prefix(10)
            .compactMap(PersonaLogInput.init(log:))
        let tone: SoundPrintPersonaTone = .balanced
        let personaInput = PersonaInput(
            dimensions: boundedDimensions.map(\.tasteDimension),
            recentLogs: Array(recentLogs),
            totalLogCount: logs.count,
            topTags: topTags(from: logs),
            averageRating: logs.map(\.rating).average,
            avoidanceSignals: boundedAvoidanceSignals.map(\.label),
            tone: tone
        )
        let userFacingSignals = FoundationModelsSoundPrintValidator.userFacingSignals(from: personaInput)
        let result: PersonaResult

        do {
            result = try await provider.generatePersona(input: personaInput)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SoundPrintProfileBuildError.unavailable
        }

        let validationContext = SoundPrintOutputValidator.PersonaValidationContext(
            userFacingSignals: userFacingSignals,
            internalAnalysisLabels: FoundationModelsSoundPrintValidator.internalAnalysisLabels(from: personaInput),
            logCount: logs.count,
            tone: tone
        )

        // Defense in depth: every provider result passes the same local gate before
        // the current reflection is mutated or duplicate legacy rows are removed.
        guard SoundPrintOutputValidator.validatePersona(result.text, context: validationContext).isValid else {
            throw SoundPrintProfileBuildError.invalidReflection
        }

        let compactSummary = try await optionalCompactSummary(
            dimensions: boundedDimensions,
            avoidanceSignals: boundedAvoidanceSignals,
            userFacingSignals: userFacingSignals,
            tone: tone
        )

        for persona in existingPersonas.dropFirst() {
            modelContext.delete(persona)
        }

        let currentPersona: SoundPrintPersona
        if let existing = existingPersonas.first {
            existing.personaText = result.text
            existing.generatedAt = Date()
            existing.logCountAtGeneration = logs.count
            existing.generationSource = result.generationSource
            existing.tone = tone
            currentPersona = existing
        } else {
            let inserted = SoundPrintPersona(
                personaText: result.text,
                logCountAtGeneration: logs.count,
                generationSource: result.generationSource,
                tone: tone
            )
            modelContext.insert(inserted)
            currentPersona = inserted
        }

        currentPersona.headline = compactSummary?.headline
        currentPersona.summaryText = compactSummary?.summary
        currentPersona.bullets = compactSummary?.bullets ?? []

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        UserDefaults.standard.set(false, forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh)
    }

    private func optionalCompactSummary(
        dimensions pendingDimensions: [PendingTasteDimension],
        avoidanceSignals pendingAvoidanceSignals: [PendingTasteAvoidanceSignal],
        userFacingSignals: [String],
        tone: SoundPrintPersonaTone
    ) async throws -> CompactSummaryResult? {
        do {
            let input = CompactSummaryInput(
                dimensions: pendingDimensions.map(\.tasteDimension),
                avoidanceSignals: pendingAvoidanceSignals.map(\.tasteAvoidanceSignal),
                userFacingSignals: userFacingSignals,
                tone: tone
            )
            let result = try await provider.generateCompactSummary(input: input)

            guard SoundPrintOutputValidator.validateCompactSummary(
                headline: result.headline,
                summary: result.summary,
                bullets: result.bullets,
                tone: tone,
                userFacingSignals: FoundationModelsSoundPrintValidator.userFacingSignals(from: input),
                internalAnalysisLabels: FoundationModelsSoundPrintValidator.internalAnalysisLabels(from: input)
            ).isValid else {
                return nil
            }

            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return nil
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
