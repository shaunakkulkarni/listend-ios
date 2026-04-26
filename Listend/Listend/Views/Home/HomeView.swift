//
//  HomeView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \LogEntry.loggedAt, order: .reverse) private var logs: [LogEntry]
    @Query(sort: \SoundPrintPersona.generatedAt, order: .reverse) private var personas: [SoundPrintPersona]
    @Query(sort: \Recommendation.createdAt, order: .reverse) private var recommendations: [Recommendation]
    @State private var isShowingNewLog = false

    var body: some View {
        List {
            if let currentPersona {
                Section("SoundPrint Persona") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current read")
                            .font(.headline)
                        Text(currentPersona.personaText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            if canShowTonightPick {
                Section("Tonight's Pick") {
                    NavigationLink {
                        TonightPickView()
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(tonightPickTitle)
                                .font(.headline)
                            Text(tonightPickSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if logs.isEmpty {
                ContentUnavailableView(
                    "No Logs Yet",
                    systemImage: "music.note.list",
                    description: Text("Recent album logs will appear here.")
                )
            } else {
                Section("Recent Logs") {
                    ForEach(logs) { log in
                        NavigationLink {
                            LogEntryDetailView(log: log)
                        } label: {
                            RecentLogRow(log: log)
                        }
                    }
                }
            }
        }
        .navigationTitle("Listend")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingNewLog = true
                } label: {
                    Label("Add Log", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingNewLog) {
            LogEntryEditorView()
        }
    }

    private var currentPersona: SoundPrintPersona? {
        personas.first
    }

    private var activeRecommendation: Recommendation? {
        recommendations.first { $0.status == RecommendationStatus.active.rawValue }
    }

    private var canShowTonightPick: Bool {
        activeRecommendation != nil || logs.contains { log in
            log.album != nil && !log.isNegativeSignal && log.rating >= 4.0
        }
    }

    private var tonightPickTitle: String {
        activeRecommendation?.album?.title ?? "Find Tonight's Pick"
    }

    private var tonightPickSubtitle: String {
        if let album = activeRecommendation?.album {
            return "\(album.artistName) is ready when you are."
        }

        return "Generate one local pick with receipts."
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .modelContainer(PreviewData.activeRecommendationContainer)
}
