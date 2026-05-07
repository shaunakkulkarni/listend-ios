//
//  ContentView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    private let catalogService: AlbumCatalogServiceProtocol
    private let recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol
    @State private var didSeedData = false

    init(
        catalogService: AlbumCatalogServiceProtocol = MockAlbumCatalogService(),
        recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol = MockRecentlyPlayedAlbumService()
    ) {
        self.catalogService = catalogService
        self.recentlyPlayedAlbumService = recentlyPlayedAlbumService
    }

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(
                    catalogService: catalogService,
                    recentlyPlayedAlbumService: recentlyPlayedAlbumService
                )
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }
            .accessibilityIdentifier("homeTab")

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
        .task {
            guard !didSeedData else {
                return
            }

            didSeedData = true
            SeedData.seedIfNeeded(in: modelContext)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self, SoundPrintPersona.self, Recommendation.self, RecommendationReceipt.self, RecommendationFeedback.self], inMemory: true)
        .environment(SoundPrintProfileRefreshCoordinator())
}
