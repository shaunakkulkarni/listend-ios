//
//  LogsView.swift
//  Listend
//
//  Created by Codex on 5/7/26.
//

import SwiftUI
import SwiftData

struct LogsView: View {
    @Query(sort: \LogEntry.loggedAt, order: .reverse) private var logs: [LogEntry]

    var body: some View {
        Group {
            if logs.isEmpty {
                ContentUnavailableView(
                    "No Logs Yet",
                    systemImage: "music.note.list",
                    description: Text("Albums you rate and review will appear here.")
                )
                .accessibilityIdentifier("logsEmptyState")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(logs) { log in
                            NavigationLink {
                                LogEntryDetailView(log: log)
                            } label: {
                                RecentLogRow(log: log)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("logHistoryRow-\(log.id.uuidString)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
                .background(Color(.systemGroupedBackground))
                .accessibilityIdentifier("logsHistoryList")
            }
        }
        .navigationTitle("Logs")
    }
}

#Preview("Empty") {
    NavigationStack {
        LogsView()
    }
    .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self, SoundPrintPersona.self, Recommendation.self, RecommendationReceipt.self, RecommendationFeedback.self], inMemory: true)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("History") {
    NavigationStack {
        LogsView()
    }
    .modelContainer(PreviewData.activeRecommendationContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}
