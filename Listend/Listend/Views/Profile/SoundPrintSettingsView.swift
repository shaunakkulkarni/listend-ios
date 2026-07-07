//
//  SoundPrintSettingsView.swift
//  Listend
//

import SwiftUI
import SwiftData

struct SoundPrintSettingsView: View {
    @AppStorage(SoundPrintPreferenceKey.preferAppleIntelligence) private var preferAppleIntelligence = true
    @AppStorage(SoundPrintPreferenceKey.personaTone) private var personaToneRawValue = SoundPrintPersonaTone.default.rawValue
    @Environment(\.modelContext) private var modelContext
    @Environment(\.soundPrintProvider) private var soundPrintProvider
    @Environment(SoundPrintProfileRefreshCoordinator.self) private var soundPrintRefreshCoordinator
    @Query(sort: \SoundPrintPersona.generatedAt, order: .reverse) private var personas: [SoundPrintPersona]

    @State private var isShowingDetail = false

    private let availability: SoundPrintAppleIntelligenceAvailability

    init(availability: SoundPrintAppleIntelligenceAvailability = .current) {
        self.availability = availability
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: statusImage)
                            .foregroundStyle(statusColor)

                        Text(displayState.statusTitle)
                            .font(.headline)
                    }

                    Text(displayState.statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("Current generator")
                        Spacer()
                        if latestSource.userFacingTitle != nil {
                            SoundPrintGenerationSourceBadge(source: latestSource)
                        } else {
                            Text(displayState.currentGeneratorTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            .accessibilityIdentifier("soundPrintSettingsStatusSection")

            Section {
                Picker("Persona tone", selection: $personaToneRawValue) {
                    ForEach(SoundPrintPersonaTone.allCases) { tone in
                        Text(tone.userFacingTitle).tag(tone.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("personaTonePicker")

                Text(selectedTone.userFacingDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Voice")
            }
            .onChange(of: personaToneRawValue) {
                guard personas.first?.tone.rawValue != personaToneRawValue else {
                    return
                }

                Task {
                    await soundPrintRefreshCoordinator.refreshProfile(in: modelContext, provider: soundPrintProvider)
                }
            }

            Section {
                if availability.isToggleVisible {
                    Toggle("Prefer Apple Intelligence for SoundPrint", isOn: $preferAppleIntelligence)
                        .accessibilityIdentifier("preferAppleIntelligenceToggle")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Apple Intelligence is not available for SoundPrint on this device.")
                            .font(.subheadline)
                        Text("Listend will keep SoundPrint available with the local fallback.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("appleIntelligenceUnsupportedMessage")
                }

                Button {
                    Task {
                        await soundPrintRefreshCoordinator.refreshProfile(in: modelContext, provider: soundPrintProvider)
                    }
                } label: {
                    Label("Try Apple Intelligence Again", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(soundPrintRefreshCoordinator.isRebuilding)
                .accessibilityIdentifier("tryAppleIntelligenceAgainButton")
            }

            Section {
                DisclosureGroup("Why am I seeing this?", isExpanded: $isShowingDetail) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(availability.headline)
                        Text(availability.technicalDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("appleIntelligenceDetailDisclosure")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.listendPaper)
        .navigationTitle("SoundPrint Settings")
    }

    private var latestSource: SoundPrintGenerationSource {
        personas.first?.generationSource ?? .unknown
    }

    private var selectedTone: SoundPrintPersonaTone {
        SoundPrintPersonaTone(rawValue: personaToneRawValue)
    }

    private var displayState: SoundPrintSettingsDisplayState {
        SoundPrintSettingsDisplayState(
            preferAppleIntelligence: preferAppleIntelligence,
            latestSource: latestSource,
            availability: availability
        )
    }

    private var statusImage: String {
        switch latestSource {
        case .foundationModels:
            return "sparkles"
        case .localFallback:
            return "waveform.path"
        case .unavailable:
            return "exclamationmark.triangle"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        latestSource == .foundationModels ? Color.listendAccent : Color.listendMutedInk
    }
}

#Preview {
    NavigationStack {
        SoundPrintSettingsView()
    }
    .modelContainer(PreviewData.fullerProfileContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}
