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
    private let authorizationRefreshID: Int
    private let replayIntroduction: () -> Void

    @State private var selectedTab: ListendTab = .home
    @State private var profileNavigationPath = NavigationPath()
    @State private var profileNavigationStackID = UUID()

    init(
        catalogService: AlbumCatalogServiceProtocol = MockAlbumCatalogService(),
        recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol = MockRecentlyPlayedAlbumService(),
        appleMusicRecommendationService: AppleMusicRecommendationServiceProtocol? = nil,
        authorizationRefreshID: Int = 0,
        replayIntroduction: @escaping () -> Void = {}
    ) {
        self.catalogService = catalogService
        self.recentlyPlayedAlbumService = recentlyPlayedAlbumService
        self.appleMusicRecommendationService = appleMusicRecommendationService
        self.authorizationRefreshID = authorizationRefreshID
        self.replayIntroduction = replayIntroduction
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView(
                    catalogService: catalogService,
                    recentlyPlayedAlbumService: recentlyPlayedAlbumService,
                    appleMusicRecommendationService: appleMusicRecommendationService,
                    switchToProfileTab: {
                        profileNavigationPath = NavigationPath()
                        profileNavigationStackID = UUID()
                        selectedTab = .profile
                    }
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

            NavigationStack(path: $profileNavigationPath) {
                ProfileView(
                    authorizationRefreshID: authorizationRefreshID,
                    replayIntroduction: replayIntroduction
                )
            }
            .id(profileNavigationStackID)
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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: ListendModelSchema.modelTypes, inMemory: true)
        .environment(SoundPrintProfileRefreshCoordinator())
}
