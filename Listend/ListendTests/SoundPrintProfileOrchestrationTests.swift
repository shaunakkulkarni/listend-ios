//
//  SoundPrintProfileOrchestrationTests.swift
//  ListendTests
//

import Foundation
import SwiftData
import Testing
@testable import Listend

@Suite(.serialized)
@MainActor
struct SoundPrintProfileOrchestrationTests {
    @Test func signalsOnlyRebuildsSignalsWithoutGeneratingProse() async throws {
        resetRefreshPreference()
        let container = try makeContainer()
        let modelContext = container.mainContext
        insertLogs(in: modelContext, count: 5)
        try modelContext.save()
        let provider = RecordingSoundPrintProvider()

        try await SoundPrintProfileBuilder(provider: provider).rebuildProfile(
            in: modelContext,
            mode: .signalsOnly
        )

        #expect(provider.personaCallCount == 0)
        #expect(provider.compactSummaryCallCount == 0)
        #expect(try modelContext.fetchCount(FetchDescriptor<TasteDimension>()) > 0)
        #expect(try modelContext.fetchCount(FetchDescriptor<SoundPrintPersona>()) == 0)
    }

    @Test func signalsOnlyPreservesCurrentReflection() async throws {
        resetRefreshPreference()
        let container = try makeContainer()
        let modelContext = container.mainContext
        insertLogs(in: modelContext, count: 5)
        let existing = SoundPrintPersona(
            personaText: "Existing reflection remains stable.",
            logCountAtGeneration: 5,
            generationSource: .foundationModels
        )
        modelContext.insert(existing)
        try modelContext.save()
        let provider = RecordingSoundPrintProvider()

        try await SoundPrintProfileBuilder(provider: provider).rebuildProfile(
            in: modelContext,
            mode: .signalsOnly
        )

        let persona = try #require(modelContext.fetch(FetchDescriptor<SoundPrintPersona>()).first)
        #expect(persona.personaText == "Existing reflection remains stable.")
        #expect(persona.generationSource == .foundationModels)
        #expect(provider.personaCallCount == 0)
    }

    @Test func failedExplicitGenerationPreservesReflectionDirtyFlagAndShowsSafeError() async throws {
        resetRefreshPreference()
        let container = try makeContainer()
        let modelContext = container.mainContext
        insertLogs(in: modelContext, count: 5)
        modelContext.insert(
            SoundPrintPersona(
                personaText: "Existing reflection survives provider failure.",
                logCountAtGeneration: 5,
                generationSource: .foundationModels
            )
        )
        try modelContext.save()
        UserDefaults.standard.set(true, forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh)
        let provider = RecordingSoundPrintProvider()
        provider.personaFailure = .failedWithPrivateDiagnostic
        let coordinator = SoundPrintProfileRefreshCoordinator()

        await coordinator.generateReflection(in: modelContext, provider: provider)

        let persona = try #require(modelContext.fetch(FetchDescriptor<SoundPrintPersona>()).first)
        #expect(persona.personaText == "Existing reflection survives provider failure.")
        #expect(UserDefaults.standard.bool(forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh))
        #expect(coordinator.lastError == "SoundPrint could not create a reflection right now. Try again.")
        #expect(coordinator.lastError?.contains("private") == false)
    }

    @Test func successfulExplicitGenerationUsesBalancedToneAndClearsDirtyFlag() async throws {
        resetRefreshPreference()
        let container = try makeContainer()
        let modelContext = container.mainContext
        insertLogs(in: modelContext, count: 5)
        try modelContext.save()
        UserDefaults.standard.set(true, forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh)
        let provider = RecordingSoundPrintProvider()
        let coordinator = SoundPrintProfileRefreshCoordinator()

        await coordinator.generateReflection(in: modelContext, provider: provider)

        let persona = try #require(modelContext.fetch(FetchDescriptor<SoundPrintPersona>()).first)
        #expect(persona.personaText == RecordingSoundPrintProvider.validReflection)
        #expect(persona.logCountAtGeneration == 5)
        #expect(persona.tone == .balanced)
        #expect(provider.personaInputs == [.balanced])
        #expect(!UserDefaults.standard.bool(forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh))
        #expect(coordinator.lastError == nil)
    }

    @Test func createdLogSelectsSignalsOnlyWithoutMarkingHistoryDirty() async throws {
        resetRefreshPreference()
        let container = try makeContainer()
        let modelContext = container.mainContext
        let logs = insertLogs(in: modelContext, count: 5)
        modelContext.insert(
            SoundPrintPersona(personaText: "Current reflection.", logCountAtGeneration: 5)
        )
        try modelContext.save()
        let provider = RecordingSoundPrintProvider()

        await SoundPrintProfileRefreshCoordinator().processSavedLog(
            logs[0],
            mutation: .created,
            in: modelContext,
            provider: provider
        )

        #expect(provider.sentimentCallCount == 1)
        #expect(provider.personaCallCount == 0)
        #expect(!UserDefaults.standard.bool(forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh))
    }

    @Test func updatedAndDeletedLogsMarkExistingReflectionDirtyAndUseSignalsOnly() async throws {
        resetRefreshPreference()
        let container = try makeContainer()
        let modelContext = container.mainContext
        let logs = insertLogs(in: modelContext, count: 6)
        modelContext.insert(
            SoundPrintPersona(personaText: "Current reflection.", logCountAtGeneration: 5)
        )
        try modelContext.save()
        let provider = RecordingSoundPrintProvider()
        let coordinator = SoundPrintProfileRefreshCoordinator()

        await coordinator.processSavedLog(
            logs[0],
            mutation: .updated,
            in: modelContext,
            provider: provider
        )

        #expect(UserDefaults.standard.bool(forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh))
        #expect(provider.personaCallCount == 0)

        UserDefaults.standard.set(false, forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh)
        modelContext.delete(logs[5])
        try modelContext.save()
        await coordinator.processDeletedLog(in: modelContext, provider: provider)

        #expect(UserDefaults.standard.bool(forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh))
        #expect(provider.personaCallCount == 0)
    }

    @Test func signalsOnlyInvalidatesReflectionBelowThresholdAndClearsDirtyFlag() async throws {
        resetRefreshPreference()
        let container = try makeContainer()
        let modelContext = container.mainContext
        insertLogs(in: modelContext, count: 4)
        modelContext.insert(
            SoundPrintPersona(personaText: "No longer eligible.", logCountAtGeneration: 5)
        )
        try modelContext.save()
        UserDefaults.standard.set(true, forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh)
        let provider = RecordingSoundPrintProvider()

        try await SoundPrintProfileBuilder(provider: provider).rebuildProfile(
            in: modelContext,
            mode: .signalsOnly
        )

        #expect(try modelContext.fetchCount(FetchDescriptor<SoundPrintPersona>()) == 0)
        #expect(!UserDefaults.standard.bool(forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh))
        #expect(provider.personaCallCount == 0)
    }

    @Test func queuedExplicitGenerationOutranksSignalsOnly() async throws {
        resetRefreshPreference()
        let container = try makeContainer()
        let modelContext = container.mainContext
        let logs = insertLogs(in: modelContext, count: 5)
        try modelContext.save()
        let provider = RecordingSoundPrintProvider()
        provider.shouldPauseFirstExtraction = true
        let coordinator = SoundPrintProfileRefreshCoordinator()

        let signalTask = Task { @MainActor in
            await coordinator.processSavedLog(
                logs[0],
                mutation: .created,
                in: modelContext,
                provider: provider
            )
        }
        while provider.extractionCallCount == 0 {
            await Task.yield()
        }

        await coordinator.generateReflection(in: modelContext, provider: provider)
        provider.resumeExtraction()
        await signalTask.value

        #expect(provider.personaCallCount == 1)
        #expect(try modelContext.fetchCount(FetchDescriptor<SoundPrintPersona>()) == 1)
    }

    @Test func duplicateExplicitGenerationRequestsCoalesce() async throws {
        resetRefreshPreference()
        let container = try makeContainer()
        let modelContext = container.mainContext
        insertLogs(in: modelContext, count: 5)
        try modelContext.save()
        let provider = RecordingSoundPrintProvider()
        provider.shouldPauseFirstExtraction = true
        let coordinator = SoundPrintProfileRefreshCoordinator()

        let generationTask = Task { @MainActor in
            await coordinator.generateReflection(in: modelContext, provider: provider)
        }
        while provider.extractionCallCount == 0 {
            await Task.yield()
        }

        await coordinator.generateReflection(in: modelContext, provider: provider)
        await coordinator.generateReflection(in: modelContext, provider: provider)
        provider.resumeExtraction()
        await generationTask.value

        #expect(provider.personaCallCount == 1)
    }

    @Test func cancellationPreservesReflectionAndDoesNotSetErrorOrFallbackOutput() async throws {
        resetRefreshPreference()
        let container = try makeContainer()
        let modelContext = container.mainContext
        insertLogs(in: modelContext, count: 5)
        modelContext.insert(
            SoundPrintPersona(
                personaText: "Existing reflection survives cancellation.",
                logCountAtGeneration: 5,
                generationSource: .foundationModels
            )
        )
        try modelContext.save()
        UserDefaults.standard.set(true, forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh)
        let provider = RecordingSoundPrintProvider()
        provider.personaFailure = .cancelled
        let coordinator = SoundPrintProfileRefreshCoordinator()

        await coordinator.generateReflection(in: modelContext, provider: provider)

        let persona = try #require(modelContext.fetch(FetchDescriptor<SoundPrintPersona>()).first)
        #expect(persona.personaText == "Existing reflection survives cancellation.")
        #expect(persona.generationSource == .foundationModels)
        #expect(provider.personaCallCount == 1)
        #expect(provider.compactSummaryCallCount == 0)
        #expect(UserDefaults.standard.bool(forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh))
        #expect(coordinator.lastError == nil)
    }

    private func resetRefreshPreference() {
        UserDefaults.standard.set(false, forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = ListendModelSchema.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @discardableResult
    private func insertLogs(in modelContext: ModelContext, count: Int) -> [LogEntry] {
        (0..<count).map { index in
            let album = Album(
                appleMusicID: "reflection.orchestration.\(index)",
                title: index == 0 ? "Blonde" : "Album \(index)",
                artistName: index == 0 ? "Frank Ocean" : "Artist \(index)"
            )
            let log = LogEntry(
                album: album,
                rating: 4.5,
                reviewText: "Polished vocals and replay value make this rewarding.",
                tags: ["vocals", "repeat"],
                sentimentScore: 0.8,
                sentimentConfidence: 0.9,
                loggedAt: Date().addingTimeInterval(TimeInterval(-index * 60)),
                updatedAt: Date().addingTimeInterval(TimeInterval(-index * 60))
            )
            modelContext.insert(album)
            modelContext.insert(log)
            return log
        }
    }
}

private enum RecordingSoundPrintProviderFailure: Error {
    case failedWithPrivateDiagnostic
    case cancelled
}

private final class RecordingSoundPrintProvider: SoundPrintProvider {
    static let validReflection = "You tend to reward vocal focus. Blonde by Frank Ocean is the clearest example so far."

    var sentimentCallCount = 0
    var extractionCallCount = 0
    var personaCallCount = 0
    var compactSummaryCallCount = 0
    var personaInputs: [SoundPrintPersonaTone] = []
    var personaFailure: RecordingSoundPrintProviderFailure?
    var shouldPauseFirstExtraction = false

    private var extractionContinuation: CheckedContinuation<Void, Never>?

    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult {
        sentimentCallCount += 1
        return MockSoundPrintProvider.analyzeSentiment(input: input)
    }

    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult {
        extractionCallCount += 1

        if shouldPauseFirstExtraction {
            shouldPauseFirstExtraction = false
            await withCheckedContinuation { continuation in
                extractionContinuation = continuation
            }
        }

        return MockSoundPrintProvider.extractTasteSignals(input: input)
    }

    func generatePersona(input: PersonaInput) async throws -> PersonaResult {
        personaCallCount += 1
        personaInputs.append(input.tone)

        switch personaFailure {
        case .cancelled:
            throw CancellationError()
        case .failedWithPrivateDiagnostic:
            throw RecordingSoundPrintProviderFailure.failedWithPrivateDiagnostic
        case nil:
            return PersonaResult(text: Self.validReflection, generationSource: .localFallback)
        }
    }

    func generateCompactSummary(input: CompactSummaryInput) async throws -> CompactSummaryResult {
        compactSummaryCallCount += 1
        return MockSoundPrintProvider.generateCompactSummary(input: input)
    }

    func resumeExtraction() {
        extractionContinuation?.resume()
        extractionContinuation = nil
    }
}
