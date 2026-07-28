//
//  MockSoundPrintProvider.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

import Foundation

/// Deterministic local SoundPrint provider — production code, not a test-only
/// mock. It serves Simulator, UI tests, devices without Apple Intelligence,
/// users who turned the preference off, and any FoundationModels failure via
/// `FallbackSoundPrintProvider`.
struct MockSoundPrintProvider: SoundPrintProvider {
    func analyzeSentiment(input: SentimentInput) async throws -> SentimentResult {
        Self.analyzeSentiment(input: input)
    }

    func extractTasteSignals(input: TasteExtractionInput) async throws -> TasteExtractionResult {
        Self.extractTasteSignals(input: input)
    }

    func generatePersona(input: PersonaInput) async throws -> PersonaResult {
        Self.generatePersona(input: input)
    }

    func generateCompactSummary(input: CompactSummaryInput) async throws -> CompactSummaryResult {
        Self.generateCompactSummary(input: input)
    }

    static func analyzeSentiment(input: SentimentInput) -> SentimentResult {
        let words = Set(input.reviewText.normalizedSoundPrintWords)
        let positiveMatches = words.intersection(positiveKeywords).count
        let negativeMatches = words.intersection(negativeKeywords).count

        let keywordAdjustedScore = baseScore(for: input.rating)
            + (Double(positiveMatches) * 0.1)
            - (Double(negativeMatches) * 0.2)

        return SentimentResult(
            score: keywordAdjustedScore.clamped(to: -1.0...1.0),
            confidence: input.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 0.8
        )
    }

    static func baseScore(for rating: Double) -> Double {
        if rating >= 4.0 {
            return 0.7
        }

        if rating >= 3.0 {
            return 0.2
        }

        return -0.5
    }

    static func extractTasteSignals(input: TasteExtractionInput) -> TasteExtractionResult {
        let sentimentScore = input.sentimentScore ?? baseScore(for: input.rating)
        let tagEvidence = partitionReactionTags(input.tags)
        let avoidanceSignals = extractAvoidanceSignals(
            input: input,
            canonicalTags: tagEvidence.canonical,
            customTags: tagEvidence.custom
        )

        guard sentimentScore >= 0.0 else {
            let scopedCraftTags = tagEvidence.canonical.filter {
                $0.category == .craftPerformance && $0.polarity == .positive
            }
            let scopedSignals = canonicalTasteSignals(
                from: scopedCraftTags,
                rating: input.rating,
                sentimentScore: sentimentScore
            )
            .map {
                TasteSignal(
                    dimensionName: $0.dimensionName,
                    label: $0.label,
                    summary: $0.summary,
                    weight: min($0.weight, scopedCanonicalTasteWeightCap),
                    confidence: min($0.confidence, scopedCanonicalTasteConfidenceCap),
                    evidenceSnippet: $0.evidenceSnippet,
                    isPositiveEvidence: true
                )
            }

            return TasteExtractionResult(
                signals: orderedTasteSignals(scopedSignals),
                avoidanceSignals: avoidanceSignals
            )
        }

        var signals = canonicalTasteSignals(
            from: tagEvidence.canonical,
            rating: input.rating,
            sentimentScore: sentimentScore
        )
        let legacyExtraction = legacyTasteSignals(
            input: input,
            customTags: tagEvidence.custom,
            sentimentScore: sentimentScore
        )
        mergeTasteSignals(
            legacyExtraction.signals,
            into: &signals,
            preferIncomingEvidence: !input.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )

        applyFavoriteTrackEvidence(
            to: &signals,
            input: input,
            normalizedText: legacyExtraction.normalizedText,
            sentimentScore: sentimentScore
        )
        applyStandoutMomentEvidence(to: &signals, input: input)
        dampenThinPositiveEvidence(in: &signals, input: input)

        return TasteExtractionResult(
            signals: orderedTasteSignals(signals),
            avoidanceSignals: avoidanceSignals
        )
    }

    private static func legacyTasteSignals(
        input: TasteExtractionInput,
        customTags: [String],
        sentimentScore: Double
    ) -> (signals: [TasteSignal], normalizedText: String) {
        let searchableText = ([input.reviewText, input.standoutMoment ?? ""] + customTags).joined(separator: " ")
        let normalizedText = searchableText.normalizedSoundPrintText
        let reviewSnippet = input.reviewText.trimmedForSoundPrint
        let fallbackSnippet = customTags.isEmpty ? input.albumTitle : "Tags: \(customTags.joined(separator: ", "))"
        let evidenceSnippet = reviewSnippet.isEmpty ? fallbackSnippet : reviewSnippet
        let hasReviewText = !input.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let normalizedReviewText = input.reviewText.normalizedSoundPrintText
        let normalizedStandoutMoment = (input.standoutMoment ?? "").normalizedSoundPrintText
        let hasDetailedReview = isDetailedSoundPrintReview(input.reviewText)

        let signals = tasteRules.compactMap { rule -> TasteSignal? in
            let matchCount = rule.keywords.filter { normalizedText.containsNormalizedSoundPrintPhrase($0) }.count

            guard matchCount > 0 else {
                return nil
            }

            var weight = (0.55 + (sentimentScore * 0.35) + (Double(matchCount - 1) * 0.05)).clamped(to: 0.0...1.0)
            let confidenceBase = hasReviewText ? 0.75 : 0.6
            var confidence = (confidenceBase + (Double(matchCount - 1) * 0.05)).clamped(to: 0.0...1.0)
            let hasDetailedMatchingEvidence =
                (
                    hasDetailedReview
                        && rule.keywords.contains {
                            normalizedReviewText.containsNormalizedSoundPrintPhrase($0)
                        }
                )
                || rule.keywords.contains {
                    normalizedStandoutMoment.containsNormalizedSoundPrintPhrase($0)
                }

            if input.rating < lowRatedCanonicalRatingThreshold,
               !hasDetailedMatchingEvidence {
                weight = min(weight, lowRatedLooseLegacyTasteWeightCap)
                confidence = min(confidence, lowRatedLooseLegacyTasteConfidenceCap)
            }

            return TasteSignal(
                dimensionName: rule.dimensionName,
                label: rule.label,
                summary: "Leans into \(rule.label.lowercased()).",
                weight: weight,
                confidence: confidence,
                evidenceSnippet: evidenceSnippet,
                isPositiveEvidence: true
            )
        }

        return (signals, normalizedText)
    }

    private static func canonicalTasteSignals(
        from tags: [ReactionTagDefinition],
        rating: Double,
        sentimentScore: Double
    ) -> [TasteSignal] {
        tasteRules.compactMap { rule in
            let matchingTags = tags.filter {
                $0.soundPrintDimensions.contains(rule.dimensionName)
            }

            guard !matchingTags.isEmpty else {
                return nil
            }

            var weight = canonicalTasteWeight(sentimentScore: sentimentScore)
            var confidence = (
                canonicalBaseConfidence
                    + (Double(matchingTags.count - 1) * canonicalMultiplicityConfidenceBonus)
            )
            .clamped(to: 0.0...canonicalMultiplicityConfidenceCap)

            if rating < lowRatedCanonicalRatingThreshold {
                weight = min(weight, scopedCanonicalTasteWeightCap)
                confidence = min(confidence, scopedCanonicalTasteConfidenceCap)
            }

            return TasteSignal(
                dimensionName: rule.dimensionName,
                label: rule.label,
                summary: "Leans into \(rule.label.lowercased()).",
                weight: weight,
                confidence: confidence,
                evidenceSnippet: canonicalEvidenceSnippet(from: matchingTags),
                isPositiveEvidence: true
            )
        }
    }

    private static func canonicalTasteWeight(sentimentScore: Double) -> Double {
        (
            canonicalTasteBaseWeight
                + (max(sentimentScore, 0.0) * canonicalTasteSentimentMultiplier)
        )
        .clamped(to: 0.0...1.0)
    }

    private static func mergeTasteSignals(
        _ incomingSignals: [TasteSignal],
        into signals: inout [TasteSignal],
        preferIncomingEvidence: Bool
    ) {
        for incoming in incomingSignals {
            guard let index = signals.firstIndex(where: {
                $0.dimensionName == incoming.dimensionName
            }) else {
                signals.append(incoming)
                continue
            }

            let existing = signals[index]
            signals[index] = TasteSignal(
                dimensionName: existing.dimensionName,
                label: existing.label,
                summary: existing.summary,
                weight: max(existing.weight, incoming.weight),
                confidence: (
                    max(existing.confidence, incoming.confidence)
                        + canonicalAgreementConfidenceBonus
                )
                .clamped(to: 0.0...canonicalAgreementConfidenceCap),
                evidenceSnippet: preferIncomingEvidence
                    ? incoming.evidenceSnippet
                    : existing.evidenceSnippet,
                isPositiveEvidence: true
            )
        }
    }

    private static func orderedTasteSignals(_ signals: [TasteSignal]) -> [TasteSignal] {
        signals.sorted { left, right in
            let leftIndex = tasteRules.firstIndex {
                $0.dimensionName == left.dimensionName
            } ?? .max
            let rightIndex = tasteRules.firstIndex {
                $0.dimensionName == right.dimensionName
            } ?? .max

            if leftIndex == rightIndex {
                return left.dimensionName < right.dimensionName
            }

            return leftIndex < rightIndex
        }
    }

    /// `favoriteTracks` is treated as positive evidence, primarily for replayability: naming
    /// specific tracks as favorites is itself a signal the album has real replay pull. When the
    /// review/tags independently agree (mentions "replay"/"repeat"/"addictive"), confidence gets
    /// a bonus rather than staying flat, per the agreement rule.
    private static func applyFavoriteTrackEvidence(
        to signals: inout [TasteSignal],
        input: TasteExtractionInput,
        normalizedText: String,
        sentimentScore: Double
    ) {
        guard !input.favoriteTracks.isEmpty else {
            return
        }

        let hasReplayAgreement = ["replay", "repeat", "addictive"]
            .contains { normalizedText.containsNormalizedSoundPrintPhrase($0) }
        let agreementBonus = (input.favoriteTracks.count >= 2 && hasReplayAgreement) ? 0.15 : 0.0
        let trackEvidence = "Favorite tracks: \(input.favoriteTracks.joined(separator: ", "))"

        if let index = signals.firstIndex(where: { $0.dimensionName == "replayability" }) {
            let existing = signals[index]
            signals[index] = TasteSignal(
                dimensionName: existing.dimensionName,
                label: existing.label,
                summary: existing.summary,
                weight: (existing.weight + 0.1 + agreementBonus).clamped(to: 0.0...1.0),
                confidence: (existing.confidence + 0.1 + agreementBonus).clamped(to: 0.0...1.0),
                evidenceSnippet: existing.evidenceSnippet,
                isPositiveEvidence: true
            )
        } else {
            signals.append(
                TasteSignal(
                    dimensionName: "replayability",
                    label: "Replay Pull",
                    summary: "Leans into replay pull.",
                    weight: (0.5 + (sentimentScore * 0.2) + agreementBonus).clamped(to: 0.0...1.0),
                    confidence: (0.55 + agreementBonus).clamped(to: 0.0...1.0),
                    evidenceSnippet: trackEvidence,
                    isPositiveEvidence: true
                )
            )
        }
    }

    /// `standoutMoment` is high-quality positive evidence: it already fed the keyword-matched
    /// dimensions above via the shared searchable text, so here it just gets a small confidence
    /// bump on whatever it helped produce, since a user calling out a specific moment is stronger
    /// signal than generic review language.
    private static func applyStandoutMomentEvidence(to signals: inout [TasteSignal], input: TasteExtractionInput) {
        guard let standoutMoment = input.standoutMoment, !standoutMoment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let normalizedStandout = standoutMoment.normalizedSoundPrintText

        for index in signals.indices {
            let matchesStandout = tasteRules
                .first { $0.dimensionName == signals[index].dimensionName }?
                .keywords
                .contains { normalizedStandout.containsNormalizedSoundPrintPhrase($0) } ?? false

            guard matchesStandout else {
                continue
            }

            let existing = signals[index]
            signals[index] = TasteSignal(
                dimensionName: existing.dimensionName,
                label: existing.label,
                summary: existing.summary,
                weight: (existing.weight + 0.05).clamped(to: 0.0...1.0),
                confidence: (existing.confidence + 0.1).clamped(to: 0.0...1.0),
                evidenceSnippet: standoutMoment.trimmedForSoundPrint,
                isPositiveEvidence: true
            )
        }
    }

    /// Conflict dampening: a low rating with exactly one favorite track shouldn't be generalized
    /// into a broad positive taste claim — cap that scoped signal's weight/confidence low instead
    /// of letting it seed a high-weight dimension.
    private static func dampenThinPositiveEvidence(in signals: inout [TasteSignal], input: TasteExtractionInput) {
        guard input.rating < 3.0, input.favoriteTracks.count == 1 else {
            return
        }

        for index in signals.indices where signals[index].dimensionName == "replayability" {
            let existing = signals[index]
            signals[index] = TasteSignal(
                dimensionName: existing.dimensionName,
                label: existing.label,
                summary: existing.summary,
                weight: min(existing.weight, 0.3),
                confidence: min(existing.confidence, 0.35),
                evidenceSnippet: existing.evidenceSnippet,
                isPositiveEvidence: true
            )
        }
    }

    /// `skipTracks` is avoidance/tracklist-consistency evidence, not a blanket negative on the
    /// album — it coexists with whatever positive dimensions the log otherwise produced.
    static func extractAvoidanceSignals(input: TasteExtractionInput) -> [AvoidanceSignal] {
        let tagEvidence = partitionReactionTags(input.tags)
        return extractAvoidanceSignals(
            input: input,
            canonicalTags: tagEvidence.canonical,
            customTags: tagEvidence.custom
        )
    }

    private static func extractAvoidanceSignals(
        input: TasteExtractionInput,
        canonicalTags: [ReactionTagDefinition],
        customTags: [String]
    ) -> [AvoidanceSignal] {
        var signals = canonicalAvoidanceSignals(
            from: canonicalTags,
            rating: input.rating
        )
        let legacySignals = legacyAvoidanceSignals(
            input: input,
            customTags: customTags
        )
        mergeAvoidanceSignals(
            legacySignals,
            into: &signals,
            preferIncomingEvidence: !input.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !input.skipTracks.isEmpty
        )
        return orderedAvoidanceSignals(signals)
    }

    private static func legacyAvoidanceSignals(
        input: TasteExtractionInput,
        customTags: [String]
    ) -> [AvoidanceSignal] {
        let searchableText = ([input.reviewText] + customTags).joined(separator: " ")
        let normalizedText = searchableText.normalizedSoundPrintText
        let hasReviewText = !input.reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let confidenceBase = hasReviewText ? 0.6 : 0.45
        let reviewSnippet = input.reviewText.trimmedForSoundPrint
        let fallbackSnippet = customTags.isEmpty ? input.albumTitle : "Tags: \(customTags.joined(separator: ", "))"
        let evidenceSnippet = reviewSnippet.isEmpty ? fallbackSnippet : reviewSnippet
        let normalizedReviewText = input.reviewText.normalizedSoundPrintText
        let hasDetailedReview = isDetailedSoundPrintReview(input.reviewText)

        var signals: [AvoidanceSignal] = avoidanceRules.compactMap { rule -> AvoidanceSignal? in
            let matchCount = rule.keywords.filter { normalizedText.containsNormalizedSoundPrintPhrase($0) }.count

            guard matchCount > 0 else {
                return nil
            }

            var strength = (0.5 + (Double(matchCount - 1) * 0.1)).clamped(to: 0.0...1.0)
            var confidence = (confidenceBase + (Double(matchCount - 1) * 0.05)).clamped(to: 0.0...1.0)
            let hasDetailedMatchingReview =
                hasDetailedReview
                    && rule.keywords.contains {
                        normalizedReviewText.containsNormalizedSoundPrintPhrase($0)
                    }

            if input.rating >= highRatedCanonicalCritiqueRatingThreshold,
               !hasDetailedMatchingReview {
                strength = min(strength, highRatedLooseLegacyAvoidanceStrengthCap)
                confidence = min(confidence, highRatedLooseLegacyAvoidanceConfidenceCap)
            }

            return AvoidanceSignal(
                signalName: rule.signalName,
                label: rule.label,
                summary: "Loses patience with \(rule.label.lowercased()).",
                strength: strength,
                confidence: confidence,
                evidenceSnippet: evidenceSnippet
            )
        }

        let skipCount = input.skipTracks.count
        let hasPositiveSkipLanguage = positiveSkipPhrases.contains { normalizedText.containsNormalizedSoundPrintPhrase($0) }
        let hasSkipKeywordMatch = skipHeavyKeywords.contains { keyword in
            (keyword != "skip" || !hasPositiveSkipLanguage)
                && normalizedText.containsNormalizedSoundPrintPhrase(keyword)
        }

        guard skipCount >= 2 || hasSkipKeywordMatch else {
            return signals
        }

        // Agreement: track selections plus matching language make this a stronger signal
        // than either alone.
        let agreementBonus = (skipCount >= 2 && hasSkipKeywordMatch) ? 0.15 : 0.0
        var strength = (0.45 + (Double(min(skipCount, 4)) * 0.08) + agreementBonus).clamped(to: 0.0...1.0)
        var confidence = (confidenceBase + agreementBonus).clamped(to: 0.0...1.0)

        // Conflict dampening: a high rating alongside skip tracks reads as a tracklist-patience
        // quirk, not a strong overall dislike, so keep this modest rather than suppressing it.
        if input.rating >= 4.0 {
            strength = min(strength, 0.4)
            confidence = min(confidence, 0.45)
        }

        let skipSnippet = skipCount > 0 ? "Skipped: \(input.skipTracks.joined(separator: ", "))" : evidenceSnippet

        signals.append(
            AvoidanceSignal(
                signalName: "skipHeavyAlbums",
                label: "Skip-Heavy Albums",
                summary: "Tends to skip through parts of albums like this.",
                strength: strength,
                confidence: confidence,
                evidenceSnippet: skipSnippet
            )
        )

        return signals
    }

    private static func canonicalAvoidanceSignals(
        from tags: [ReactionTagDefinition],
        rating: Double
    ) -> [AvoidanceSignal] {
        allAvoidanceRules.compactMap { rule in
            let matchingTags = tags.filter {
                $0.avoidanceSignals.contains(rule.signalName)
            }

            guard !matchingTags.isEmpty else {
                return nil
            }

            let isHighRated = rating >= highRatedCanonicalCritiqueRatingThreshold
            let confidenceBase = isHighRated
                ? highRatedCanonicalAvoidanceBaseConfidence
                : canonicalBaseConfidence
            let confidenceCap = isHighRated
                ? highRatedCanonicalAvoidanceConfidenceCap
                : canonicalMultiplicityConfidenceCap
            let confidence = (
                confidenceBase
                    + (Double(matchingTags.count - 1) * canonicalMultiplicityConfidenceBonus)
            )
            .clamped(to: 0.0...confidenceCap)
            let strength = isHighRated
                ? min(canonicalAvoidanceStrength, highRatedCanonicalAvoidanceStrengthCap)
                : canonicalAvoidanceStrength

            return AvoidanceSignal(
                signalName: rule.signalName,
                label: rule.label,
                summary: avoidanceSummary(
                    signalName: rule.signalName,
                    label: rule.label
                ),
                strength: strength,
                confidence: confidence,
                evidenceSnippet: canonicalEvidenceSnippet(from: matchingTags)
            )
        }
    }

    private static func mergeAvoidanceSignals(
        _ incomingSignals: [AvoidanceSignal],
        into signals: inout [AvoidanceSignal],
        preferIncomingEvidence: Bool
    ) {
        for incoming in incomingSignals {
            guard let index = signals.firstIndex(where: {
                $0.signalName == incoming.signalName
            }) else {
                signals.append(incoming)
                continue
            }

            let existing = signals[index]
            signals[index] = AvoidanceSignal(
                signalName: existing.signalName,
                label: existing.label,
                summary: existing.summary,
                strength: max(existing.strength, incoming.strength),
                confidence: (
                    max(existing.confidence, incoming.confidence)
                        + canonicalAgreementConfidenceBonus
                )
                .clamped(to: 0.0...canonicalAgreementConfidenceCap),
                evidenceSnippet: preferIncomingEvidence
                    ? incoming.evidenceSnippet
                    : existing.evidenceSnippet
            )
        }
    }

    private static func orderedAvoidanceSignals(
        _ signals: [AvoidanceSignal]
    ) -> [AvoidanceSignal] {
        signals.sorted { left, right in
            let leftIndex = allAvoidanceRules.firstIndex {
                $0.signalName == left.signalName
            } ?? .max
            let rightIndex = allAvoidanceRules.firstIndex {
                $0.signalName == right.signalName
            } ?? .max

            if leftIndex == rightIndex {
                return left.signalName < right.signalName
            }

            return leftIndex < rightIndex
        }
    }

    private static func avoidanceSummary(
        signalName: String,
        label: String
    ) -> String {
        if signalName == "skipHeavyAlbums" {
            return "Tends to skip through parts of albums like this."
        }

        return "Loses patience with \(label.lowercased())."
    }

    private static func partitionReactionTags(
        _ tags: [String]
    ) -> (canonical: [ReactionTagDefinition], custom: [String]) {
        var canonical: [ReactionTagDefinition] = []
        var custom: [String] = []
        var seenCanonicalIDs: Set<String> = []

        for tag in tags {
            guard let definition = reactionTagResolver.canonicalTag(
                forPersistedDisplayValue: tag
            ) else {
                custom.append(tag)
                continue
            }

            if seenCanonicalIDs.insert(definition.id).inserted {
                canonical.append(definition)
            }
        }

        return (canonical, custom)
    }

    private static func canonicalEvidenceSnippet(
        from tags: [ReactionTagDefinition]
    ) -> String {
        "Reactions: \(tags.map(\.displayName).joined(separator: ", "))"
    }

    private static func isDetailedSoundPrintReview(_ reviewText: String) -> Bool {
        reviewText
            .split(whereSeparator: \.isWhitespace)
            .count >= minimumDetailedSoundPrintReviewWordCount
    }

    static func generateCompactSummary(input: CompactSummaryInput) -> CompactSummaryResult {
        let sortedDimensions = input.dimensions.sorted { $0.weight > $1.weight }
        let sortedAvoidance = input.avoidanceSignals.sorted { $0.strength > $1.strength }
        let groundingSignal = compactGroundingSignal(from: input.userFacingSignals)

        let result = CompactSummaryResult(
            headline: compactSummaryHeadline(topDimension: sortedDimensions.first, tone: input.tone),
            summary: compactSummarySentence(topDimension: sortedDimensions.first, topAvoidance: sortedAvoidance.first, tone: input.tone),
            bullets: compactSummaryBullets(dimensions: sortedDimensions, avoidanceSignals: sortedAvoidance, tone: input.tone, groundingSignal: groundingSignal)
        )

        guard SoundPrintOutputValidator.validateCompactSummary(
            headline: result.headline,
            summary: result.summary,
            bullets: result.bullets,
            tone: input.tone,
            userFacingSignals: input.userFacingSignals,
            internalAnalysisLabels: input.dimensions.map(\.label) + input.avoidanceSignals.map(\.label)
        ).isValid else {
            return fallbackCompactSummary(tone: input.tone)
        }

        return result
    }

    private static func compactSummaryHeadline(topDimension: TasteDimension?, tone: SoundPrintPersonaTone) -> String {
        guard topDimension != nil else {
            switch tone {
            case .analyst: return "Insufficient Data For A Finding"
            case .balanced: return "Still Building The Pattern"
            case .wrapped: return "Plot Still Loading"
            }
        }

        switch tone {
        case .analyst:
            return "Clear Reward Pattern Leads"
        case .balanced:
            return "Reward And Friction"
        case .wrapped:
            return "The Pattern Has Teeth"
        }
    }

    private static func compactSummarySentence(topDimension: TasteDimension?, topAvoidance: TasteAvoidanceSignal?, tone: SoundPrintPersonaTone) -> String {
        guard let topDimension else {
            return "Log a few more albums to start seeing a pattern here."
        }

        switch tone {
        case .analyst:
            guard let topAvoidance else {
                return "The data points to \(naturalPhrase(for: topDimension.label)) as the leading reward signal."
            }
            return "The data points to \(naturalPhrase(for: topDimension.label)), with \(naturalPhrase(for: topAvoidance.label)) as the leading detractor."
        case .balanced:
            guard let topAvoidance else {
                return "You tend to reward \(naturalPhrase(for: topDimension.label))."
            }
            return "You reward \(naturalPhrase(for: topDimension.label)), but \(naturalPhrase(for: topAvoidance.label)) can lose you fast."
        case .wrapped:
            guard let topAvoidance else {
                return "Your logs made \(naturalPhrase(for: topDimension.label)) the main character."
            }
            return "You wanted \(naturalPhrase(for: topDimension.label)); \(naturalPhrase(for: topAvoidance.label)) got shown the door."
        }
    }

    private static func compactSummaryBullets(
        dimensions: [TasteDimension],
        avoidanceSignals: [TasteAvoidanceSignal],
        tone: SoundPrintPersonaTone,
        groundingSignal: String?
    ) -> [String] {
        var bullets: [String] = []

        if let groundingSignal {
            bullets.append("Example: \(groundingSignal)")
        }

        switch tone {
        case .analyst:
            for dimension in dimensions.prefix(2) where bullets.count < 3 {
                bullets.append("Rewards: \(naturalPhrase(for: dimension.label))")
            }
            if let topAvoidance = avoidanceSignals.first, bullets.count < 3 {
                bullets.append("Docks: \(naturalPhrase(for: topAvoidance.label))")
            } else if let thirdDimension = dimensions.dropFirst(2).first, bullets.count < 3 {
                bullets.append("Trend: \(naturalPhrase(for: thirdDimension.label))")
            }
        case .balanced:
            for dimension in dimensions.prefix(2) where bullets.count < 3 {
                bullets.append("Rewards \(naturalPhrase(for: dimension.label))")
            }
            if let topAvoidance = avoidanceSignals.first, bullets.count < 3 {
                bullets.append("Loses patience with \(naturalPhrase(for: topAvoidance.label))")
            } else if let thirdDimension = dimensions.dropFirst(2).first, bullets.count < 3 {
                bullets.append("Also leans into \(naturalPhrase(for: thirdDimension.label))")
            }
        case .wrapped:
            for dimension in dimensions.prefix(2) where bullets.count < 3 {
                bullets.append("Wants \(naturalPhrase(for: dimension.label))")
            }
            if let topAvoidance = avoidanceSignals.first, bullets.count < 3 {
                bullets.append("Rejects \(naturalPhrase(for: topAvoidance.label))")
            } else if let thirdDimension = dimensions.dropFirst(2).first, bullets.count < 3 {
                bullets.append("Also wants \(naturalPhrase(for: thirdDimension.label))")
            }
        }

        let modestFillers: [String]
        switch tone {
        case .analyst:
            modestFillers = ["Sample size still small", "More logs will sharpen this", "Pattern still forming"]
        case .balanced:
            modestFillers = ["Still gathering evidence", "More logs will sharpen this", "Pattern still forming"]
        case .wrapped:
            modestFillers = ["More logs sharpen the plot", "The pattern is warming up", "Next chapter pending"]
        }

        var fillerIndex = 0
        while bullets.count < 3, fillerIndex < modestFillers.count {
            bullets.append(modestFillers[fillerIndex])
            fillerIndex += 1
        }

        return Array(bullets.prefix(3))
    }

    private static func fallbackCompactSummary(tone: SoundPrintPersonaTone) -> CompactSummaryResult {
        switch tone {
        case .analyst:
            return CompactSummaryResult(
                headline: "Insufficient Data For A Finding",
                summary: "Log a few more albums to start seeing a pattern here.",
                bullets: ["Sample size still small", "More logs will sharpen this", "Pattern still forming"]
            )
        case .balanced:
            return CompactSummaryResult(
                headline: "Still Building The Pattern",
                summary: "Log a few more albums to start seeing a pattern here.",
                bullets: ["Still gathering evidence", "More logs will sharpen this", "Pattern still forming"]
            )
        case .wrapped:
            return CompactSummaryResult(
                headline: "Plot Still Loading",
                summary: "Log a few more albums to start seeing a pattern here.",
                bullets: ["More logs sharpen the plot", "The pattern is warming up", "Next chapter pending"]
            )
        }
    }

    static func generatePersona(input: PersonaInput) -> PersonaResult {
        let strongestDimensions = input.dimensions
            .sorted {
                if $0.weight == $1.weight {
                    return $0.label < $1.label
                }

                return $0.weight > $1.weight
            }
        let positiveLogs = input.recentLogs.filter(\.isPositiveSignal)
        let favoriteLog = positiveLogs
            .sorted {
                if $0.rating == $1.rating {
                    return $0.albumTitle < $1.albumTitle
                }

                return $0.rating > $1.rating
            }
            .first

        let primaryDimension = strongestDimensions.first?.label
        let secondaryDimension = strongestDimensions.dropFirst().first?.label
        let topAvoidanceLabel = input.avoidanceSignals.first

        let draft = buildPersonaDraft(
            primaryDimension: primaryDimension,
            secondaryDimension: secondaryDimension,
            topAvoidanceLabel: topAvoidanceLabel,
            favoriteLog: favoriteLog,
            tone: input.tone
        )

        if SoundPrintOutputValidator.isPersonaValid(
            draft,
            userFacingSignals: FoundationModelsSoundPrintValidator.userFacingSignals(from: input),
            internalAnalysisLabels: FoundationModelsSoundPrintValidator.internalAnalysisLabels(from: input),
            logCount: input.totalLogCount,
            tone: input.tone
        ) {
            return PersonaResult(text: draft, generationSource: .localFallback)
        }

        return PersonaResult(
            text: fallbackPersona(
                primaryDimension: primaryDimension,
                topAvoidanceLabel: topAvoidanceLabel,
                favoriteLog: favoriteLog,
                tone: input.tone
            ),
            generationSource: .localFallback
        )
    }

    /// Two sentences: the first states what's rewarded (preferred phrasing
    /// per the tone spec), the second grounds it in either an avoidance signal (what's rejected)
    /// or the strongest available track-level/album evidence — never both, to stay within budget.
    private static func buildPersonaDraft(
        primaryDimension: String?,
        secondaryDimension: String?,
        topAvoidanceLabel: String?,
        favoriteLog: PersonaLogInput?,
        tone: SoundPrintPersonaTone
    ) -> String {
        "\(personaRewardClause(primaryDimension: primaryDimension, secondaryDimension: secondaryDimension, tone: tone)) \(personaEvidenceClause(topAvoidanceLabel: topAvoidanceLabel, favoriteLog: favoriteLog, tone: tone))"
    }

    private static func personaRewardClause(primaryDimension: String?, secondaryDimension: String?, tone: SoundPrintPersonaTone) -> String {
        guard let primaryDimension else {
            switch tone {
            case .analyst: return "Your data so far points to records with real staying power."
            case .balanced: return "Your logs point toward records with real staying power."
            case .wrapped: return "Your logs are still writing this chapter."
            }
        }

        switch tone {
        case .analyst:
            if let secondaryDimension {
                return "Your data points to \(naturalPhrase(for: primaryDimension)) and \(naturalPhrase(for: secondaryDimension)) as reward signals."
            }
            return "Your data points to \(naturalPhrase(for: primaryDimension)) as the leading reward signal."
        case .balanced:
            if let secondaryDimension {
                return "You reward \(naturalPhrase(for: primaryDimension)) and \(naturalPhrase(for: secondaryDimension))."
            }
            return "You reward \(naturalPhrase(for: primaryDimension))."
        case .wrapped:
            if let secondaryDimension {
                return "Your logs wanted \(naturalPhrase(for: primaryDimension)) and \(naturalPhrase(for: secondaryDimension))."
            }
            return "Your logs wanted \(naturalPhrase(for: primaryDimension))."
        }
    }

    private static func personaEvidenceClause(topAvoidanceLabel: String?, favoriteLog: PersonaLogInput?, tone: SoundPrintPersonaTone) -> String {
        if let topAvoidanceLabel {
            let albumText = favoriteLog.map { " \($0.albumTitle) is the clearest example." } ?? ""
            switch tone {
            case .analyst: return "\(naturalPhrase(for: topAvoidanceLabel)) is where your patience runs out.\(albumText)"
            case .balanced: return "You lose patience with \(naturalPhrase(for: topAvoidanceLabel)).\(albumText)"
            case .wrapped: return "\(naturalPhrase(for: topAvoidanceLabel)) got cut fast.\(albumText)"
            }
        }

        guard let favoriteLog else {
            switch tone {
            case .analyst: return "Your sample so far is too small for a clear secondary signal."
            case .balanced: return "The pattern so far is still taking shape."
            case .wrapped: return "The plot is still warming up."
            }
        }

        if favoriteLog.hasStandoutMoment {
            switch tone {
            case .analyst: return "The moment you flagged in \(favoriteLog.albumTitle) is the clearest data point."
            case .balanced: return "The moment you flagged in \(favoriteLog.albumTitle) says it best."
            case .wrapped: return "The moment you flagged in \(favoriteLog.albumTitle) did the talking."
            }
        }

        if let favoriteTrack = favoriteLog.favoriteTracks.first {
            switch tone {
            case .analyst: return "\"\(favoriteTrack)\" off \(favoriteLog.albumTitle) is the clearest example in your logs so far."
            case .balanced: return "\"\(favoriteTrack)\" off \(favoriteLog.albumTitle) is the clearest example so far."
            case .wrapped: return "\"\(favoriteTrack)\" off \(favoriteLog.albumTitle) made the case."
            }
        }

        switch tone {
        case .analyst: return "\(favoriteLog.albumTitle) by \(favoriteLog.artistName) is the clearest example in your logs so far."
        case .balanced: return "\(favoriteLog.albumTitle) by \(favoriteLog.artistName) is the clearest example so far."
        case .wrapped: return "\(favoriteLog.albumTitle) by \(favoriteLog.artistName) made the pattern obvious."
        }
    }

    private static func fallbackPersona(
        primaryDimension: String?,
        topAvoidanceLabel: String?,
        favoriteLog: PersonaLogInput?,
        tone: SoundPrintPersonaTone
    ) -> String {
        guard let primaryDimension else {
            switch tone {
            case .analyst:
                let albumText = favoriteLog.map { "\($0.albumTitle) is the clearest example in your logs so far." } ?? "Your ratings alone are doing the talking so far."
                return "Your data so far points to records with real staying power. \(albumText)"
            case .balanced:
                let albumText = favoriteLog.map { "\($0.albumTitle) is the clearest example so far." } ?? "The ratings alone are doing the talking so far."
                return "Your logs point toward records with real staying power. \(albumText)"
            case .wrapped:
                let albumText = favoriteLog.map { "\($0.albumTitle) made the pattern visible." } ?? "The ratings alone are telling the story so far."
                return "Your logs are still writing this chapter. \(albumText)"
            }
        }

        if let topAvoidanceLabel, let favoriteLog {
            switch tone {
            case .analyst:
                return "Your data points to \(naturalPhrase(for: primaryDimension)) as the clearest signal so far. \(naturalPhrase(for: topAvoidanceLabel)) is where \(favoriteLog.albumTitle) shows the limit."
            case .balanced:
                return "You reward \(naturalPhrase(for: primaryDimension)). \(favoriteLog.albumTitle) also shows your patience dropping around \(naturalPhrase(for: topAvoidanceLabel))."
            case .wrapped:
                return "Your logs wanted \(naturalPhrase(for: primaryDimension)). \(naturalPhrase(for: topAvoidanceLabel)) got cut fast on \(favoriteLog.albumTitle)."
            }
        }

        if let favoriteLog, let favoriteTrack = favoriteLog.favoriteTracks.first {
            switch tone {
            case .analyst:
                return "Your data points to \(naturalPhrase(for: primaryDimension)) as the clearest signal so far. \"\(favoriteTrack)\" off \(favoriteLog.albumTitle) is the clearest example."
            case .balanced:
                return "Your logs point toward \(naturalPhrase(for: primaryDimension)). \"\(favoriteTrack)\" off \(favoriteLog.albumTitle) is the clearest example."
            case .wrapped:
                return "Your logs wanted \(naturalPhrase(for: primaryDimension)). \"\(favoriteTrack)\" off \(favoriteLog.albumTitle) made the case."
            }
        }

        switch tone {
        case .analyst:
            let albumText = favoriteLog.map { " \($0.albumTitle) is the clearest example in your logs." } ?? ""
            return "Your data points to \(naturalPhrase(for: primaryDimension)) as the clearest signal so far.\(albumText)"
        case .balanced:
            let albumText = favoriteLog.map { " \($0.albumTitle) is the clearest example." } ?? " That pattern is the clearest signal so far."
            return "Your logs point toward \(naturalPhrase(for: primaryDimension)).\(albumText)"
        case .wrapped:
            let albumText = favoriteLog.map { " \($0.albumTitle) made the pattern obvious." } ?? " The pattern is only getting clearer."
            return "Your logs wanted \(naturalPhrase(for: primaryDimension)).\(albumText)"
        }
    }

    private static func compactGroundingSignal(from userFacingSignals: [String]) -> String? {
        userFacingSignals.first { $0.normalizedSoundPrintWords.count <= 10 }
    }

    private static func naturalPhrase(for label: String) -> String {
        switch label {
        case "Emotional Temperature": return "records with a clear emotional temperature"
        case "Energy Bias": return "high-energy records"
        case "Production Taste": return "distinct production choices"
        case "Vocal Gravity", "Vocal Focus": return "standout vocal performances"
        case "Lyric Attention": return "lyrics that carry real weight"
        case "Experimental Tolerance": return "records that take strange turns"
        case "Arrangement Depth": return "rich arrangements"
        case "Genre Flex": return "sounds that cross lanes"
        case "Era Pull": return "records with a strong sense of era"
        case "Replay Pull": return "albums that hold up past the first impression"
        case "Tracklist Patience": return "albums that stay tight front to back"
        case "Emotional Directness": return "direct emotional writing"
        case "Texture Bias": return "records with a strong sonic texture"
        case "Filler Sensitivity": return "tracks that feel padded"
        case "Sterile Production": return "production that feels too sterile"
        case "Weak Writing": return "writing that feels thin"
        case "Low Replay Value": return "records that fade after the first impression"
        case "Energy Without Payoff": return "buildups that never pay off"
        case "Mood Mismatch": return "records that miss the mood"
        case "Skip-Heavy Albums": return "albums with too much dead weight"
        default: return label.lowercased()
        }
    }

    private static let positiveKeywords: Set<String> = [
        "love",
        "loved",
        "great",
        "favorite",
        "beautiful",
        "amazing",
        "replay",
        "catchy",
        "incredible"
    ]

    private static let negativeKeywords: Set<String> = [
        "hate",
        "hated",
        "boring",
        "overrated",
        "bad",
        "weak",
        "annoying",
        "forgettable",
        "disappointing"
    ]

    private static let reactionTagResolver = LocalReactionTagResolver(
        catalog: TaxonomyCatalogLoader.shared
    )
    private static let canonicalTasteBaseWeight = 0.66
    private static let canonicalTasteSentimentMultiplier = 0.25
    private static let canonicalAvoidanceStrength = 0.6
    private static let canonicalBaseConfidence = 0.78
    private static let canonicalMultiplicityConfidenceBonus = 0.04
    private static let canonicalMultiplicityConfidenceCap = 0.86
    private static let canonicalAgreementConfidenceBonus = 0.04
    private static let canonicalAgreementConfidenceCap = 0.9
    private static let lowRatedCanonicalRatingThreshold = 3.0
    private static let scopedCanonicalTasteWeightCap = 0.3
    private static let scopedCanonicalTasteConfidenceCap = 0.35
    private static let lowRatedLooseLegacyTasteWeightCap = 0.25
    private static let lowRatedLooseLegacyTasteConfidenceCap = 0.3
    private static let highRatedCanonicalCritiqueRatingThreshold = 4.0
    private static let highRatedCanonicalAvoidanceStrengthCap = 0.4
    private static let highRatedCanonicalAvoidanceBaseConfidence = 0.6
    private static let highRatedCanonicalAvoidanceConfidenceCap = 0.68
    private static let highRatedLooseLegacyAvoidanceStrengthCap = 0.35
    private static let highRatedLooseLegacyAvoidanceConfidenceCap = 0.5
    private static let minimumDetailedSoundPrintReviewWordCount = 4

    private static let tasteRules: [TasteRule] = [
        TasteRule(dimensionName: "mood", label: "Emotional Temperature", keywords: ["dark", "sad", "moody", "melancholic"]),
        TasteRule(dimensionName: "energy", label: "Energy Bias", keywords: ["energetic", "intense", "aggressive"]),
        TasteRule(dimensionName: "productionStyle", label: "Production Taste", keywords: ["polished", "glossy", "clean", "raw", "rough", "lo-fi"]),
        TasteRule(dimensionName: "vocalFocus", label: "Vocal Gravity", keywords: ["vocals", "voice", "singer"]),
        TasteRule(dimensionName: "lyricFocus", label: "Lyric Attention", keywords: ["lyrics", "writing", "storytelling"]),
        TasteRule(dimensionName: "experimentation", label: "Experimental Tolerance", keywords: ["weird", "experimental", "unpredictable"]),
        TasteRule(dimensionName: "instrumentalRichness", label: "Arrangement Depth", keywords: ["dense", "layered", "lush"]),
        TasteRule(dimensionName: "genreOpenness", label: "Genre Flex", keywords: ["genre-bending", "fusion"]),
        TasteRule(dimensionName: "eraAffinity", label: "Era Pull", keywords: ["classic", "old-school", "90s", "2000s"]),
        TasteRule(dimensionName: "replayability", label: "Replay Pull", keywords: ["replay", "repeat", "addictive"]),
        TasteRule(dimensionName: "tracklistConsistency", label: "Tracklist Patience", keywords: ["consistent", "cohesive", "no filler", "no skips", "not a single skip", "tight tracklist"]),
        TasteRule(dimensionName: "emotionalDirectness", label: "Emotional Directness", keywords: ["raw emotion", "direct", "honest", "vulnerable"]),
        TasteRule(dimensionName: "texturePreference", label: "Texture Bias", keywords: ["textured", "grainy", "atmospheric", "warm tone"])
    ]

    private static let avoidanceRules: [AvoidanceRule] = [
        AvoidanceRule(signalName: "fillerSensitivity", label: "Filler Sensitivity", keywords: ["filler", "padded", "too long", "drags"]),
        AvoidanceRule(signalName: "sterileProduction", label: "Sterile Production", keywords: ["sterile", "overproduced", "lifeless", "clinical"]),
        AvoidanceRule(signalName: "weakWriting", label: "Weak Writing", keywords: ["weak lyrics", "lazy writing", "cliche", "generic lyrics"]),
        AvoidanceRule(signalName: "lowReplayValue", label: "Low Replay Value", keywords: ["one listen", "wont replay", "forgettable", "skip after"]),
        AvoidanceRule(signalName: "energyWithoutPayoff", label: "Energy Without Payoff", keywords: ["all buildup", "no payoff", "goes nowhere", "never arrives"]),
        AvoidanceRule(signalName: "moodMismatch", label: "Mood Mismatch", keywords: ["wrong mood", "tonally off", "mismatched"])
    ]

    private static let allAvoidanceRules: [AvoidanceRule] = {
        avoidanceRules + [
            AvoidanceRule(
                signalName: "skipHeavyAlbums",
                label: "Skip-Heavy Albums",
                keywords: skipHeavyKeywords
            )
        ]
    }()

    private static let skipHeavyKeywords: [String] = [
        "filler", "pacing", "bloated", "too long", "weak middle", "inconsistent", "uneven", "front-loaded", "skip"
    ]

    private static let positiveSkipPhrases: [String] = [
        "no skips", "not a single skip", "not one skip", "zero skips", "never skipped", "didnt skip", "didn't skip"
    ]
}

private struct AvoidanceRule {
    let signalName: String
    let label: String
    let keywords: [String]
}

private struct TasteRule {
    let dimensionName: String
    let label: String
    let keywords: [String]
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
