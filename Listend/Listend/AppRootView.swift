//
//  AppRootView.swift
//  Listend
//

import SwiftData
import SwiftUI

struct AppRootView: View {
    @Query(sort: \LogEntry.loggedAt, order: .reverse) private var logs: [LogEntry]
    @AppStorage(OnboardingPreferenceKey.completedVersion) private var completedOnboardingVersion = 0

    private let catalogService: AlbumCatalogServiceProtocol
    private let recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol
    private let appleMusicRecommendationService: AppleMusicRecommendationServiceProtocol?
    private let launchConfiguration: ActivationLaunchConfiguration

    @State private var hasPresentedRequiredOnboarding = false
    @State private var didFinishRequiredOnboarding = false
    @State private var isReplayingIntroduction = false
    @State private var authorizationRefreshID = 0

    init(
        catalogService: AlbumCatalogServiceProtocol = MockAlbumCatalogService(),
        recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol = MockRecentlyPlayedAlbumService(),
        appleMusicRecommendationService: AppleMusicRecommendationServiceProtocol? = nil,
        launchConfiguration: ActivationLaunchConfiguration = ActivationLaunchConfiguration()
    ) {
        self.catalogService = catalogService
        self.recentlyPlayedAlbumService = recentlyPlayedAlbumService
        self.appleMusicRecommendationService = appleMusicRecommendationService
        self.launchConfiguration = launchConfiguration
    }

    var body: some View {
        Group {
            if shouldShowRequiredOnboarding {
                OnboardingView(
                    catalogService: catalogService,
                    recentlyPlayedAlbumService: recentlyPlayedAlbumService,
                    isReplay: false,
                    finish: finishRequiredOnboarding
                )
                .onAppear {
                    hasPresentedRequiredOnboarding = true
                }
            } else {
                ContentView(
                    catalogService: catalogService,
                    recentlyPlayedAlbumService: recentlyPlayedAlbumService,
                    appleMusicRecommendationService: appleMusicRecommendationService,
                    authorizationRefreshID: authorizationRefreshID,
                    replayIntroduction: {
                        isReplayingIntroduction = true
                    }
                )
                .onAppear {
                    backfillCompletionForExistingUserIfNeeded()
                }
            }
        }
        .fullScreenCover(isPresented: $isReplayingIntroduction, onDismiss: {
            authorizationRefreshID += 1
        }) {
            OnboardingView(
                catalogService: catalogService,
                recentlyPlayedAlbumService: recentlyPlayedAlbumService,
                isReplay: true,
                finish: {
                    isReplayingIntroduction = false
                }
            )
        }
    }

    private var shouldShowRequiredOnboarding: Bool {
        guard !didFinishRequiredOnboarding else {
            return false
        }

        if hasPresentedRequiredOnboarding {
            return true
        }

        return OnboardingGateResolver.resolve(
            OnboardingGateInput(
                completedVersion: completedOnboardingVersion > 0 ? completedOnboardingVersion : nil,
                currentVersion: OnboardingVersion.current,
                logCount: logs.count,
                forceOnboarding: launchConfiguration.forceOnboarding,
                bypassOnboarding: launchConfiguration.bypassOnboarding
            )
        ) == .showOnboarding
    }

    private func finishRequiredOnboarding() {
        completedOnboardingVersion = max(completedOnboardingVersion, OnboardingVersion.current)
        didFinishRequiredOnboarding = true
        hasPresentedRequiredOnboarding = false
    }

    private func backfillCompletionForExistingUserIfNeeded() {
        guard !logs.isEmpty,
              !launchConfiguration.forceOnboarding,
              !launchConfiguration.bypassOnboarding else {
            return
        }

        completedOnboardingVersion = max(completedOnboardingVersion, OnboardingVersion.current)
    }
}

#Preview("Fresh") {
    AppRootView(
        launchConfiguration: ActivationLaunchConfiguration(
            forceOnboarding: true,
            bypassOnboarding: false
        )
    )
    .modelContainer(for: ListendModelSchema.modelTypes, inMemory: true)
    .environment(SoundPrintProfileRefreshCoordinator())
}
