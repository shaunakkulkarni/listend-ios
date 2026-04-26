//
//  LogSentimentUpdater.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

import SwiftData

struct LogSentimentUpdater {
    let provider: SoundPrintProvider

    init(provider: SoundPrintProvider = MockSoundPrintProvider()) {
        self.provider = provider
    }

    @MainActor
    func updateSentiment(for log: LogEntry, in modelContext: ModelContext) async throws {
        do {
            let sentiment = try await provider.analyzeSentiment(
                input: SentimentInput(
                    rating: log.rating,
                    reviewText: log.reviewText,
                    tags: log.tags
                )
            )

            log.sentimentScore = sentiment.score
            log.sentimentConfidence = sentiment.confidence
        } catch {
            log.sentimentScore = MockSoundPrintProvider.baseScore(for: log.rating)
            log.sentimentConfidence = 0.6
        }

        try modelContext.save()
    }
}
