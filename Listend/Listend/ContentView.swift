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

    @State private var selectedTab: ListendTab = .home

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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self, SoundPrintPersona.self, Recommendation.self, RecommendationReceipt.self, RecommendationFeedback.self, RecentlyPlayedAlbumSnapshot.self, AppleMusicRecentPlaySnapshot.self, AlbumTrack.self, TasteAvoidanceSignal.self], inMemory: true)
        .environment(SoundPrintProfileRefreshCoordinator())
}
