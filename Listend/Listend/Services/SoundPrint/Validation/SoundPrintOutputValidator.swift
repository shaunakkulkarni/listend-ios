//
//  SoundPrintOutputValidator.swift
//  Listend
//
//  Pure-Swift quality gate for SoundPrint persona/summary text. Has no dependency
//  on FoundationModels so it runs identically for every provider (Mock, FM, Fallback)
//  and is the one place banned language / length rules are enforced.
//

import Foundation

enum SoundPrintOutputValidator {
    struct PersonaValidationContext {
        let userFacingSignals: [String]
        let internalAnalysisLabels: [String]
        let logCount: Int
        let tone: SoundPrintPersonaTone
        let supportsReplayBehaviorClaims: Bool

        init(
            userFacingSignals: [String],
            internalAnalysisLabels: [String] = [],
            logCount: Int = Int.max,
            tone: SoundPrintPersonaTone = .balanced,
            supportsReplayBehaviorClaims: Bool = false
        ) {
            self.userFacingSignals = userFacingSignals
            self.internalAnalysisLabels = internalAnalysisLabels
            self.logCount = logCount
            self.tone = tone
            self.supportsReplayBehaviorClaims = supportsReplayBehaviorClaims
        }

        init(
            concreteSignals: [String],
            logCount: Int = Int.max,
            tone: SoundPrintPersonaTone = .balanced,
            supportsReplayBehaviorClaims: Bool = false
        ) {
            self.userFacingSignals = concreteSignals
            self.internalAnalysisLabels = []
            self.logCount = logCount
            self.tone = tone
            self.supportsReplayBehaviorClaims = supportsReplayBehaviorClaims
        }
    }

    enum ValidationOutcome: Equatable {
        case valid
        case invalid(reasons: [String])

        var isValid: Bool {
            if case .valid = self {
                return true
            }

            return false
        }
    }

    static let minimumPersonaCharacterCount = 40
    static let maximumPersonaWordCount = 90
    static let maximumPersonaParagraphCount = 2
    static let maximumPersonaClaimCount = 3

    static let requiredSummarySentenceCount = 1
    static let requiredBulletCount = 3

    /// Phrases banned in every tone: vague filler and identity-flattery that say
    /// nothing regardless of voice.
    static let coreBannedPhrases: [String] = [
        "eclectic taste", "eclectic",
        "sonic journey", "sonic",
        "soundscape",
        "genre-bending",
        "masterpiece",
        "connoisseur",
        "tastemaker",
        "explorer",
        "curator",
        "audiophile",
        "soundtrack to your life",
        "wide range of genres",
        "something for everyone",
        "diverse taste",
        "varied taste",
        "diverse",
        "unique"
    ]

    /// Cliché-but-charming recap vocabulary: additionally banned in Analyst and
    /// Balanced, but part of the bit in Wrapped.
    static let playfulPhrases: [String] = [
        "vibes",
        "immaculate vibes",
        "journey",
        "emotional rollercoaster",
        "hidden gem",
        "you contain multitudes",
        "your taste knows no bounds"
    ]

    /// The strictest list (all tones' bans combined). Kept for callers that don't
    /// have a tone in hand.
    static let bannedPhrases: [String] = coreBannedPhrases + playfulPhrases

    static func bannedPhrases(for tone: SoundPrintPersonaTone) -> [String] {
        tone == .wrapped ? coreBannedPhrases : coreBannedPhrases + playfulPhrases
    }

    /// Words that only ever appear when a model is talking *about* the persona
    /// text instead of writing it — critique leakage. Matched on word boundaries
    /// so "personal"/"critical" don't false-positive.
    private static let metaCommentaryWords: Set<String> = [
        "persona", "personas", "prompt", "prompts", "schema", "schemas",
        "model", "models", "validation", "validated", "validator", "protocol",
        "instruction", "instructions", "rewrite", "critic", "critique", "unsupported", "conflates"
    ]

    private static let metaCommentaryPhrases: [String] = [
        "the user",
        "this text",
        "language model",
        "foundation models",
        "apple intelligence",
        "as an ai",
        "i am an ai"
    ]

    /// A persona is a holistic cross-log summary, never anchored to one album on
    /// screen — so an unnamed "this/that album" is always a dangling, ambiguous
    /// reference rather than a legitimate grounded claim.
    private static let vagueAlbumReferencePhrases: [String] = [
        "this album",
        "that album"
    ]

    private static let overconfidentPhrases: [String] = [
        "always",
        "never",
        "definitely",
        "obsessed with",
        "consistently proves",
        "your favorite genre is"
    ]

    /// Reject absolute-frequency language, and allow replay behavior only when
    /// a supplied reaction or review phrase explicitly supports it.
    private static let unsupportedFrequencyPhrases: [String] = [
        "always",
        "never",
        "every time",
        "each time",
        "all the time",
        "constantly",
        "without fail",
        "repeatedly",
        "your favorite genre is"
    ]

    private static let replayBehaviorPhrases: [String] = [
        "on repeat",
        "in rotation",
        "keep coming back",
        "keep returning",
        "come back to",
        "coming back to",
        "comes back to",
        "returns to",
        "replay",
        "replays",
        "revisit",
        "revisits"
    ]

    private static let limitedEvidenceQualifiers: [String] = [
        "so far",
        "in these logs",
        "from these logs",
        "across these logs",
        "based on these logs",
        "lately",
        "still forming",
        "still taking shape"
    ]

    private static func overconfidentPhrases(for tone: SoundPrintPersonaTone) -> [String] {
        switch tone {
        case .wrapped:
            // "You were obsessed with Blonde this year" is the genre's idiom.
            return overconfidentPhrases.filter { $0 != "obsessed with" }
        case .analyst, .balanced:
            return overconfidentPhrases
        }
    }

    /// Log count below which overconfident language is rejected. Analyst never
    /// overclaims, regardless of how much evidence exists.
    private static func overconfidenceLogCountThreshold(for tone: SoundPrintPersonaTone) -> Int {
        tone == .analyst ? Int.max : 10
    }

    static func validatePersona(_ text: String, context: PersonaValidationContext) -> ValidationOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .invalid(reasons: ["empty output"])
        }

        var reasons: [String] = []
        let normalized = trimmed.normalizedSoundPrintText
        let words = trimmed.normalizedSoundPrintWords

        reasons.append(contentsOf: bannedPhraseReasons(in: normalized, tone: context.tone))
        reasons.append(contentsOf: metaCommentaryReasons(in: normalized, words: words))
        reasons.append(contentsOf: vagueAlbumReferenceReasons(in: normalized))
        reasons.append(contentsOf: unsupportedFrequencyReasons(in: normalized))
        if !context.supportsReplayBehaviorClaims {
            reasons.append(contentsOf: unsupportedReplayReasons(in: normalized))
        }
        reasons.append(contentsOf: internalAnalysisLabelReasons(
            in: normalized,
            internalAnalysisLabels: context.internalAnalysisLabels,
            userFacingSignals: context.userFacingSignals
        ))

        if !words.contains(where: { $0 == "you" || $0 == "your" || $0 == "yours" }) {
            reasons.append("not written in second person")
        }

        if normalized.hasPrefix("you are") {
            reasons.append("starts with a \"You are...\" opener")
        }

        if trimmed.count < minimumPersonaCharacterCount {
            reasons.append("too short")
        }

        if words.count > maximumPersonaWordCount {
            reasons.append("too long: \(words.count) words (maximum \(maximumPersonaWordCount))")
        }

        if trimmed.soundPrintParagraphs.count > maximumPersonaParagraphCount {
            reasons.append("too many paragraphs: \(trimmed.soundPrintParagraphs.count) (maximum \(maximumPersonaParagraphCount))")
        }

        if trimmed.soundPrintSentences.count > maximumPersonaClaimCount {
            reasons.append("too many substantive claims: \(trimmed.soundPrintSentences.count) (maximum \(maximumPersonaClaimCount))")
        }

        if !containsConcreteSignal(normalized, concreteSignals: context.userFacingSignals) {
            reasons.append("no concrete signal referenced (generic filler)")
        }

        if context.logCount < 10,
           !limitedEvidenceQualifiers.contains(where: { normalized.containsNormalizedSoundPrintPhrase($0) }) {
            reasons.append("limited evidence is not qualified")
        }

        if context.logCount < overconfidenceLogCountThreshold(for: context.tone) {
            reasons.append(contentsOf: overconfidenceReasons(in: normalized, tone: context.tone))
        }

        return reasons.isEmpty ? .valid : .invalid(reasons: reasons)
    }

    static func isPersonaValid(
        _ text: String,
        userFacingSignals: [String],
        internalAnalysisLabels: [String] = [],
        logCount: Int = Int.max,
        tone: SoundPrintPersonaTone = .balanced,
        supportsReplayBehaviorClaims: Bool = false
    ) -> Bool {
        validatePersona(
            text,
            context: PersonaValidationContext(
                userFacingSignals: userFacingSignals,
                internalAnalysisLabels: internalAnalysisLabels,
                logCount: logCount,
                tone: tone,
                supportsReplayBehaviorClaims: supportsReplayBehaviorClaims
            )
        ).isValid
    }

    static func isPersonaValid(
        _ text: String,
        concreteSignals: [String],
        logCount: Int = Int.max,
        tone: SoundPrintPersonaTone = .balanced,
        supportsReplayBehaviorClaims: Bool = false
    ) -> Bool {
        isPersonaValid(
            text,
            userFacingSignals: concreteSignals,
            logCount: logCount,
            tone: tone,
            supportsReplayBehaviorClaims: supportsReplayBehaviorClaims
        )
    }

    static func validateCompactSummary(
        headline: String,
        summary: String,
        bullets: [String],
        tone: SoundPrintPersonaTone = .balanced,
        userFacingSignals: [String] = [],
        internalAnalysisLabels: [String] = []
    ) -> ValidationOutcome {
        var reasons: [String] = []

        let trimmedHeadline = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBullets = bullets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        if trimmedHeadline.isEmpty {
            reasons.append("empty headline")
        } else {
            reasons.append(contentsOf: bannedPhraseReasons(in: trimmedHeadline.normalizedSoundPrintText, tone: tone, context: "headline"))
        }

        if trimmedSummary.isEmpty {
            reasons.append("empty summary")
        } else {
            let summarySentenceCount = trimmedSummary.soundPrintSentences.count
            if summarySentenceCount != requiredSummarySentenceCount {
                reasons.append("expected \(requiredSummarySentenceCount) summary sentence, found \(summarySentenceCount)")
            }
            reasons.append(contentsOf: bannedPhraseReasons(in: trimmedSummary.normalizedSoundPrintText, tone: tone, context: "summary"))
        }

        let nonEmptyBullets = trimmedBullets.filter { !$0.isEmpty }
        if nonEmptyBullets.count != requiredBulletCount {
            reasons.append("expected \(requiredBulletCount) bullets, found \(nonEmptyBullets.count)")
        }

        for bullet in nonEmptyBullets {
            reasons.append(contentsOf: bannedPhraseReasons(in: bullet.normalizedSoundPrintText, tone: tone, context: "bullet"))
        }

        let combined = ([trimmedHeadline, trimmedSummary] + trimmedBullets)
            .joined(separator: " ")
            .normalizedSoundPrintText
        reasons.append(contentsOf: internalAnalysisLabelReasons(
            in: combined,
            internalAnalysisLabels: internalAnalysisLabels,
            userFacingSignals: userFacingSignals
        ))

        if !userFacingSignals.isEmpty, !containsConcreteSignal(combined, concreteSignals: userFacingSignals) {
            reasons.append("no concrete signal referenced (generic filler)")
        }

        return reasons.isEmpty ? .valid : .invalid(reasons: reasons)
    }

    private static func bannedPhraseReasons(in normalizedText: String, tone: SoundPrintPersonaTone = .balanced, context: String? = nil) -> [String] {
        bannedPhrases(for: tone)
            .filter { normalizedText.containsNormalizedSoundPrintPhrase($0) }
            .map { phrase in
                if let context {
                    return "banned phrase in \(context): \(phrase)"
                }

                return "banned phrase: \(phrase)"
            }
    }

    private static func metaCommentaryReasons(in normalizedText: String, words: [String]) -> [String] {
        var reasons = words
            .filter { metaCommentaryWords.contains($0) }
            .map { "critique-style meta language: \($0)" }

        reasons.append(contentsOf: metaCommentaryPhrases
            .filter { normalizedText.containsNormalizedSoundPrintPhrase($0) }
            .map { "critique-style meta language: \($0)" })

        return reasons
    }

    private static func vagueAlbumReferenceReasons(in normalizedText: String) -> [String] {
        vagueAlbumReferencePhrases
            .filter { normalizedText.containsNormalizedSoundPrintPhrase($0) }
            .map { "vague unnamed album reference: \($0)" }
    }

    private static func overconfidenceReasons(in normalizedText: String, tone: SoundPrintPersonaTone) -> [String] {
        overconfidentPhrases(for: tone)
            .filter { normalizedText.containsNormalizedSoundPrintPhrase($0) }
            .map { "overconfident language for low log count: \($0)" }
    }

    private static func unsupportedFrequencyReasons(in normalizedText: String) -> [String] {
        unsupportedFrequencyPhrases
            .filter { containsPhraseOrWord($0, in: normalizedText) }
            .map { "unsupported absolute-frequency claim: \($0)" }
    }

    private static func unsupportedReplayReasons(in normalizedText: String) -> [String] {
        replayBehaviorPhrases
            .filter { containsPhraseOrWord($0, in: normalizedText) }
            .map { "unsupported replay behavior: \($0)" }
    }

    private static func containsPhraseOrWord(_ phrase: String, in normalizedText: String) -> Bool {
        let normalizedPhrase = phrase.normalizedSoundPrintText
        if normalizedPhrase.normalizedSoundPrintWords.count == 1 {
            return normalizedText.normalizedSoundPrintWords.contains(normalizedPhrase)
        }

        return normalizedText.containsNormalizedSoundPrintPhrase(normalizedPhrase)
    }

    private static func internalAnalysisLabelReasons(
        in normalizedText: String,
        internalAnalysisLabels: [String],
        userFacingSignals: [String]
    ) -> [String] {
        return internalAnalysisLabels.compactMap { label in
            let normalizedLabel = label.normalizedSoundPrintText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !normalizedLabel.isEmpty,
                  normalizedText.contains(normalizedLabel) else {
                return nil
            }

            return "internal analysis label leaked: \(label)"
        }
    }

    private static func containsConcreteSignal(_ normalizedText: String, concreteSignals: [String]) -> Bool {
        concreteSignals.contains { signal in
            let normalizedSignal = signal.normalizedSoundPrintText.trimmingCharacters(in: .whitespacesAndNewlines)
            return !normalizedSignal.isEmpty && normalizedText.contains(normalizedSignal)
        }
    }
}
