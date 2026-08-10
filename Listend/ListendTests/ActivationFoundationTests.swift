//
//  ActivationFoundationTests.swift
//  ListendTests
//
//  Created by Codex on 8/7/26.
//

import Foundation
import Testing

#if canImport(MusicKit)
import MusicKit
#endif

@testable import Listend

@MainActor
struct ActivationFoundationTests {
    @Test func freshUserSeesOnboarding() {
        let decision = OnboardingGateResolver.resolve(OnboardingGateInput(
            completedVersion: nil,
            logCount: 0
        ))

        #expect(decision == .showOnboarding)
    }

    @Test func completedCurrentOrNewerVersionShowsApp() {
        let currentDecision = OnboardingGateResolver.resolve(OnboardingGateInput(
            completedVersion: OnboardingVersion.current,
            logCount: 0
        ))
        let newerDecision = OnboardingGateResolver.resolve(OnboardingGateInput(
            completedVersion: OnboardingVersion.current + 1,
            logCount: 0
        ))

        #expect(currentDecision == .showApp)
        #expect(newerDecision == .showApp)
    }

    @Test func olderCompletedVersionSeesOnboarding() {
        let decision = OnboardingGateResolver.resolve(OnboardingGateInput(
            completedVersion: OnboardingVersion.current - 1,
            logCount: 0
        ))

        #expect(decision == .showOnboarding)
    }

    @Test func existingLogsShowAppWithoutCompletion() {
        let decision = OnboardingGateResolver.resolve(OnboardingGateInput(
            completedVersion: nil,
            logCount: 1
        ))

        #expect(decision == .showApp)
    }

    @Test func forceOnboardingOverridesLogsAndCompletion() {
        let decision = OnboardingGateResolver.resolve(OnboardingGateInput(
            completedVersion: OnboardingVersion.current,
            logCount: 4,
            forceOnboarding: true
        ))

        #expect(decision == .showOnboarding)
    }

    @Test func bypassOnboardingHasHighestPrecedence() {
        let decision = OnboardingGateResolver.resolve(OnboardingGateInput(
            completedVersion: nil,
            logCount: 0,
            forceOnboarding: true,
            bypassOnboarding: true
        ))

        #expect(decision == .showApp)
    }

    @Test func completionPersistsCurrentVersionAndNeverDowngrades() throws {
        let suiteName = "ActivationFoundationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = OnboardingPreferences(userDefaults: defaults)

        #expect(preferences.completedVersion == nil)

        preferences.markCompleted()
        #expect(preferences.completedVersion == OnboardingVersion.current)

        defaults.set(OnboardingVersion.current + 2, forKey: OnboardingPreferenceKey.completedVersion)
        preferences.markCompleted()
        #expect(preferences.completedVersion == OnboardingVersion.current + 2)
    }

    @Test func replayDoesNotMutateCompletion() throws {
        let suiteName = "ActivationReplayTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = OnboardingPreferences(userDefaults: defaults)

        preferences.markCompleted(presentationMode: .replay)

        #expect(preferences.completedVersion == nil)
        #expect(defaults.object(forKey: OnboardingPreferenceKey.completedVersion) == nil)

        let existingVersion = OnboardingVersion.current + 2
        defaults.set(existingVersion, forKey: OnboardingPreferenceKey.completedVersion)
        preferences.markCompleted(
            version: existingVersion + 1,
            presentationMode: .replay
        )

        #expect(preferences.completedVersion == existingVersion)
    }

    @Test func launchConfigurationParsesGateAndAuthorizationArguments() {
        let configuration = ActivationLaunchConfiguration(arguments: [
            "Listend",
            ActivationLaunchArgument.uiTesting,
            ActivationLaunchArgument.resetUITestingData,
            ActivationLaunchArgument.forceOnboarding,
            ActivationLaunchArgument.bypassOnboarding,
            ActivationLaunchArgument.appleMusicAuthorizationInitialState,
            AppleMusicAuthorizationState.restricted.rawValue,
            ActivationLaunchArgument.appleMusicAuthorizationRequestResult,
            AppleMusicAuthorizationState.denied.rawValue
        ])

        #expect(configuration.isUITesting)
        #expect(configuration.shouldResetUITestingData)
        #expect(configuration.forceOnboarding)
        #expect(configuration.bypassOnboarding)
        #expect(configuration.appleMusicAuthorizationInitialState == .restricted)
        #expect(configuration.appleMusicAuthorizationRequestResult == .denied)
    }

    @Test func malformedAuthorizationLaunchValueFallsBackToUnavailable() {
        let configuration = ActivationLaunchConfiguration(arguments: [
            "Listend",
            ActivationLaunchArgument.appleMusicAuthorizationInitialState,
            "future-status"
        ])

        #expect(configuration.appleMusicAuthorizationInitialState == .unavailable)
        #expect(configuration.appleMusicAuthorizationRequestResult == nil)
    }

    @Test func mockAuthorizationTransitionsAndCountsRequests() async {
        let service = MockAppleMusicAuthorizationService(
            initialState: .notDetermined,
            requestResult: .denied
        )

        #expect(service.currentState == .notDetermined)
        #expect(service.requestCount == 0)

        let firstResult = await service.requestAuthorization()
        let secondResult = await service.requestAuthorization()

        #expect(firstResult == .denied)
        #expect(secondResult == .denied)
        #expect(service.currentState == .denied)
        #expect(service.requestCount == 2)
    }

    @Test func unavailableAuthorizationServiceAlwaysReturnsUnavailable() async {
        let service = UnavailableAppleMusicAuthorizationService()

        #expect(service.currentState == .unavailable)
        #expect(await service.requestAuthorization() == .unavailable)
    }

    #if canImport(MusicKit)
    @Test func musicKitAuthorizationStatusesMapExplicitly() {
        #expect(AppleMusicAuthorizationState(musicAuthorizationStatus: .notDetermined) == .notDetermined)
        #expect(AppleMusicAuthorizationState(musicAuthorizationStatus: .authorized) == .authorized)
        #expect(AppleMusicAuthorizationState(musicAuthorizationStatus: .denied) == .denied)
        #expect(AppleMusicAuthorizationState(musicAuthorizationStatus: .restricted) == .restricted)
    }
    #endif

    @Test func settingsPresentationCoversEveryAuthorizationState() {
        let notDetermined = AppleMusicAuthorizationPresentation(state: .notDetermined)
        #expect(notDetermined.statusText == "Not Connected")
        #expect(notDetermined.action == .connect)
        #expect(notDetermined.detailText != nil)

        let authorized = AppleMusicAuthorizationPresentation(state: .authorized)
        #expect(authorized.statusText == "Connected")
        #expect(authorized.action == nil)
        #expect(authorized.detailText == nil)

        let denied = AppleMusicAuthorizationPresentation(state: .denied)
        #expect(denied.statusText == "Access Denied")
        #expect(denied.action == .openSystemSettings)
        #expect(denied.detailText != nil)

        let restricted = AppleMusicAuthorizationPresentation(state: .restricted)
        #expect(restricted.statusText == "Restricted")
        #expect(restricted.action == nil)
        #expect(restricted.detailText != nil)

        let unavailable = AppleMusicAuthorizationPresentation(state: .unavailable)
        #expect(unavailable.statusText == "Unavailable")
        #expect(unavailable.action == nil)
        #expect(unavailable.detailText != nil)

        #expect(AppleMusicAuthorizationState.allCases.count == 5)
        #expect(AppleMusicAuthorizationSettingsAction.connect.title == "Connect")
        #expect(AppleMusicAuthorizationSettingsAction.openSystemSettings.title == "Open System Settings")
    }
}
