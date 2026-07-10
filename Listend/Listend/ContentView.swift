//
//  ContentView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI
import SwiftData

enum ListendTab: Hashable {
    case home
    case logs
    case search
    case profile
}

struct ContentView: View {
    private let catalogService: AlbumCatalogServiceProtocol
    private let recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol
    private let appleMusicRecommendationService: AppleMusicRecommendationServiceProtocol?
    private let pendingSharedAlbumStore = PendingSharedAlbumStore()

    @State private var selectedTab: ListendTab = .home
    @State private var sharedIntakeLink: SharedIntakeLink?

    init(
        catalogService: AlbumCatalogServiceProtocol = MockAlbumCatalogService(),
        recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol = MockRecentlyPlayedAlbumService(),
        appleMusicRecommendationService: AppleMusicRecommendationServiceProtocol? = nil
    ) {
        self.catalogService = catalogService
        self.recentlyPlayedAlbumService = recentlyPlayedAlbumService
        self.appleMusicRecommendationService = appleMusicRecommendationService
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(
                    catalogService: catalogService,
                    recentlyPlayedAlbumService: recentlyPlayedAlbumService,
                    appleMusicRecommendationService: appleMusicRecommendationService,
                    switchToProfileTab: { selectedTab = .profile }
                )
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .tag(ListendTab.home)
            .accessibilityIdentifier("homeTab")

            NavigationStack {
                LogsView()
            }
            .tabItem {
                Label("Logs", systemImage: "music.note.list")
            }
            .tag(ListendTab.logs)
            .accessibilityIdentifier("logsTab")

            NavigationStack {
                SearchView(catalogService: catalogService)
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .tag(ListendTab.search)
            .accessibilityIdentifier("searchTab")

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .tag(ListendTab.profile)
            .accessibilityIdentifier("profileTab")
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if SandboxMode.isEnabled {
                Text("SANDBOX · MOCK DATA")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.orange)
                    .accessibilityIdentifier("sandboxModeBanner")
            }
        }
        .onOpenURL(perform: handleOpenURL)
        .sheet(item: $sharedIntakeLink) { link in
            ShareIntakeView(
                catalogService: catalogService,
                prefilledText: link.text,
                autoResolveOnAppear: true
            )
        }
    }

    /// Handles the `listend://shared-album` launch from the share extension.
    /// Consumes the pending payload once (clearing it) so it never re-opens on
    /// relaunch, switches to Search, and reuses the existing intake sheet.
    private func handleOpenURL(_ url: URL) {
        guard SharedAlbumDeepLink.isSharedAlbumURL(url),
              let payload = pendingSharedAlbumStore.consume() else {
            return
        }

        selectedTab = .search
        sharedIntakeLink = SharedIntakeLink(text: payload)
    }
}

private struct SharedIntakeLink: Identifiable {
    let id = UUID()
    let text: String
}

#Preview {
    ContentView()
        .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self, SoundPrintPersona.self, Recommendation.self, RecommendationReceipt.self, RecommendationFeedback.self, RecentlyPlayedAlbumSnapshot.self, AppleMusicRecentPlaySnapshot.self, AlbumTrack.self, TasteAvoidanceSignal.self], inMemory: true)
        .environment(SoundPrintProfileRefreshCoordinator())
}
