//
//  ActivationLaunchConfiguration.swift
//  Listend
//
//  Created by Codex on 8/7/26.
//

import Foundation

enum ActivationLaunchArgument {
    static let uiTesting = "-ui-testing"
    static let resetUITestingData = "-reset-ui-testing-data"
    static let forceOnboarding = "-force-onboarding"
    static let bypassOnboarding = "-bypass-onboarding"
    static let appleMusicAuthorizationInitialState = "-apple-music-authorization-initial-state"
    static let appleMusicAuthorizationRequestResult = "-apple-music-authorization-request-result"
}

struct ActivationLaunchConfiguration: Equatable {
    let isUITesting: Bool
    let shouldResetUITestingData: Bool
    let forceOnboarding: Bool
    let bypassOnboarding: Bool
    let appleMusicAuthorizationInitialState: AppleMusicAuthorizationState?
    let appleMusicAuthorizationRequestResult: AppleMusicAuthorizationState?

    init(
        isUITesting: Bool,
        shouldResetUITestingData: Bool = false,
        forceOnboarding: Bool = false,
        bypassOnboarding: Bool = false,
        appleMusicAuthorizationInitialState: AppleMusicAuthorizationState? = nil,
        appleMusicAuthorizationRequestResult: AppleMusicAuthorizationState? = nil
    ) {
        self.isUITesting = isUITesting
        self.shouldResetUITestingData = shouldResetUITestingData
        self.forceOnboarding = forceOnboarding
        self.bypassOnboarding = bypassOnboarding
        self.appleMusicAuthorizationInitialState = appleMusicAuthorizationInitialState
        self.appleMusicAuthorizationRequestResult = appleMusicAuthorizationRequestResult
    }

    init(forceOnboarding: Bool, bypassOnboarding: Bool) {
        self.init(
            isUITesting: false,
            forceOnboarding: forceOnboarding,
            bypassOnboarding: bypassOnboarding
        )
    }

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isUITesting = arguments.contains(ActivationLaunchArgument.uiTesting)
        shouldResetUITestingData = arguments.contains(ActivationLaunchArgument.resetUITestingData)
        forceOnboarding = arguments.contains(ActivationLaunchArgument.forceOnboarding)
        bypassOnboarding = arguments.contains(ActivationLaunchArgument.bypassOnboarding)
        appleMusicAuthorizationInitialState = Self.authorizationState(
            following: ActivationLaunchArgument.appleMusicAuthorizationInitialState,
            in: arguments
        )
        appleMusicAuthorizationRequestResult = Self.authorizationState(
            following: ActivationLaunchArgument.appleMusicAuthorizationRequestResult,
            in: arguments
        )
    }

    private static func authorizationState(
        following argument: String,
        in arguments: [String]
    ) -> AppleMusicAuthorizationState? {
        guard let argumentIndex = arguments.firstIndex(of: argument) else {
            return nil
        }

        let valueIndex = arguments.index(after: argumentIndex)
        guard arguments.indices.contains(valueIndex) else {
            return .unavailable
        }

        return AppleMusicAuthorizationState(rawValue: arguments[valueIndex]) ?? .unavailable
    }
}
