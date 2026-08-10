//
//  AppleMusicAuthorizationPresentation.swift
//  Listend
//
//  Created by Codex on 8/7/26.
//

enum AppleMusicAuthorizationSettingsAction: Equatable {
    case connect
    case openSystemSettings

    var title: String {
        switch self {
        case .connect:
            return "Connect"
        case .openSystemSettings:
            return "Open System Settings"
        }
    }
}

struct AppleMusicAuthorizationPresentation: Equatable {
    let statusText: String
    let detailText: String?
    let action: AppleMusicAuthorizationSettingsAction?

    init(state: AppleMusicAuthorizationState) {
        switch state {
        case .notDetermined:
            statusText = "Not Connected"
            detailText = "Connect Apple Music to bring in recently played albums and make logging faster."
            action = .connect
        case .authorized:
            statusText = "Connected"
            detailText = nil
            action = nil
        case .denied:
            statusText = "Access Denied"
            detailText = "Allow Apple Music access in system Settings to use recently played albums."
            action = .openSystemSettings
        case .restricted:
            statusText = "Restricted"
            detailText = "Apple Music access is restricted on this device."
            action = nil
        case .unavailable:
            statusText = "Unavailable"
            detailText = "Apple Music is unavailable on this device. Logging remains available."
            action = nil
        }
    }
}
