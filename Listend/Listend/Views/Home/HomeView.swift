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

    @Query(sort: \Album.title) private var albums: [Album]
    @Query(sort: \LogEntry.loggedAt, order: .reverse) private var logs: [LogEntry]
    @Query(sort: \TasteDimension.weight, order: .reverse) private var dimensions: [TasteDimension]
    @Query(sort: \SoundPrintPersona.generatedAt, order: .reverse) private var personas: [SoundPrintPersona]
    @Query(sort: \Recommendation.createdAt, order: .reverse) private var recommendations: [Recommendation]
    @State private var isShowingNewLog = false
    @State private var albumForNewLog: Album?
    @State private var recentlyPlayedAlbums: [AlbumSearchResult] = []
    @State private var isLoadingRecentlyPlayed = false
    @State private var didLoadRecentlyPlayed = false
    @State private var recentlyPlayedErrorMessage: String?
    @State private var albumForRecentLog: Album?

    init(
        catalogService: AlbumCatalogServiceProtocol = MockAlbumCatalogService(),
        recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol = MockRecentlyPlayedAlbumService()
    ) {
        self.catalogService = catalogService
        self.recentlyPlayedAlbumService = recentlyPlayedAlbumService
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HomeHeader(
                    logCount: logs.count,
                    averageRatingText: averageRatingText,
                    latestLogDate: logs.first?.loggedAt,
                    addLog: showNewLog
                )

                if canShowTonightPick {
                    NavigationLink {
                        TonightPickView(catalogService: catalogService)
                    } label: {
                        TonightPickModule(
                            title: tonightPickTitle,
                            subtitle: tonightPickSubtitle,
                            isActive: activeRecommendation != nil
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tonightPickLink")
                }

                RecentlyPlayedAlbumsSection(
                    albums: recentlyPlayedAlbums,
                    isLoading: isLoadingRecentlyPlayed,
                    didLoad: didLoadRecentlyPlayed,
                    errorMessage: recentlyPlayedErrorMessage,
                    loadAlbums: requestRecentlyPlayedAlbums,
                    selectAlbum: startRecentLog
                )

                if let currentPersona {
                    NavigationLink {
                        SoundPrintProfileView()
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
        .background(Color(.systemGroupedBackground))
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

    private var canShowTonightPick: Bool {
        activeRecommendation != nil || logs.contains { log in
            log.album != nil && !log.isNegativeSignal && log.rating >= 4.0
        }
    }

    private var tonightPickTitle: String {
        activeRecommendation?.album?.title ?? "Find Tonight's Pick"
    }

    private var tonightPickSubtitle: String {
        if let album = activeRecommendation?.album {
            return "\(album.artistName) is ready when you are."
        }

        return "Generate one pick with receipts."
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
            recentlyPlayedAlbums = albums
            didLoadRecentlyPlayed = true
        } catch {
            recentlyPlayedAlbums = []
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

private struct HomeHeader: View {
    let logCount: Int
    let averageRatingText: String
    let latestLogDate: Date?
    let addLog: () -> Void

    var body: some View {
        EditorialSurface {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Listend")
                        .font(.system(.largeTitle, design: .serif).weight(.bold))
                    Text("A quiet place for the albums that stayed with you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        HomeStatPill(title: "Logs", value: logCount.formatted(), systemImage: "music.note.list")
                        HomeStatPill(title: "Average", value: averageRatingText, systemImage: "star.fill")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HomeStatPill(title: "Logs", value: logCount.formatted(), systemImage: "music.note.list")
                        HomeStatPill(title: "Average", value: averageRatingText, systemImage: "star.fill")
                    }
                }

                HStack(alignment: .center, spacing: 12) {
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
}

private struct HomeStatPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.secondary.opacity(0.10), in: Capsule())
    }
}

private struct TonightPickModule: View {
    let title: String
    let subtitle: String
    let isActive: Bool

    var body: some View {
        EditorialSurface(isInteractive: true) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: isActive ? "sparkles" : "moon.stars")
                    .font(.title2)
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Tonight's Pick")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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
        EditorialSurface(isInteractive: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(Color.accentColor)
                    Text("SoundPrint")
                        .font(.headline)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

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
        EditorialSurface(isInteractive: true) {
            HStack(alignment: .center, spacing: 12) {
                AlbumArtworkView(artworkURL: log.album?.artworkURL, size: 48)

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
                            .foregroundStyle(.yellow)

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

private struct RecentlyPlayedAlbumsSection: View {
    let albums: [AlbumSearchResult]
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
                .font(.subheadline.weight(.semibold))
                .disabled(isLoading)
                .accessibilityIdentifier("loadRecentlyPlayedAlbumsButton")
            }

            if albums.isEmpty {
                RecentlyPlayedEmptyState(
                    isLoading: isLoading,
                    didLoad: didLoad,
                    errorMessage: errorMessage,
                    loadAlbums: loadAlbums
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(albums) { album in
                            Button {
                                selectAlbum(album)
                            } label: {
                                RecentlyPlayedAlbumRow(album: album)
                                    .frame(width: 250)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("recentlyPlayedAlbum-\(album.catalogID)")
                        }
                    }
                }
                .scrollClipDisabled()

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
                        .foregroundStyle(Color.accentColor)
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
                .listendProminentButtonStyle()
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
    let album: AlbumSearchResult

    var body: some View {
        EditorialSurface(isInteractive: true) {
            VStack(alignment: .leading, spacing: 10) {
                AlbumArtworkView(artworkURL: album.artworkURL, size: 56)

                VStack(alignment: .leading, spacing: 5) {
                    Text(album.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(album.artistName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    metadata
                }

                HStack {
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var metadata: some View {
        HStack(spacing: 8) {
            if let releaseYear = album.releaseYear {
                Text(String(releaseYear))
            }

            if let genreName = album.genreName {
                Text(genreName)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

#Preview("Active Dashboard") {
    NavigationStack {
        HomeView()
    }
    .modelContainer(PreviewData.activeRecommendationContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Cold Start") {
    NavigationStack {
        HomeView()
    }
    .modelContainer(PreviewData.coldStartRecommendationContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}
