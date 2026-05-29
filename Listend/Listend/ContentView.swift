//
//  ContentView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    private let catalogService: AlbumCatalogServiceProtocol
    private let recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol
    private let appleMusicRecommendationService: AppleMusicRecommendationServiceProtocol?

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
        TabView {
            NavigationStack {
                HomeView(
                    catalogService: catalogService,
                    recentlyPlayedAlbumService: recentlyPlayedAlbumService,
                    appleMusicRecommendationService: appleMusicRecommendationService
                )
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .accessibilityIdentifier("homeTab")

            NavigationStack {
                LogsView()
            }
            .tabItem {
                Label("Logs", systemImage: "music.note.list")
            }
            .accessibilityIdentifier("logsTab")

            NavigationStack {
                SearchView(catalogService: catalogService)
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            .accessibilityIdentifier("searchTab")

            NavigationStack {
                ProfileView()
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .accessibilityIdentifier("profileTab")
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self, SoundPrintPersona.self, Recommendation.self, RecommendationReceipt.self, RecommendationFeedback.self, RecentlyPlayedAlbumSnapshot.self, AppleMusicRecentPlaySnapshot.self], inMemory: true)
        .environment(SoundPrintProfileRefreshCoordinator())
}
