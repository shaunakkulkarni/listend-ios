//
//  SandboxSettingsView.swift
//  Listend
//

import SwiftUI
import SwiftData

struct SandboxSettingsView: View {
    @AppStorage(SandboxPreferenceKey.scenario) private var scenarioRawValue = SandboxScenario.default.rawValue
    @AppStorage(SandboxPreferenceKey.intelligenceProvider) private var intelligenceProviderRawValue = SandboxIntelligenceProvider.default.rawValue
    @Environment(\.modelContext) private var modelContext
    @State private var message: String?
    @State private var isLoading = false

    var body: some View {
        List {
            Section {
                Picker("Provider", selection: $intelligenceProviderRawValue) {
                    ForEach(SandboxIntelligenceProvider.allCases) { provider in
                        Text(provider.title).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.inline)

                Text(selectedIntelligenceProvider.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if selectedIntelligenceProvider == .onDevice {
                    Text(SoundPrintAppleIntelligenceAvailability.current.headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Intelligence provider")
            } footer: {
                Text("This affects only AI-backed features in Listend Sandbox. Album search and playback remain mocked, and TestFlight settings are separate.")
            }

            Section {
                Picker("Scenario", selection: $scenarioRawValue) {
                    ForEach(SandboxScenario.allCases) { scenario in
                        Text(scenario.title).tag(scenario.rawValue)
                    }
                }

                Text(selectedScenario.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Mock data")
            }

            Section {
                Button {
                    loadSelectedScenario()
                } label: {
                    Label("Reset and Load Scenario", systemImage: "arrow.counterclockwise")
                }
                .disabled(isLoading)
                .accessibilityIdentifier("sandboxResetAndLoadButton")

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("This deletes only Listend Sandbox data. Your TestFlight app and its library are separate.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.listendPaper)
        .navigationTitle("Sandbox Data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectedScenario: SandboxScenario {
        SandboxScenario(rawValue: scenarioRawValue)
    }

    private var selectedIntelligenceProvider: SandboxIntelligenceProvider {
        SandboxIntelligenceProvider(rawValue: intelligenceProviderRawValue)
    }

    private func loadSelectedScenario() {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try SandboxDataSeeder.resetAndSeed(selectedScenario, in: modelContext)
            message = "Loaded \(selectedScenario.title)."
        } catch {
            message = "Could not load the Sandbox scenario."
        }
    }
}

#Preview {
    NavigationStack {
        SandboxSettingsView()
    }
    .modelContainer(PreviewData.fullerProfileContainer)
}
