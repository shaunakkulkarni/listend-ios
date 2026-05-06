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
        EditorialSurface(isInteractive: true) {
            HStack(alignment: .top, spacing: 12) {
                AlbumArtworkView(artworkURL: log.album?.artworkURL, size: 64)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(log.album?.title ?? "Unknown Album")
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(log.album?.artistName ?? "Unknown Artist")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 10) {
                        Label(ratingText, systemImage: "star.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.yellow)

                        Text(log.loggedAt, format: .dateTime.month(.abbreviated).day().year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if !log.reviewText.isEmpty {
                        Text(log.reviewText)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !log.tags.isEmpty {
                        TagStrip(tags: log.tags)
                    }
                }
            }
        }
    }

    private var ratingText: String {
        log.rating.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct TagStrip: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(title: tag)
                }
            }
        }
        .scrollClipDisabled()
    }
}

private struct TagChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.secondary.opacity(0.12), in: Capsule())
    }
}
