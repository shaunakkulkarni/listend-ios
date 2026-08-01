//
//  ProfileView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @AppStorage(SoundPrintPreferenceKey.reflectionNeedsRefresh) private var reflectionNeedsRefresh = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.soundPrintProvider) private var soundPrintProvider
    @Environment(SoundPrintProfileRefreshCoordinator.self) private var soundPrintRefreshCoordinator
    @Query private var logs: [LogEntry]
    @Query(sort: \SoundPrintPersona.generatedAt, order: .reverse) private var personas: [SoundPrintPersona]

    var body: some View {
        List {
            Section("Stats") {
                NavigationLink {
                    TasteInsightsView()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your Taste So Far")
                            .font(.headline)
                        Text(tasteInsightsSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("tasteInsightsLink")

                StatRow(title: "Total Logs", value: logs.count.formatted(), valueIdentifier: "totalLogsValueText")
                    .accessibilityIdentifier("totalLogsStat")
                StatRow(title: "Average Rating", value: averageRatingText, valueIdentifier: "averageRatingValueText")
                    .accessibilityIdentifier("averageRatingStat")
                StatRow(title: "Top Tags", value: topTagsText, valueIdentifier: "topTagsValueText")
                    .accessibilityIdentifier("topTagsStat")
            }

            Section("SoundPrint") {
                SoundPrintReflectionCard(
                    status: reflectionStatus,
                    persona: currentPersona,
                    isGenerating: soundPrintRefreshCoordinator.isRebuilding,
                    errorMessage: soundPrintRefreshCoordinator.lastError,
                    generate: generateReflection
                )
            }

            if SandboxMode.isEnabled {
                Section("Developer") {
                    NavigationLink {
                        SandboxSettingsView()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sandbox Data")
                                .font(.headline)
                            Text("Reset mock data or switch testing scenarios")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("sandboxSettingsLink")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.listendPaper)
        .navigationTitle("Profile")
    }

    private var averageRatingText: String {
        guard !logs.isEmpty else {
            return "No ratings"
        }

        let average = logs.reduce(0) { $0 + $1.rating } / Double(logs.count)
        return average.formatted(.number.precision(.fractionLength(1)))
    }

    private var topTagsText: String {
        let tagCounts = logs
            .flatMap(\.tags)
            .reduce(into: [String: Int]()) { counts, tag in
                counts[tag, default: 0] += 1
            }

        let topTags = tagCounts
            .sorted {
                if $0.value == $1.value {
                    return $0.key < $1.key
                }

                return $0.value > $1.value
            }
            .prefix(3)
            .map(\.key)

        return topTags.isEmpty ? "No tags yet" : topTags.joined(separator: ", ")
    }

    private var tasteInsightsSubtitle: String {
        logs.isEmpty ? "Start logging to build your taste recap." : "\(logs.count.formatted()) logs and counting"
    }

    private var currentPersona: SoundPrintPersona? {
        personas.first
    }

    private var reflectionStatus: SoundPrintReflectionStatus {
        SoundPrintReflectionStatus.resolve(
            logCount: logs.count,
            representedLogCount: currentPersona?.logCountAtGeneration,
            historyChanged: reflectionNeedsRefresh
        )
    }

    private func generateReflection() {
        Task {
            await soundPrintRefreshCoordinator.generateReflection(
                in: modelContext,
                provider: soundPrintProvider
            )
        }
    }
}

private struct SoundPrintReflectionCard: View {
    let status: SoundPrintReflectionStatus
    let persona: SoundPrintPersona?
    let isGenerating: Bool
    let errorMessage: String?
    let generate: () -> Void

    private var presentation: SoundPrintReflectionPresentation {
        SoundPrintReflectionPresentation(status: status)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.md) {
            switch status.phase {
            case .collecting:
                collectingContent
            case .readyToCreate:
                readyToCreateContent
            case .current, .readyToUpdate:
                if let persona {
                    reflectionContent(persona)
                }
            }

            if status.phase == .collecting || status.phase == .readyToCreate {
                settingsLink
            }

            if isGenerating {
                ProgressView("Reading your latest logs…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("soundPrintGenerationProgress")
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("soundPrintGenerationError")
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("soundPrintReflectionCard")
    }

    @ViewBuilder
    private var collectingContent: some View {
        Text(presentation.title)
            .font(.headline)
        Text(presentation.description)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if let progressText = presentation.progressText {
            Text(progressText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .accessibilityLabel("SoundPrint progress")
                .accessibilityValue(progressText)
                .accessibilityIdentifier("soundPrintProgressText")
        }
    }

    @ViewBuilder
    private var readyToCreateContent: some View {
        Text(presentation.title)
            .font(.headline)
        Text(presentation.description)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        Button("Create my SoundPrint", action: generate)
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating)
            .accessibilityIdentifier("createSoundPrintButton")
    }

    private func reflectionContent(_ persona: SoundPrintPersona) -> some View {
        VStack(alignment: .leading, spacing: ListendSpacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    Text(presentation.title)
                        .font(.headline)
                    SoundPrintGenerationSourceBadge(source: persona.generationSource)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.title)
                        .font(.headline)
                    SoundPrintGenerationSourceBadge(source: persona.generationSource)
                }
            }

            NavigationLink {
                SoundPrintProfileView()
            } label: {
                VStack(alignment: .leading, spacing: ListendSpacing.sm) {
                    Text(persona.personaText)
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Based on \(persona.logCountAtGeneration) logs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if let freshnessText = presentation.freshnessText {
                        Text(freshnessText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
            .accessibilityIdentifier("soundPrintReflectionLink")

            if status.phase == .readyToUpdate {
                Text(presentation.description)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Button("Update my SoundPrint", action: generate)
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating)
                    .accessibilityIdentifier("updateSoundPrintButton")
            }
        }
    }

    private var settingsLink: some View {
        NavigationLink {
            SoundPrintSettingsView()
        } label: {
            Label("SoundPrint Settings", systemImage: "gearshape")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("soundPrintSettingsLink")
    }
}

private struct StatRow: View {
    let title: String
    let value: String
    var valueIdentifier: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            valueText
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var valueText: some View {
        let text = Text(value)
            .foregroundStyle(.secondary)

        if let valueIdentifier {
            text.accessibilityIdentifier(valueIdentifier)
        } else {
            text
        }
    }
}

#Preview("Collecting") {
    NavigationStack {
        ProfileView()
    }
    .modelContainer(PreviewData.lockedPersonaContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Ready to Create") {
    NavigationStack {
        ProfileView()
    }
    .modelContainer(PreviewData.readyReflectionContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Current Reflection") {
    NavigationStack {
        ProfileView()
    }
    .modelContainer(PreviewData.unlockedPersonaContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Apple Intelligence Reflection") {
    NavigationStack {
        ProfileView()
    }
    .modelContainer(PreviewData.appleIntelligencePersonaContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Update Ready") {
    NavigationStack {
        ProfileView()
    }
    .modelContainer(PreviewData.updateReadyReflectionContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}
