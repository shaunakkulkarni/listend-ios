//
//  OnboardingFoundation.swift
//  Listend
//
//  Created by Codex on 8/7/26.
//

import Foundation

enum OnboardingPreferenceKey {
    static let completedVersion = "onboarding.completedVersion"
}

enum OnboardingVersion {
    static let current = 1
}

enum OnboardingPresentationMode: Equatable {
    case firstRun
    case replay

    fileprivate var persistsCompletion: Bool {
        self == .firstRun
    }
}

struct OnboardingPreferences {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var completedVersion: Int? {
        (userDefaults.object(forKey: OnboardingPreferenceKey.completedVersion) as? NSNumber)?.intValue
    }

    func markCompleted(
        version: Int = OnboardingVersion.current,
        presentationMode: OnboardingPresentationMode = .firstRun
    ) {
        guard presentationMode.persistsCompletion else {
            return
        }

        let versionToStore = max(completedVersion ?? 0, version)
        userDefaults.set(versionToStore, forKey: OnboardingPreferenceKey.completedVersion)
    }

    func resetForUITesting() {
        userDefaults.removeObject(forKey: OnboardingPreferenceKey.completedVersion)
    }
}

struct OnboardingGateInput: Equatable {
    let completedVersion: Int?
    let currentVersion: Int
    let logCount: Int
    let forceOnboarding: Bool
    let bypassOnboarding: Bool

    init(
        completedVersion: Int?,
        currentVersion: Int = OnboardingVersion.current,
        logCount: Int,
        forceOnboarding: Bool = false,
        bypassOnboarding: Bool = false
    ) {
        self.completedVersion = completedVersion
        self.currentVersion = currentVersion
        self.logCount = logCount
        self.forceOnboarding = forceOnboarding
        self.bypassOnboarding = bypassOnboarding
    }
}

enum OnboardingGateDecision: Equatable {
    case showOnboarding
    case showApp
}

enum OnboardingGateResolver {
    static func resolve(_ input: OnboardingGateInput) -> OnboardingGateDecision {
        if input.bypassOnboarding {
            return .showApp
        }

        if input.forceOnboarding {
            return .showOnboarding
        }

        if input.logCount > 0 {
            return .showApp
        }

        if let completedVersion = input.completedVersion,
           completedVersion >= input.currentVersion {
            return .showApp
        }

        return .showOnboarding
    }
}
