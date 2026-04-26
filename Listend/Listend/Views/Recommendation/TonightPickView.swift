//
//  TonightPickView.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

import SwiftUI
import SwiftData

struct TonightPickView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LogEntry.loggedAt, order: .reverse) private var logs: [LogEntry]

    private let recommendationService = LocalRecommendationService()

    @State private var recommendation: Recommendation?
    @State private var receipts: [RecommendationReceipt] = []
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        List {
            if let recommendation {
                activeRecommendationSection(recommendation)
                feedbackSection(recommendation)
            } else {
                emptyStateSection
            }
        }
        .navigationTitle("Tonight's Pick")
        .task {
            await loadActiveRecommendation()
        }
    }

    private func activeRecommendationSection(_ recommendation: Recommendation) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.album?.title ?? "Unknown Album")
                        .font(.title2.weight(.bold))
                    Text(recommendation.album?.artistName ?? "Unknown Artist")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    metadata(for: recommendation)
                }

                Text(confidenceText(for: recommendation))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(recommendation.explanationText)
                    .font(.subheadline)
            }
            .padding(.vertical, 6)
        } header: {
            Text("Pick")
        }
    }

    private func feedbackSection(_ recommendation: Recommendation) -> some View {
        Section("Receipts") {
            if receipts.isEmpty {
                Text("No receipts saved for this pick.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(receipts) { receipt in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(receipt.snippet)
                            .font(.subheadline)
                        Text("\(receipt.sourceAlbumTitle) - \(receipt.sourceArtistName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Button {
                Task {
                    await submit(.liked, for: recommendation)
                }
            } label: {
                Label("Like", systemImage: "hand.thumbsup")
            }
            .disabled(isWorking)

            Button {
                Task {
                    await submit(.dismissed, for: recommendation)
                }
            } label: {
                Label("Dismiss", systemImage: "xmark")
            }
            .disabled(isWorking)

            Button {
                Task {
                    await submit(.savedForLater, for: recommendation)
                }
            } label: {
                Label("Save for Later", systemImage: "bookmark")
            }
            .disabled(isWorking)

            Button {
                Task {
                    await submit(.listened, for: recommendation)
                }
            } label: {
                Label("Listened", systemImage: "checkmark.circle")
            }
            .disabled(isWorking)
        }
    }

    private var emptyStateSection: some View {
        Section {
            ContentUnavailableView(
                emptyTitle,
                systemImage: emptySystemImage,
                description: Text(emptyDescription)
            )

            Button {
                Task {
                    await generateRecommendation()
                }
            } label: {
                Label("Find Tonight's Pick", systemImage: "sparkles")
            }
            .disabled(isWorking || !hasPositiveAnchor)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hasPositiveAnchor: Bool {
        !recommendationService.positiveAnchorLogs(from: logs).isEmpty
    }

    private var emptyTitle: String {
        hasPositiveAnchor ? "No Active Pick" : "Log More Albums First"
    }

    private var emptySystemImage: String {
        hasPositiveAnchor ? "sparkles" : "music.note.list"
    }

    private var emptyDescription: String {
        hasPositiveAnchor ? "Generate one local recommendation backed by your own logs." : "A 4-star positive log unlocks Tonight's Pick."
    }

    @ViewBuilder
    private func metadata(for recommendation: Recommendation) -> some View {
        HStack(spacing: 8) {
            if let releaseYear = recommendation.album?.releaseYear {
                Text(String(releaseYear))
            }

            if let genreName = recommendation.album?.genreName {
                Text(genreName)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func confidenceText(for recommendation: Recommendation) -> String {
        let score = recommendation.score.formatted(.percent.precision(.fractionLength(0)))
        let confidence = recommendation.confidence.formatted(.percent.precision(.fractionLength(0)))
        return "\(score) match confidence: \(confidence)"
    }

    @MainActor
    private func loadActiveRecommendation() async {
        do {
            recommendation = try recommendationService.activeRecommendation(in: modelContext)
            if let recommendation {
                receipts = try recommendationService.receipts(for: recommendation, in: modelContext)
            }
        } catch {
            message = "Could not load Tonight's Pick."
        }
    }

    @MainActor
    private func generateRecommendation() async {
        isWorking = true
        defer {
            isWorking = false
        }

        do {
            let generated = try await recommendationService.currentOrGenerateRecommendation(in: modelContext)
            recommendation = generated
            receipts = try recommendationService.receipts(for: generated, in: modelContext)
            message = nil
        } catch LocalRecommendationError.needsMoreLogs {
            message = "Log more albums first."
        } catch LocalRecommendationError.noCandidates {
            message = "No local picks left."
        } catch {
            message = "Could not generate Tonight's Pick."
        }
    }

    @MainActor
    private func submit(_ feedbackType: RecommendationFeedbackType, for recommendation: Recommendation) async {
        isWorking = true
        defer {
            isWorking = false
        }

        do {
            try recommendationService.submitFeedback(feedbackType, for: recommendation, in: modelContext)
            self.recommendation = nil
            receipts = []
            message = "Feedback saved. You can generate the next eligible pick."
        } catch {
            message = "Could not save feedback."
        }
    }
}

#Preview("Active Pick") {
    NavigationStack {
        TonightPickView()
    }
    .modelContainer(PreviewData.activeRecommendationContainer)
}

#Preview("Cold Start") {
    NavigationStack {
        TonightPickView()
    }
    .modelContainer(PreviewData.coldStartRecommendationContainer)
}
