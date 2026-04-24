//
//  RecentLogRow.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI

struct RecentLogRow: View {
    let log: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(log.album?.title ?? "Unknown Album")
                    .font(.headline)
                Text(log.album?.artistName ?? "Unknown Artist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Label(ratingText, systemImage: "star.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.yellow)

                Text(log.loggedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !log.reviewText.isEmpty {
                Text(log.reviewText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            if !log.tags.isEmpty {
                TagsView(tags: log.tags)
            }
        }
        .padding(.vertical, 6)
    }

    private var ratingText: String {
        log.rating.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct TagsView: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
        }
    }
}
