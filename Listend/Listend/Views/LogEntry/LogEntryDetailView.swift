//
//  LogEntryDetailView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI
import SwiftData

struct LogEntryDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SoundPrintProfileRefreshCoordinator.self) private var soundPrintRefreshCoordinator

    let log: LogEntry

    @State private var isShowingEditor = false
    @State private var isShowingDeleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(log.album?.title ?? "Unknown Album")
                        .font(.title2.weight(.bold))

                    Text(log.album?.artistName ?? "Unknown Artist")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if let releaseYear = log.album?.releaseYear {
                        Text(String(releaseYear))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Log") {
                DetailRow(title: "Rating", value: ratingText, valueIdentifier: "ratingValueText")
                    .accessibilityIdentifier("ratingDetailRow")
                DetailRow(title: "Logged", value: log.loggedAt.formatted(date: .abbreviated, time: .omitted))

                if log.updatedAt > log.loggedAt {
                    DetailRow(title: "Updated", value: log.updatedAt.formatted(date: .abbreviated, time: .omitted))
                }
            }

            if !log.reviewText.isEmpty {
                Section("Review") {
                    Text(log.reviewText)
                        .accessibilityIdentifier("reviewValueText")
                }
            }

            if !log.tags.isEmpty {
                Section("Tags") {
                    Text(log.tags.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("tagsValueText")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button("Delete Log", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }
                .accessibilityIdentifier("deleteLogButton")
            }
        }
        .navigationTitle("Log")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    isShowingEditor = true
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            LogEntryEditorView(log: log)
        }
        .confirmationDialog(
            "Delete this log?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Log", role: .destructive) {
                Task {
                    await deleteLog()
                }
            }
            .accessibilityIdentifier("confirmDeleteLogButton")

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the log from your local diary.")
        }
    }

    private var ratingText: String {
        log.rating.formatted(.number.precision(.fractionLength(1)))
    }

    @MainActor
    private func deleteLog() async {
        do {
            modelContext.delete(log)
            try modelContext.save()
            await soundPrintRefreshCoordinator.refreshProfile(in: modelContext)
            dismiss()
        } catch {
            errorMessage = "Could not delete log."
        }
    }
}

private struct DetailRow: View {
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
        LogEntryDetailView(
            log: LogEntry(
                album: Album(title: "Blonde", artistName: "Frank Ocean"),
                rating: 5.0,
                reviewText: "Sparse in the right places.",
                tags: ["late night", "vocals"]
            )
        )
    }
    .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self, SoundPrintPersona.self, Recommendation.self, RecommendationReceipt.self, RecommendationFeedback.self], inMemory: true)
    .environment(SoundPrintProfileRefreshCoordinator())
}
