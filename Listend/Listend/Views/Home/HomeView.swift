//
//  HomeView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    private let catalogService: AlbumCatalogServiceProtocol
    private let recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol
    private let appleMusicRecommendationService: AppleMusicRecommendationServiceProtocol?
    private let switchToProfileTab: () -> Void

    @Query(sort: \Album.title) private var albums: [Album]
    @Query(sort: \LogEntry.loggedAt, order: .reverse) private var logs: [LogEntry]
    @Query(sort: \TasteDimension.weight, order: .reverse) private var dimensions: [TasteDimension]
    @Query(sort: \SoundPrintPersona.generatedAt, order: .reverse) private var personas: [SoundPrintPersona]
    @Query(sort: \Recommendation.createdAt, order: .reverse) private var recommendations: [Recommendation]
    @Query(sort: \RecentlyPlayedAlbumSnapshot.sortOrder) private var cachedRecentlyPlayedAlbumSnapshots: [RecentlyPlayedAlbumSnapshot]
    @State private var isShowingNewLog = false
    @State private var albumForNewLog: Album?
    @State private var recentlyPlayedAlbums: [AlbumSearchResult] = []
    @State private var isLoadingRecentlyPlayed = false
    @State private var didLoadRecentlyPlayed = false
    @State private var recentlyPlayedErrorMessage: String?
    @State private var albumForRecentLog: Album?

    init(
        catalogService: AlbumCatalogServiceProtocol = MockAlbumCatalogService(),
        recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol = MockRecentlyPlayedAlbumService(),
        appleMusicRecommendationService: AppleMusicRecommendationServiceProtocol? = nil,
        switchToProfileTab: @escaping () -> Void = {}
    ) {
        self.catalogService = catalogService
        self.recentlyPlayedAlbumService = recentlyPlayedAlbumService
        self.appleMusicRecommendationService = appleMusicRecommendationService
        self.switchToProfileTab = switchToProfileTab
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HomeIdentityHeader(
                    logCount: logs.count,
                    averageRatingText: averageRatingText,
                    latestLogDate: logs.first?.loggedAt,
                    addLog: showNewLog
                )

                NavigationLink {
                    TodayPickView(
                        catalogService: catalogService,
                        appleMusicRecommendationService: appleMusicRecommendationService
                    )
                } label: {
                    TodayPickCard(
                        album: activeRecommendation?.album,
                        confidence: activeRecommendation?.confidence,
                        title: todayPickTitle,
                        subtitle: todayPickSubtitle,
                        isActive: activeRecommendation != nil
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("todayPickLink")

                RecentlyPlayedAlbumsSection(
                    items: displayedRecentlyPlayedItems,
                    isLoading: isLoadingRecentlyPlayed,
                    didLoad: didLoadRecentlyPlayed || !cachedRecentlyPlayedAlbumSnapshots.isEmpty,
                    errorMessage: recentlyPlayedErrorMessage,
                    loadAlbums: requestRecentlyPlayedAlbums,
                    selectAlbum: startRecentLog
                )

                if let currentPersona {
                    Button {
                        switchToProfileTab()
                    } label: {
                        SoundPrintSummaryModule(
                            persona: currentPersona,
                            topDimension: dimensions.first
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("homeSoundPrintLink")
                }

                LatestLogPreviewSection(log: logs.first)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Color.listendPaper)
        .navigationTitle("Listend")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(
            isPresented: $isShowingNewLog,
            onDismiss: {
                albumForNewLog = nil
            }
        ) {
            if let albumForNewLog {
                LogEntryEditorView(preselectedAlbum: albumForNewLog)
            } else {
                NavigationStack {
                    AlbumSelectionView(
                        catalogService: catalogService,
                        recentlyPlayedAlbumService: recentlyPlayedAlbumService
                    ) { album in
                        albumForNewLog = album
                    }
                }
            }
        }
        .sheet(item: $albumForRecentLog) { album in
            LogEntryEditorView(preselectedAlbum: album)
        }
    }

    private var currentPersona: SoundPrintPersona? {
        personas.first
    }

    private var activeRecommendation: Recommendation? {
        recommendations.first { $0.status == RecommendationStatus.active.rawValue }
    }

    private var todayPickEligibility: TodayPickEligibility {
        TodayPickEligibility(logs: logs)
    }

    @MainActor
    private var displayedRecentlyPlayedAlbums: [AlbumSearchResult] {
        if !recentlyPlayedAlbums.isEmpty {
            return recentlyPlayedAlbums
        }

        return cachedRecentlyPlayedAlbumSnapshots.map(RecentlyPlayedAlbumCache.albumSearchResult)
    }

    @MainActor
    private var displayedRecentlyPlayedItems: [RecentlyPlayedAlbumDisplayItem] {
        displayedRecentlyPlayedAlbums.prefix(6).map { album in
            RecentlyPlayedAlbumDisplayItem(
                album: album,
                isLogged: RecentlyPlayedAlbumLogState.isLogged(album, in: logs)
            )
        }
    }

    private var todayPickTitle: String {
        activeRecommendation?.album?.title ?? "Find Today's Pick"
    }

    private var todayPickSubtitle: String {
        if let album = activeRecommendation?.album {
            return "\(album.artistName) is ready when you are."
        }

        return todayPickEligibility.isEligible
            ? "Generate one pick with receipts."
            : todayPickEligibility.progressDescription
    }

    private var averageRatingText: String {
        guard !logs.isEmpty else {
            return "No ratings"
        }

        let average = logs.reduce(0) { $0 + $1.rating } / Double(logs.count)
        return average.formatted(.number.precision(.fractionLength(1)))
    }

    private func showNewLog() {
        albumForNewLog = nil
        isShowingNewLog = true
    }

    private func requestRecentlyPlayedAlbums() {
        Task {
            await loadRecentlyPlayedAlbums()
        }
    }

    @MainActor
    private func loadRecentlyPlayedAlbums() async {
        guard !isLoadingRecentlyPlayed else {
            return
        }

        isLoadingRecentlyPlayed = true
        recentlyPlayedErrorMessage = nil

        do {
            let albums = try await recentlyPlayedAlbumService.recentlyPlayedAlbums()
            try RecentlyPlayedAlbumCache.replaceCachedAlbums(with: albums, in: modelContext)
            recentlyPlayedAlbums = albums
            didLoadRecentlyPlayed = true
        } catch {
            didLoadRecentlyPlayed = true
            recentlyPlayedErrorMessage = "Could not load recently played albums. Check Apple Music access and try again."
        }

        isLoadingRecentlyPlayed = false
    }

    private func startRecentLog(_ album: AlbumSearchResult) {
        do {
            albumForRecentLog = try AlbumCacheUpserter.upsertAlbum(
                from: album,
                cachedAlbums: albums,
                in: modelContext
            )
        } catch {
            recentlyPlayedErrorMessage = "Could not prepare this album for logging."
        }
    }
}

private struct HomeIdentityHeader: View {
    let logCount: Int
    let averageRatingText: String
    let latestLogDate: Date?
    let addLog: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.lg) {
            VStack(alignment: .leading, spacing: ListendSpacing.xs) {
                Text("Listend")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                    .foregroundStyle(Color.listendInk)
                Text("A quiet place for the albums that stayed with you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: ListendSpacing.xxl) {
                HomeStatNumeral(value: logCount.formatted(), label: "Logs")
                HomeStatNumeral(value: averageRatingText, label: "Average")
            }

            HStack(alignment: .center, spacing: ListendSpacing.md) {
                Button(action: addLog) {
                    Label("Add Log", systemImage: "plus")
                }
                .listendProminentButtonStyle()
                .accessibilityIdentifier("addLogButton")

                if let latestLogDate {
                    Text("Last logged \(latestLogDate, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

private struct HomeStatNumeral: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .foregroundStyle(Color.listendInk)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TodayPickCard: View {
    let album: Album?
    let confidence: Double?
    let title: String
    let subtitle: String
    let isActive: Bool

    var body: some View {
        ListendObjectCard {
            HStack(alignment: .center, spacing: ListendSpacing.md) {
                if isActive {
                    AlbumArtworkView(artworkURL: album?.artworkURL, size: 64, albumTitle: album?.title)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: ListendRadius.artwork)
                            .fill(Color.listendAccentSoft)
                        Image(systemName: "sun.max")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("Today's Pick")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        if isActive, let confidence {
                            Text(confidence, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.listendAccent)
                        }
                    }
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SoundPrintSummaryModule: View {
    let persona: SoundPrintPersona
    let topDimension: TasteDimension?

    var body: some View {
        ListendObjectCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(.secondary)
                    Text("SoundPrint")
                        .font(.headline)
                    SoundPrintGenerationSourceBadge(source: persona.generationSource)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                SoundPrintPersonaToneBadge(tone: persona.tone)

                Text(persona.personaText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                if let topDimension {
                    Text("Current thread: \(topDimension.label)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("homeSoundPrintModule")
    }
}

private struct LatestLogPreviewSection: View {
    let log: LogEntry?

    var body: some View {
        if let log {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Latest Log")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Text("View all in Logs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    LogEntryDetailView(log: log)
                } label: {
                    LatestLogPreviewRow(log: log)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("latestLogPreviewLink")
            }
        }
    }
}

private struct LatestLogPreviewRow: View {
    let log: LogEntry

    var body: some View {
        ListendObjectCard {
            HStack(alignment: .center, spacing: 12) {
                AlbumArtworkView(artworkURL: log.album?.artworkURL, size: 56, albumTitle: log.album?.title)

                VStack(alignment: .leading, spacing: 5) {
                    Text(log.album?.title ?? "Unknown Album")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(log.album?.artistName ?? "Unknown Artist")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Label(ratingText, systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.listendAccent)

                        Text(log.loggedAt, format: .dateTime.month(.abbreviated).day().year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var ratingText: String {
        log.rating.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct RecentlyPlayedAlbumDisplayItem: Identifiable {
    let album: AlbumSearchResult
    let isLogged: Bool

    var id: String {
        album.id
    }
}

private struct RecentlyPlayedAlbumsSection: View {
    let items: [RecentlyPlayedAlbumDisplayItem]
    let isLoading: Bool
    let didLoad: Bool
    let errorMessage: String?
    let loadAlbums: () -> Void
    let selectAlbum: (AlbumSearchResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Text("Recently Played")
                    .font(.title3.weight(.bold))

                Spacer()

                Button(action: loadAlbums) {
                    Label(buttonTitle, systemImage: buttonSystemImage)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading)
                .accessibilityIdentifier("loadRecentlyPlayedAlbumsButton")
            }

            if items.isEmpty {
                RecentlyPlayedEmptyState(
                    isLoading: isLoading,
                    didLoad: didLoad,
                    errorMessage: errorMessage,
                    loadAlbums: loadAlbums
                )
            } else {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        if item.isLogged {
                            RecentlyPlayedAlbumRow(item: item)
                                .accessibilityIdentifier("recentlyPlayedAlbum-\(item.album.catalogID)")
                        } else {
                            Button {
                                selectAlbum(item.album)
                            } label: {
                                RecentlyPlayedAlbumRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recentlyPlayedAlbum-\(item.album.catalogID)")
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var buttonTitle: String {
        didLoad ? "Refresh" : "Load"
    }

    private var buttonSystemImage: String {
        isLoading ? "hourglass" : "arrow.clockwise"
    }
}

private struct RecentlyPlayedEmptyState: View {
    let isLoading: Bool
    let didLoad: Bool
    let errorMessage: String?
    let loadAlbums: () -> Void

    var body: some View {
        EditorialSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.headline)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button(action: loadAlbums) {
                    Label(isLoading ? "Loading" : "Load Recently Played", systemImage: isLoading ? "hourglass" : "music.note")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                .accessibilityIdentifier("recentlyPlayedEmptyStateLoadButton")
            }
        }
    }

    private var iconName: String {
        errorMessage == nil ? "music.note" : "exclamationmark.triangle"
    }

    private var title: String {
        if errorMessage != nil {
            return "Apple Music unavailable"
        }

        if didLoad {
            return "No recent albums"
        }

        return "Log from Apple Music"
    }

    private var message: String {
        if let errorMessage {
            return errorMessage
        }

        if didLoad {
            return "Albums you recently played in Apple Music will appear here."
        }

        return "Load your recently played albums when you want a faster way to start a log."
    }
}

private struct RecentlyPlayedAlbumRow: View {
    let item: RecentlyPlayedAlbumDisplayItem

    private var album: AlbumSearchResult {
        item.album
    }

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            AlbumArtworkView(artworkURL: album.artworkURL, size: 40)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(album.artistName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if item.isLogged {
                Label("Logged", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.10), in: Capsule())
            } else {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(minHeight: 54)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        }
    }
}

#Preview("Active Dashboard") {
    NavigationStack {
        HomeView()
    }
    .modelContainer(PreviewData.activeRecommendationContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Apple Intelligence SoundPrint") {
    NavigationStack {
        HomeView()
    }
    .modelContainer(PreviewData.appleIntelligencePersonaContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Cold Start") {
    NavigationStack {
        HomeView()
    }
    .modelContainer(PreviewData.coldStartRecommendationContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}
