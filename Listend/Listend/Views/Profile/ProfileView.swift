//
//  ProfileView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(SoundPrintProfileRefreshCoordinator.self) private var soundPrintRefreshCoordinator
    @Query private var logs: [LogEntry]
    @Query(sort: \TasteDimension.weight, order: .reverse) private var dimensions: [TasteDimension]
    @Query(sort: \SoundPrintPersona.generatedAt, order: .reverse) private var personas: [SoundPrintPersona]

    var body: some View {
        List {
            Section("Stats") {
                StatRow(title: "Total Logs", value: logs.count.formatted(), valueIdentifier: "totalLogsValueText")
                    .accessibilityIdentifier("totalLogsStat")
                StatRow(title: "Average Rating", value: averageRatingText, valueIdentifier: "averageRatingValueText")
                    .accessibilityIdentifier("averageRatingStat")
                StatRow(title: "Top Tags", value: topTagsText, valueIdentifier: "topTagsValueText")
                    .accessibilityIdentifier("topTagsStat")
            }

            Section("SoundPrint") {
                PersonaCard(logCount: logs.count, persona: currentPersona)
                if soundPrintRefreshCoordinator.isRebuilding {
                    Label("Refreshing SoundPrint", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                }

                if let lastError = soundPrintRefreshCoordinator.lastError {
                    Label(lastError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }

                if canShowSoundPrintProfile {
                    NavigationLink {
                        SoundPrintProfileView()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SoundPrint Profile")
                                .font(.headline)
                            Text("\(dimensions.count) taste dimensions from your logs")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Taste profile pending")
                            .font(.headline)
                        Text("Log a few positive albums to start building your SoundPrint.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
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

    private var canShowSoundPrintProfile: Bool {
        positiveLogCount >= 2 && !dimensions.isEmpty
    }

    private var currentPersona: SoundPrintPersona? {
        personas.first
    }

    private var positiveLogCount: Int {
        logs.filter(\.isPositiveSignal).count
    }
}

private struct PersonaCard: View {
    let logCount: Int
    let persona: SoundPrintPersona?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Persona")
                .font(.headline)

            if let persona, logCount >= 5 {
                Text(persona.personaText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Log 5 albums to unlock your SoundPrint persona.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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

#Preview {
    NavigationStack {
        ProfileView()
    }
    .modelContainer(PreviewData.lockedPersonaContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Unlocked Persona") {
    NavigationStack {
        ProfileView()
    }
    .modelContainer(PreviewData.unlockedPersonaContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}
