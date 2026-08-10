//
//  AppleMusicAuthorizationService.swift
//  Listend
//
//  Created by Codex on 8/7/26.
//

import Foundation

#if canImport(MusicKit)
import MusicKit
#endif

enum AppleMusicAuthorizationState: String, CaseIterable, Equatable {
    case notDetermined
    case authorized
    case denied
    case restricted
    case unavailable
}

protocol AppleMusicAuthorizationServiceProtocol {
    var currentState: AppleMusicAuthorizationState { get }
    func requestAuthorization() async -> AppleMusicAuthorizationState
}

struct MusicKitAppleMusicAuthorizationService: AppleMusicAuthorizationServiceProtocol {
    var currentState: AppleMusicAuthorizationState {
        #if canImport(MusicKit)
        AppleMusicAuthorizationState(musicAuthorizationStatus: MusicAuthorization.currentStatus)
        #else
        .unavailable
        #endif
    }

    func requestAuthorization() async -> AppleMusicAuthorizationState {
        #if canImport(MusicKit)
        let status = await MusicAuthorization.request()
        return AppleMusicAuthorizationState(musicAuthorizationStatus: status)
        #else
        return .unavailable
        #endif
    }
}

struct UnavailableAppleMusicAuthorizationService: AppleMusicAuthorizationServiceProtocol {
    let currentState = AppleMusicAuthorizationState.unavailable

    func requestAuthorization() async -> AppleMusicAuthorizationState {
        .unavailable
    }
}

final class MockAppleMusicAuthorizationService: AppleMusicAuthorizationServiceProtocol {
    private(set) var currentState: AppleMusicAuthorizationState
    var requestResult: AppleMusicAuthorizationState
    private(set) var requestCount = 0

    init(
        initialState: AppleMusicAuthorizationState = .notDetermined,
        requestResult: AppleMusicAuthorizationState = .authorized
    ) {
        currentState = initialState
        self.requestResult = requestResult
    }

    func requestAuthorization() async -> AppleMusicAuthorizationState {
        requestCount += 1
        currentState = requestResult
        return currentState
    }
}

#if canImport(MusicKit)
extension AppleMusicAuthorizationState {
    init(musicAuthorizationStatus: MusicAuthorization.Status) {
        switch musicAuthorizationStatus {
        case .notDetermined:
            self = .notDetermined
        case .authorized:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .unavailable
        }
    }
}
#endif
