//
//  GeneralSettingsView.swift
//  Listend
//

import SwiftData
import SwiftUI
import UIKit

struct GeneralSettingsView: View {
    @Environment(\.appleMusicAuthorizationService) private var appleMusicAuthorizationService
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private let authorizationRefreshID: Int
    private let replayIntroduction: () -> Void

    @State private var authorizationState = AppleMusicAuthorizationState.unavailable
    @State private var isRequestingAuthorization = false

    init(
        authorizationRefreshID: Int = 0,
        replayIntroduction: @escaping () -> Void = {}
    ) {
        self.authorizationRefreshID = authorizationRefreshID
        self.replayIntroduction = replayIntroduction
    }

    var body: some View {
        List {
            musicSection

            Section("SoundPrint") {
                NavigationLink {
                    SoundPrintSettingsView()
                } label: {
                    SettingsDestinationLabel(
                        title: "SoundPrint Settings",
                        detail: "Reflection preferences, availability, and generation details"
                    )
                }
                .accessibilityIdentifier("generalSettingsSoundPrintLink")
            }

            Section("Getting Started") {
                Button("Replay Introduction", action: replayIntroduction)
                    .accessibilityIdentifier("replayIntroductionButton")
            }

            Section("Data & Privacy") {
                PrivacyStatement(
                    symbol: "internaldrive",
                    text: "Journal data is stored locally by Listend."
                )
                PrivacyStatement(
                    symbol: "apple.logo",
                    text: "Apple Music features use Apple Music services when invoked."
                )
                PrivacyStatement(
                    symbol: "sparkles",
                    text: "SoundPrint may use on-device Apple Intelligence when available and preferred, with Listend's local fallback."
                )
                PrivacyStatement(
                    symbol: "checkmark.shield",
                    text: "Logging remains available when optional integrations fail."
                )
            }

            Section("About") {
                LabeledContent("App", value: "Listend")
                LabeledContent("Version", value: appVersion)
                    .accessibilityIdentifier("installedVersionValue")
                LabeledContent("Build", value: buildNumber)
                    .accessibilityIdentifier("installedBuildValue")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.listendPaper)
        .navigationTitle("Settings")
        .task {
            refreshAuthorizationState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshAuthorizationState()
            }
        }
        .onChange(of: authorizationRefreshID) {
            refreshAuthorizationState()
        }
        .accessibilityIdentifier("generalSettingsView")
    }

    private var musicSection: some View {
        Section("Music") {
            VStack(alignment: .leading, spacing: ListendSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Apple Music")
                        .font(.headline)
                    Spacer(minLength: ListendSpacing.md)
                    Text(authorizationPresentation.statusText)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("appleMusicSettingsStatus")
                }

                if let detailText = authorizationPresentation.detailText {
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                authorizationAction
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var authorizationAction: some View {
        switch authorizationPresentation.action {
        case .connect:
            Button {
                requestAuthorization()
            } label: {
                HStack(spacing: ListendSpacing.sm) {
                    if isRequestingAuthorization {
                        ProgressView()
                    }
                    Text(isRequestingAuthorization ? "Connecting…" : "Connect")
                }
            }
            .disabled(isRequestingAuthorization)
            .accessibilityLabel(isRequestingAuthorization ? "Connecting Apple Music" : "Connect Apple Music")
            .accessibilityIdentifier("appleMusicConnectButton")

        case .openSystemSettings:
            Button("Open System Settings") {
                guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                    return
                }
                openURL(settingsURL)
            }
            .accessibilityIdentifier("appleMusicOpenSystemSettingsButton")

        case nil:
            EmptyView()
        }
    }

    private var authorizationPresentation: AppleMusicAuthorizationPresentation {
        AppleMusicAuthorizationPresentation(state: authorizationState)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    private func refreshAuthorizationState() {
        authorizationState = appleMusicAuthorizationService.currentState
    }

    private func requestAuthorization() {
        guard !isRequestingAuthorization else {
            return
        }

        isRequestingAuthorization = true
        Task {
            authorizationState = await appleMusicAuthorizationService.requestAuthorization()
            isRequestingAuthorization = false
        }
    }
}

private struct SettingsDestinationLabel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private struct PrivacyStatement: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.listendAccent)
        }
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
    .modelContainer(for: ListendModelSchema.modelTypes, inMemory: true)
    .environment(SoundPrintProfileRefreshCoordinator())
    .environment(\.appleMusicAuthorizationService, MockAppleMusicAuthorizationService())
}
