//
//  ShareViewController.swift
//  ListendShareExtension
//
//  Collects a shared Apple Music URL (or text), stashes it in the App Group,
//  and launches the main Listend app to continue into the existing log flow.
//  It never presents a log UI of its own.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    // Duplicated from the app's `SharedAlbumIntake` — file-system-synchronized
    // targets can't share one source file. Keep these in sync.
    private let appGroupID = "group.com.shaunakkulkarni.Listend"
    private let pendingURLKey = "pendingSharedAlbumURL"
    private let hostAppURL = URL(string: "listend://shared-album")

    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await processSharedItem() }
    }

    private func configureUI() {
        view.backgroundColor = .systemBackground

        statusLabel.text = "Opening this album in Listend…"
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])
    }

    private func processSharedItem() async {
        guard let payload = await extractSharedString() else {
            // Nothing usable was shared; close without launching.
            complete()
            return
        }

        savePendingPayload(payload)

        if openHostApp() {
            complete()
        } else {
            // Fallback: could not launch Listend from the extension. The payload is
            // saved, so the user can open the app manually to continue.
            statusLabel.text = "Saved to Listend. Open Listend to continue."
            try? await Task.sleep(for: .seconds(2))
            complete()
        }
    }

    private func extractSharedString() async -> String? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            return nil
        }

        let providers = items.flatMap { $0.attachments ?? [] }

        // Prefer a URL attachment; fall back to plain text (which may contain a URL).
        if let url = await firstItem(in: providers, ofType: UTType.url) as? URL {
            return url.absoluteString
        }

        if let text = await firstItem(in: providers, ofType: UTType.plainText) as? String {
            return text
        }

        return nil
    }

    private func firstItem(in providers: [NSItemProvider], ofType type: UTType) async -> NSSecureCoding? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let item = try? await provider.loadItem(forTypeIdentifier: type.identifier, options: nil) {
                return item
            }
        }

        return nil
    }

    private func savePendingPayload(_ payload: String) {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty, let defaults = UserDefaults(suiteName: appGroupID) else {
            return
        }

        defaults.set(trimmed, forKey: pendingURLKey)
    }

    /// Opens the containing app via the responder chain. Returns whether a
    /// `UIApplication` responder that could open the URL was found.
    private func openHostApp() -> Bool {
        guard let hostAppURL else {
            return false
        }

        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self

        while let current = responder {
            if current.responds(to: selector) {
                current.perform(selector, with: hostAppURL)
                return true
            }

            responder = current.next
        }

        return false
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
