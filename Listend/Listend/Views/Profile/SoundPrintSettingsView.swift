//
//  SoundPrintSettingsView.swift
//  Listend
//

import SwiftUI
import SwiftData

struct SoundPrintSettingsView: View {
    @AppStorage(SoundPrintPreferenceKey.preferAppleIntelligence) private var preferAppleIntelligence = true
    @AppStorage(SoundPrintPreferenceKey.reflectionNeedsRefresh) private var reflectionNeedsRefresh = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.soundPrintProvider) private var soundPrintProvider
    @Environment(SoundPrintProfileRefreshCoordinator.self) private var soundPrintRefreshCoordinator
    @Query private var logs: [LogEntry]
    @Query(sort: \SoundPrintPersona.generatedAt, order: .reverse) private var personas: [SoundPrintPersona]

    @State private var isShowingDetail = false

    private let availability: SoundPrintAppleIntelligenceAvailability

    init(availability: SoundPrintAppleIntelligenceAvailability = .current) {
        self.availability = availability
    }

    var body: some View {
        List {
            Section("Reflection status") {
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

                    HStack(alignment: .firstTextBaseline) {
                        Text("Last successful generator")
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

            Section("Apple Intelligence") {
                if availability.isToggleVisible {
                    Toggle("Prefer Apple Intelligence", isOn: $preferAppleIntelligence)
                        .accessibilityIdentifier("preferAppleIntelligenceToggle")

                    Text("This preference applies only when you explicitly create or update a reflection. It never replaces your current reflection automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
            }

            if canGenerateReflection {
                Section {
                    Button {
                        Task {
                            await soundPrintRefreshCoordinator.generateReflection(in: modelContext, provider: soundPrintProvider)
                        }
                    } label: {
                        Label(generationActionTitle, systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(soundPrintRefreshCoordinator.isRebuilding)
                    .accessibilityIdentifier("soundPrintSettingsGenerationButton")
                }
            }

            Section("Technical details") {
                DisclosureGroup("Apple Intelligence availability", isExpanded: $isShowingDetail) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Availability")
                            .font(.subheadline.weight(.semibold))
                        Text(availability.headline)
                        Text(availability.technicalDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityValue(isShowingDetail ? "Expanded" : "Collapsed")
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

    private var displayState: SoundPrintSettingsDisplayState {
        SoundPrintSettingsDisplayState(
            preferAppleIntelligence: preferAppleIntelligence,
            latestSource: latestSource,
            availability: availability
        )
    }

    private var reflectionStatus: SoundPrintReflectionStatus {
        SoundPrintReflectionStatus.resolve(
            logCount: logs.count,
            representedLogCount: personas.first?.logCountAtGeneration,
            historyChanged: reflectionNeedsRefresh
        )
    }

    private var canGenerateReflection: Bool {
        switch reflectionStatus.phase {
        case .readyToCreate, .readyToUpdate:
            return true
        case .collecting, .current:
            return false
        }
    }

    private var generationActionTitle: String {
        if soundPrintRefreshCoordinator.lastError != nil {
            return "Try again"
        }

        return reflectionStatus.phase == .readyToCreate
            ? "Create my SoundPrint"
            : "Update my SoundPrint"
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
