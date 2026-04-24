//
//  ProfileView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query private var logs: [LogEntry]

    var body: some View {
        List {
            Section("Stats") {
                StatRow(title: "Total Logs", value: logs.count.formatted())
                StatRow(title: "Average Rating", value: averageRatingText)
                StatRow(title: "Top Tags", value: topTagsText)
            }

            Section("SoundPrint") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Taste profile pending")
                        .font(.headline)
                    Text("SoundPrint starts after the local logging foundation is in place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
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
}

private struct StatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
    .modelContainer(for: [Album.self, LogEntry.self], inMemory: true)
}
