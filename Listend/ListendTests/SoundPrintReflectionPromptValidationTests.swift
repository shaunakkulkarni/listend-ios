//
//  SoundPrintReflectionPromptValidationTests.swift
//  ListendTests
//

import Foundation
import Testing
@testable import Listend

struct SoundPrintReflectionPromptValidationTests {
    @Test func reflectionPromptUsesThePlainProseContract() {
        let instructions = SoundPrintPromptTemplates.personaInstructions(tone: .wrapped)
        let prompt = SoundPrintPromptTemplates.personaPrompt(
            totalLogCount: 5,
            averageRating: 4.4,
            topTasteDimensions: ["Vocal Focus"],
            avoidanceSignals: ["Skip-Heavy Albums"],
            topTags: ["vocals"],
            recentLogSummary: "Blonde by Frank Ocean, rating 5.0",
            evidenceSnippets: ["Sparse intimate vocals."],
            tone: .wrapped
        )

        #expect(instructions.localizedCaseInsensitiveContains("listening reflection"))
        #expect(instructions.localizedCaseInsensitiveContains("90 words"))
        #expect(instructions.localizedCaseInsensitiveContains("balanced voice"))
        #expect(prompt.localizedCaseInsensitiveContains("plain reflection prose"))
        #expect(prompt.contains("User-selected reactions or tags:"))
        #expect(!instructions.localizedCaseInsensitiveContains("json"))
    }

    @Test func validatorAcceptsAQualifiedGroundedReflection() {
        let outcome = SoundPrintOutputValidator.validatePersona(
            "In these logs, you respond to intimate vocals, and Blonde by Frank Ocean makes that pull clear. Your \"vocals\" reaction keeps the pattern modest so far.",
            context: .init(
                userFacingSignals: ["Blonde", "Frank Ocean", "vocals", "Sparse intimate vocals"],
                internalAnalysisLabels: ["Vocal Focus", "Skip-Heavy Albums"],
                logCount: 5
            )
        )

        #expect(outcome.isValid)
    }

    @Test func validatorRejectsOverLimitInternalGenericAndUngroundedReflections() {
        let longReflection = (["You", "Blonde"] + Array(repeating: "detail", count: 89)).joined(separator: " ")
        let internalLabelReflection = "In these logs, you reward Tracklist Patience, and Blonde is the clearest example so far."
        let internalKeyReflection = "In these logs, your skipHeavyAlbums signal conflicts with Blonde so far."
        let genericReflection = "You have eclectic taste, and Blonde confirms that your music taste is unique so far."
        let ungroundedReflection = "In these logs, you reward records with real staying power, and the pattern is still taking shape so far."
        let context = SoundPrintOutputValidator.PersonaValidationContext(
            userFacingSignals: ["Blonde", "Frank Ocean", "vocals"],
            internalAnalysisLabels: ["Tracklist Patience", "skipHeavyAlbums"],
            logCount: 5
        )

        #expect(!SoundPrintOutputValidator.validatePersona(longReflection, context: context).isValid)
        #expect(!SoundPrintOutputValidator.validatePersona(internalLabelReflection, context: context).isValid)
        #expect(!SoundPrintOutputValidator.validatePersona(internalKeyReflection, context: context).isValid)
        #expect(!SoundPrintOutputValidator.validatePersona(genericReflection, context: context).isValid)
        #expect(!SoundPrintOutputValidator.validatePersona(ungroundedReflection, context: context).isValid)
    }

    @Test func validatorRejectsPersonaUserAndProtocolLanguage() {
        let protocolLeak = "You can see the model prompt and validation schema in Blonde, so far."
        let personaLeak = "This persona says the user rewards Blonde by Frank Ocean, so far."
        let context = SoundPrintOutputValidator.PersonaValidationContext(
            userFacingSignals: ["Blonde", "Frank Ocean", "vocals"],
            logCount: 50
        )

        #expect(!SoundPrintOutputValidator.validatePersona(protocolLeak, context: context).isValid)
        #expect(!SoundPrintOutputValidator.validatePersona(personaLeak, context: context).isValid)
    }

    @Test func validatorRejectsUnsupportedAbsoluteFrequencyAndReplayClaims() {
        let absoluteFrequencyClaim = "In these logs, you always choose Blonde by Frank Ocean when you want intimate vocals."
        let replayClaim = "In these logs, you keep coming back to Blonde by Frank Ocean for intimate vocals."
        let context = SoundPrintOutputValidator.PersonaValidationContext(
            userFacingSignals: ["Blonde", "Frank Ocean", "intimate vocals"],
            logCount: 50
        )

        #expect(!SoundPrintOutputValidator.validatePersona(absoluteFrequencyClaim, context: context).isValid)
        #expect(!SoundPrintOutputValidator.validatePersona(replayClaim, context: context).isValid)

        let supportedReplay = SoundPrintOutputValidator.validatePersona(
            replayClaim,
            context: .init(
                userFacingSignals: ["Blonde", "Frank Ocean", "intimate vocals"],
                logCount: 5,
                supportsReplayBehaviorClaims: true
            )
        )
        #expect(supportedReplay.isValid)
    }

    @Test func validatorRejectsExcessClaimsAndParagraphs() {
        let fourClaims = "In these logs, you reward intimate vocals. Blonde makes that clear. Frank Ocean anchors the pattern. Careful pacing also matters so far."
        let threeParagraphs = "In these logs, you reward intimate vocals.\n\nBlonde makes that clear.\n\nFrank Ocean anchors the pattern so far."
        let context = SoundPrintOutputValidator.PersonaValidationContext(
            userFacingSignals: ["Blonde", "Frank Ocean", "intimate vocals"],
            logCount: 5
        )

        #expect(!SoundPrintOutputValidator.validatePersona(fourClaims, context: context).isValid)
        #expect(!SoundPrintOutputValidator.validatePersona(threeParagraphs, context: context).isValid)
    }

    @Test func mockFallbackProducesAValidBalancedReflection() async throws {
        let input = reflectionInput(tone: .wrapped)
        let result = try await MockSoundPrintProvider().generatePersona(input: input)
        let outcome = SoundPrintOutputValidator.validatePersona(
            result.text,
            context: .init(
                userFacingSignals: FoundationModelsSoundPrintValidator.userFacingSignals(from: input),
                internalAnalysisLabels: FoundationModelsSoundPrintValidator.internalAnalysisLabels(from: input),
                logCount: input.totalLogCount,
                tone: .balanced,
                supportsReplayBehaviorClaims: FoundationModelsSoundPrintValidator.supportsReplayBehaviorClaims(from: input)
            )
        )

        #expect(result.generationSource == .localFallback)
        #expect(result.text.normalizedSoundPrintWords.count <= SoundPrintOutputValidator.maximumPersonaWordCount)
        #expect(result.text.localizedCaseInsensitiveContains("Blonde"))
        #expect(outcome.isValid)
    }

    @Test func fallbackPersonaPreservesSourcesAndPropagatesCancellation() async throws {
        let input = reflectionInput()
        let primary = FallbackSoundPrintProvider(
            primary: ReflectionTestProvider(resultSource: .foundationModels),
            fallback: ReflectionTestProvider(resultSource: .localFallback)
        )
        let fallback = FallbackSoundPrintProvider(
            primary: ReflectionTestProvider(resultSource: .foundationModels, shouldFail: true),
            fallback: ReflectionTestProvider(resultSource: .localFallback)
        )
        let cancelling = FallbackSoundPrintProvider(
            primary: ReflectionTestProvider(resultSource: .foundationModels, shouldCancel: true),
            fallback: ReflectionTestProvider(resultSource: .localFallback)
        )

        let primaryResult = try await primary.generatePersona(input: input)
        let fallbackResult = try await fallback.generatePersona(input: input)

        #expect(primaryResult.generationSource == .foundationModels)
        #expect(fallbackResult.generationSource == .localFallback)

        do {
            _ = try await cancelling.generatePersona(input: input)
            Issue.record("Cancellation should propagate instead of invoking the fallback.")
        } catch is CancellationError {
            #expect(true)
        }
    }

    private func reflectionInput(tone: SoundPrintPersonaTone = .balanced) -> PersonaInput {
        PersonaInput(
            dimensions: [
                TasteDimension(
                    name: "vocalFocus",
                    label: "Vocal Focus",
                    weight: 0.9,
                    confidence: 0.8,
                    summary: "Vocal detail stands out."
                )
            ],
            recentLogs: [
                PersonaLogInput(
                    albumTitle: "Blonde",
                    artistName: "Frank Ocean",
                    rating: 5.0,
                    reviewSnippet: "Sparse intimate vocals that still feel huge.",
                    tags: ["vocals"],
                    isPositiveSignal: true,
                    favoriteTracks: ["Nights"]
                )
            ],
            totalLogCount: 5,
            topTags: ["vocals"],
            averageRating: 4.4,
            avoidanceSignals: ["Skip-Heavy Albums"],
            tone: tone
        )
    }
}

private struct ReflectionTestProvider: SoundPrintProvider {
    let resultSource: SoundPrintGenerationSource
    var shouldFail = false
    var shouldCancel = false

    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult {
        SentimentResult(score: 0.5, confidence: 0.8)
    }

    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult {
        TasteExtractionResult(signals: [], avoidanceSignals: [])
    }

    func generatePersona(input: PersonaInput) async throws -> PersonaResult {
        if shouldCancel {
            throw CancellationError()
        }

        if shouldFail {
            throw ReflectionTestError.failed
        }

        return PersonaResult(
            text: "In these logs, you respond to intimate vocals, and Blonde by Frank Ocean makes that pull clear. Your \"vocals\" reaction keeps the pattern modest so far.",
            generationSource: resultSource
        )
    }

    func generateCompactSummary(input: CompactSummaryInput) async throws -> CompactSummaryResult {
        CompactSummaryResult(headline: "Grounded reflection", summary: "Blonde keeps the pattern concrete.", bullets: ["Blonde", "Vocals", "So far"])
    }
}

private enum ReflectionTestError: Error {
    case failed
}
