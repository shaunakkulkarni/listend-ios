//
//  TodayPickView.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

import SwiftUI
import SwiftData

struct TodayPickView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LogEntry.loggedAt, order: .reverse) private var logs: [LogEntry]

    private let recommendationService: LocalRecommendationService

    @State private var recommendation: Recommendation?
    @State private var receipts: [RecommendationReceipt] = []
    @State private var message: String?
    @State private var isWorking = false

    init(
        catalogService: AlbumCatalogServiceProtocol = MockAlbumCatalogService(),
        appleMusicRecommendationService: AppleMusicRecommendationServiceProtocol? = nil
    ) {
        recommendationService = LocalRecommendationService(
            catalogService: catalogService,
            appleMusicService: appleMusicRecommendationService
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ListendSpacing.xl) {
                Text("One album. With receipts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let recommendation {
                    recommendationCard(recommendation)

                    Text(recommendation.explanationText)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    receiptsSection

                    feedbackRow(recommendation)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, ListendSpacing.lg)
            .padding(.top, ListendSpacing.lg)
            .padding(.bottom, 90)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.listendPaper)
        .navigationTitle("Today's Pick")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadActiveRecommendation()
        }
    }

    private func recommendationCard(_ recommendation: Recommendation) -> some View {
        ListendObjectCard {
            VStack(alignment: .leading, spacing: ListendSpacing.md) {
                HStack {
                    Spacer(minLength: 0)
                    AlbumArtworkView(
                        artworkURL: recommendation.album?.artworkURL,
                        size: 220,
                        albumTitle: recommendation.album?.title
                    )
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.album?.title ?? "Unknown Album")
                        .font(.system(.title2, design: .serif).weight(.semibold))
                        .accessibilityIdentifier("todayPickStateText")
                    Text(recommendation.album?.artistName ?? "Unknown Artist")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    metadata(for: recommendation)
                }

                Label(confidenceText(for: recommendation), systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.listendAccent)

                Text(freshnessText(for: recommendation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("todayPickFreshnessText")

                if let album = recommendation.album {
                    AlbumPreviewControl(lookup: AlbumPreviewLookup(album: album))
                }
            }
        }
    }

    @ViewBuilder
    private var receiptsSection: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.sm) {
            Text("Receipts")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if receipts.isEmpty {
                Text("No receipts saved for this pick.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(receipts.enumerated()), id: \.element.id) { index, receipt in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(receipt.snippet)
                                .font(.subheadline)
                            Text("\(receipt.sourceAlbumTitle) - \(receipt.sourceArtistName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)

                        if index < receipts.count - 1 {
                            Divider()
                                .background(Color.listendHairline)
                        }
                    }
                }
            }
        }
    }

    private func feedbackRow(_ recommendation: Recommendation) -> some View {
        HStack(spacing: ListendSpacing.sm) {
            feedbackButton(
                systemImage: "hand.thumbsup",
                label: "Like recommendation",
                identifier: "likeRecommendationButton"
            ) {
                submit(.liked, for: recommendation)
            }

            feedbackButton(
                systemImage: "bookmark",
                label: "Save recommendation for later",
                identifier: "saveRecommendationButton"
            ) {
                submit(.savedForLater, for: recommendation)
            }

            feedbackButton(
                systemImage: "checkmark.circle",
                label: "Mark recommendation as listened",
                identifier: "listenedRecommendationButton"
            ) {
                submit(.listened, for: recommendation)
            }

            feedbackButton(
                systemImage: "xmark",
                label: "Dismiss recommendation",
                identifier: "dismissRecommendationButton"
            ) {
                submit(.dismissed, for: recommendation)
            }
        }
    }

    private func feedbackButton(
        systemImage: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.bordered)
        .disabled(isWorking)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.lg) {
            ContentUnavailableView(
                emptyTitle,
                systemImage: emptySystemImage,
                description: Text(emptyDescription)
            )

            Button {
                generateRecommendation()
            } label: {
                Label("Find Today's Pick", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking || !eligibility.isEligible)
            .accessibilityIdentifier("findTodayPickButton")

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("todayPickMessageText")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var eligibility: TodayPickEligibility {
        TodayPickEligibility(logs: logs)
    }

    private var emptyTitle: String {
        eligibility.isEligible ? "No Active Pick" : "Log More Albums First"
    }

    private var emptySystemImage: String {
        eligibility.isEligible ? "sparkles" : "music.note.list"
    }

    private var emptyDescription: String {
        eligibility.isEligible ? "Generate one pick backed by your own logs." : eligibility.lockedDescription
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

    private func freshnessText(for recommendation: Recommendation) -> String {
        if recommendation.freshnessStatus == RecommendationFreshnessStatus.appleFreshnessChecked.rawValue {
            return "Checked against Apple Music library and recent plays."
        }

        return "Apple Music freshness was unavailable, so this pick is based on your Listend logs."
    }

    @MainActor
    private func loadActiveRecommendation() async {
        do {
            recommendation = try recommendationService.activeRecommendation(in: modelContext)
            if let recommendation {
                receipts = try recommendationService.receipts(for: recommendation, in: modelContext)
            }
        } catch {
            message = "Could not load Today's Pick."
        }
    }

    private func generateRecommendation() {
        guard !isWorking else {
            return
        }

        Task {
            await generateRecommendationAsync()
        }
    }

    @MainActor
    private func generateRecommendationAsync() async {
        guard !isWorking else {
            return
        }

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
            message = eligibility.lockedDescription
        } catch LocalRecommendationError.noCandidates {
            message = "No picks left."
        } catch {
            message = "Could not generate Today's Pick."
        }
    }

    private func submit(_ feedbackType: RecommendationFeedbackType, for recommendation: Recommendation) {
        guard !isWorking else {
            return
        }

        Task {
            await submitAsync(feedbackType, for: recommendation)
        }
    }

    @MainActor
    private func submitAsync(_ feedbackType: RecommendationFeedbackType, for recommendation: Recommendation) async {
        guard !isWorking else {
            return
        }

        isWorking = true
        defer {
            isWorking = false
        }

        do {
            try recommendationService.submitFeedback(feedbackType, for: recommendation, in: modelContext)
            self.recommendation = nil
            receipts = []
            message = eligibility.isEligible
                ? "Feedback saved. You can generate the next eligible pick."
                : "Feedback saved. \(eligibility.progressDescription)"
        } catch {
            message = "Could not save feedback."
        }
    }
}

#Preview("Active Pick") {
    NavigationStack {
        TodayPickView()
    }
    .modelContainer(PreviewData.activeRecommendationContainer)
}

#Preview("Cold Start") {
    NavigationStack {
        TodayPickView()
    }
    .modelContainer(PreviewData.coldStartRecommendationContainer)
}
