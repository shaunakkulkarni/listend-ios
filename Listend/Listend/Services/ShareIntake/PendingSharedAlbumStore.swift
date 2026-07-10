//
//  PendingSharedAlbumStore.swift
//  Listend
//

import Foundation

/// Shared constants for the Apple Music Share Sheet handoff.
///
/// These values are intentionally duplicated in the share extension's
/// `ShareViewController` because file-system-synchronized targets cannot share a
/// single source file without membership-exception plumbing. Keep the two in sync.
enum SharedAlbumIntake {
    /// App Group both the app and the share extension read/write.
    static let appGroupID = ListendAppGroup.identifier
    /// UserDefaults key holding the most recent shared Apple Music URL/text.
    static let pendingURLKey = "pendingSharedAlbumURL"
    /// Custom URL scheme the extension uses only to launch the host app.
    static let deepLinkScheme = SandboxMode.isEnabled ? "listend-sandbox" : "listend"
    /// Host component identifying a shared-album launch.
    static let deepLinkHost = "shared-album"
}

/// Recognizes the `listend://shared-album` launch trigger. Pure and unit-testable.
enum SharedAlbumDeepLink {
    static func isSharedAlbumURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == SharedAlbumIntake.deepLinkScheme
            && url.host?.lowercased() == SharedAlbumIntake.deepLinkHost
    }
}

/// Reads/writes the pending shared album payload in the App Group.
///
/// The share extension writes the raw Apple Music URL; the main app reads it once
/// and clears it, so a shared link is consumed exactly once and never re-opens on
/// relaunch. `UserDefaults` is injectable for testing.
struct PendingSharedAlbumStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: SharedAlbumIntake.appGroupID) ?? .standard
    }

    func save(_ payload: String) {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        defaults.set(trimmed, forKey: SharedAlbumIntake.pendingURLKey)
    }

    /// Returns the pending payload and clears it, guaranteeing single consumption.
    func consume() -> String? {
        guard let value = defaults.string(forKey: SharedAlbumIntake.pendingURLKey) else {
            return nil
        }

        defaults.removeObject(forKey: SharedAlbumIntake.pendingURLKey)

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func clear() {
        defaults.removeObject(forKey: SharedAlbumIntake.pendingURLKey)
    }
}
