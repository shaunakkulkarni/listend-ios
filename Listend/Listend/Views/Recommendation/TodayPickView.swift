//
//  TodayPickView.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

import SwiftUI
import SwiftData

struct TodayPickView: View {
    @AppStorage(TodayPickPreferenceKey.recommendationMode) private var recommendationModeRawValue = TodayPickRecommendationMode.default.rawValue
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LogEntry.loggedAt, order: .reverse) private var logs: [LogEntry]
    @Query(sort: \Recommendation.createdAt, order: .reverse) private var recommendations: [Recommendation]

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

                savedPicksSection
            }
            .padding(.horizontal, ListendSpacing.lg)
            .padding(.top, ListendSpacing.lg)
            .padding(.bottom, 90)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.listendPaper)
        .navigationTitle("Today's Pick")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    TodayPickSettingsView()
                } label: {
                    Label("Today’s Pick Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("todayPickSettingsLink")
            }
        }
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

                Label(
                    TodayPickMatchQuality(confidence: recommendation.confidence).label,
                    systemImage: "checkmark.seal.fill"
                )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.listendAccent)
                    .accessibilityIdentifier("todayPickMatchQualityText")

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

    @ViewBuilder
    private var savedPicksSection: some View {
        if !savedRecommendations.isEmpty {
            VStack(alignment: .leading, spacing: ListendSpacing.sm) {
                Text("Saved Picks")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("savedPicksSectionTitle")

                ListendObjectCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(savedRecommendations.enumerated()), id: \.element.id) { index, savedRecommendation in
                            if let album = savedRecommendation.album {
                                NavigationLink {
                                    AlbumDetailView(album: albumSearchResult(from: album))
                                } label: {
                                    SavedPickRow(album: album)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open saved pick \(album.title) by \(album.artistName)")
                                .accessibilityIdentifier("savedPickLink-\(savedRecommendation.id.uuidString)")

                                if index < savedRecommendations.count - 1 {
                                    Divider()
                                        .background(Color.listendHairline)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var savedRecommendations: [Recommendation] {
        recommendations.filter {
            $0.status == RecommendationStatus.saved.rawValue && $0.album != nil
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

    private func albumSearchResult(from album: Album) -> AlbumSearchResult {
        AlbumSearchResult(
            id: album.appleMusicID ?? "local:\(album.id.uuidString)",
            title: album.title,
            artistName: album.artistName,
            releaseYear: album.releaseYear,
            genreName: album.genreName,
            artworkURL: album.artworkURL
        )
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
            let generated = try await recommendationService.currentOrGenerateRecommendation(
                in: modelContext,
                mode: TodayPickRecommendationMode(rawValue: recommendationModeRawValue)
            )
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
            if feedbackType == .savedForLater {
                message = "Saved to Saved Picks. You can generate another pick."
            } else {
                message = eligibility.isEligible
                    ? "Feedback saved. You can generate the next eligible pick."
                    : "Feedback saved. \(eligibility.progressDescription)"
            }
        } catch {
            message = "Could not save feedback."
        }
    }
}

private struct SavedPickRow: View {
    let album: Album

    var body: some View {
        HStack(spacing: ListendSpacing.md) {
            AlbumArtworkView(
                artworkURL: album.artworkURL,
                size: 52,
                albumTitle: album.title
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(album.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(album.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: ListendSpacing.sm)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, ListendSpacing.sm)
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
