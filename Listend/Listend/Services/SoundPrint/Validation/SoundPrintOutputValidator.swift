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
        let concreteSignals: [String]
        let logCount: Int

        init(concreteSignals: [String], logCount: Int = Int.max) {
            self.concreteSignals = concreteSignals
            self.logCount = logCount
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

    static let maxPersonaWordCount = 55
    static let requiredPersonaSentenceCount = 2
    static let minimumPersonaCharacterCount = 40

    static let maxHeadlineWordCount = 7
    static let maxSummaryWordCount = 28
    static let requiredSummarySentenceCount = 1
    static let requiredBulletCount = 3
    static let maxBulletWordCount = 12

    /// Union of every banned/discouraged phrase from the tone spec (persona, summary,
    /// and critic banned-term lists), plus the handful already caught by the original
    /// MockSoundPrintProvider generic-phrase check.
    static let bannedPhrases: [String] = [
        "eclectic taste", "eclectic",
        "sonic journey", "sonic",
        "journey",
        "soundscape",
        "vibes",
        "genre-bending",
        "hidden gem",
        "masterpiece",
        "connoisseur",
        "tastemaker",
        "explorer",
        "curator",
        "audiophile",
        "soundtrack to your life",
        "you contain multitudes",
        "your taste knows no bounds",
        "immaculate vibes",
        "emotional rollercoaster",
        "wide range of genres",
        "something for everyone",
        "diverse taste",
        "varied taste",
        "diverse",
        "unique"
    ]

    private static let overconfidentPhrases: [String] = [
        "always",
        "never",
        "definitely",
        "obsessed with",
        "consistently proves",
        "your favorite genre is"
    ]

    static func validatePersona(_ text: String, context: PersonaValidationContext) -> ValidationOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return .invalid(reasons: ["empty output"])
        }

        var reasons: [String] = []
        let normalized = trimmed.normalizedSoundPrintText

        reasons.append(contentsOf: bannedPhraseReasons(in: normalized))

        if normalized.hasPrefix("you are") {
            reasons.append("starts with a \"You are...\" opener")
        }

        if trimmed.count < minimumPersonaCharacterCount {
            reasons.append("too short")
        }

        let wordCount = trimmed.normalizedSoundPrintWords.count
        if wordCount > maxPersonaWordCount {
            reasons.append("too many words (\(wordCount) > \(maxPersonaWordCount))")
        }

        let sentenceCount = trimmed.soundPrintSentences.count
        if sentenceCount != requiredPersonaSentenceCount {
            reasons.append("expected \(requiredPersonaSentenceCount) sentences, found \(sentenceCount)")
        }

        if !containsConcreteSignal(normalized, concreteSignals: context.concreteSignals) {
            reasons.append("no concrete signal referenced (generic filler)")
        }

        if context.logCount < 10 {
            reasons.append(contentsOf: overconfidenceReasons(in: normalized))
        }

        return reasons.isEmpty ? .valid : .invalid(reasons: reasons)
    }

    static func isPersonaValid(_ text: String, concreteSignals: [String], logCount: Int = Int.max) -> Bool {
        validatePersona(text, context: PersonaValidationContext(concreteSignals: concreteSignals, logCount: logCount)).isValid
    }

    static func validateCompactSummary(headline: String, summary: String, bullets: [String]) -> ValidationOutcome {
        var reasons: [String] = []

        let trimmedHeadline = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBullets = bullets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        if trimmedHeadline.isEmpty {
            reasons.append("empty headline")
        } else {
            let headlineWordCount = trimmedHeadline.normalizedSoundPrintWords.count
            if headlineWordCount > maxHeadlineWordCount {
                reasons.append("headline too long (\(headlineWordCount) > \(maxHeadlineWordCount) words)")
            }
            reasons.append(contentsOf: bannedPhraseReasons(in: trimmedHeadline.normalizedSoundPrintText, context: "headline"))
        }

        if trimmedSummary.isEmpty {
            reasons.append("empty summary")
        } else {
            let summaryWordCount = trimmedSummary.normalizedSoundPrintWords.count
            if summaryWordCount > maxSummaryWordCount {
                reasons.append("summary too long (\(summaryWordCount) > \(maxSummaryWordCount) words)")
            }

            let summarySentenceCount = trimmedSummary.soundPrintSentences.count
            if summarySentenceCount != requiredSummarySentenceCount {
                reasons.append("expected \(requiredSummarySentenceCount) summary sentence, found \(summarySentenceCount)")
            }
            reasons.append(contentsOf: bannedPhraseReasons(in: trimmedSummary.normalizedSoundPrintText, context: "summary"))
        }

        let nonEmptyBullets = trimmedBullets.filter { !$0.isEmpty }
        if nonEmptyBullets.count != requiredBulletCount {
            reasons.append("expected \(requiredBulletCount) bullets, found \(nonEmptyBullets.count)")
        }

        for bullet in nonEmptyBullets {
            let bulletWordCount = bullet.normalizedSoundPrintWords.count
            if bulletWordCount > maxBulletWordCount {
                reasons.append("bullet too long (\(bulletWordCount) > \(maxBulletWordCount) words): \(bullet)")
            }
            reasons.append(contentsOf: bannedPhraseReasons(in: bullet.normalizedSoundPrintText, context: "bullet"))
        }

        return reasons.isEmpty ? .valid : .invalid(reasons: reasons)
    }

    private static func bannedPhraseReasons(in normalizedText: String, context: String? = nil) -> [String] {
        bannedPhrases
            .filter { normalizedText.containsNormalizedSoundPrintPhrase($0) }
            .map { phrase in
                if let context {
                    return "banned phrase in \(context): \(phrase)"
                }

                return "banned phrase: \(phrase)"
            }
    }

    private static func overconfidenceReasons(in normalizedText: String) -> [String] {
        overconfidentPhrases
            .filter { normalizedText.containsNormalizedSoundPrintPhrase($0) }
            .map { "overconfident language for low log count: \($0)" }
    }

    private static func containsConcreteSignal(_ normalizedText: String, concreteSignals: [String]) -> Bool {
        concreteSignals.contains { signal in
            let normalizedSignal = signal.normalizedSoundPrintText.trimmingCharacters(in: .whitespacesAndNewlines)
            return !normalizedSignal.isEmpty && normalizedText.contains(normalizedSignal)
        }
    }
}
