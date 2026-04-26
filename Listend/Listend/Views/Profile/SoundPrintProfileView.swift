//
//  SoundPrintProfileView.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

import SwiftUI
import SwiftData

struct SoundPrintProfileView: View {
    @Query(sort: \TasteDimension.weight, order: .reverse) private var dimensions: [TasteDimension]
    @Query private var evidence: [TasteEvidence]
    @Query private var logs: [LogEntry]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How SoundPrint sees your taste")
                        .font(.title2.weight(.bold))
                    Text("Built from positive logs and their receipts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if dimensions.isEmpty {
                ContentUnavailableView(
                    "No SoundPrint Yet",
                    systemImage: "waveform.path",
                    description: Text("Positive logs with reviews or tags will build your taste profile.")
                )
            } else {
                Section("Dimensions") {
                    ForEach(dimensions) { dimension in
                        DimensionCard(
                            dimension: dimension,
                            evidence: evidenceItems(for: dimension)
                        ) { logID in
                            log(for: logID)
                        }
                    }
                }
            }
        }
        .navigationTitle("SoundPrint")
    }

    private func evidenceItems(for dimension: TasteDimension) -> [TasteEvidence] {
        evidence
            .filter { $0.dimensionName == dimension.name && $0.isPositiveEvidence }
            .sorted {
                if $0.strength == $1.strength {
                    return $0.snippet < $1.snippet
                }

                return $0.strength > $1.strength
            }
    }

    private func log(for id: UUID) -> LogEntry? {
        logs.first { $0.id == id }
    }
}

private struct DimensionCard: View {
    let dimension: TasteDimension
    let evidence: [TasteEvidence]
    let log: (UUID) -> LogEntry?

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(evidence) { item in
                    ReceiptRow(evidence: item, log: log(item.logEntryID))
                }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dimension.label)
                        .font(.headline)
                    Text(dimension.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                MetricBar(title: "Weight", value: dimension.weight)
                MetricBar(title: "Confidence", value: dimension.confidence)
            }
            .padding(.vertical, 6)
        }
    }
}

private struct MetricBar: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .percent.precision(.fractionLength(0)))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            ProgressView(value: value.clamped(to: 0.0...1.0))
                .tint(.accentColor)
        }
    }
}

private struct ReceiptRow: View {
    let evidence: TasteEvidence
    let log: LogEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(evidence.snippet)
                .font(.subheadline)

            Text(albumContext)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var albumContext: String {
        guard let album = log?.album else {
            return "Log no longer available"
        }

        return "\(album.title) - \(album.artistName)"
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self, SoundPrintPersona.self, Recommendation.self, RecommendationReceipt.self, RecommendationFeedback.self], inMemory: true)
}
