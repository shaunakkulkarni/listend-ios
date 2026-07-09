//
//  TasteInsightsView.swift
//  Listend
//
//  "Your Taste So Far" — a warm, local-first recap of the user's logging history.
//  Reads existing SwiftData logs via @Query and renders a deterministic recap built
//  by TasteInsightsBuilder. Mirrors SoundPrintProfileView's layout conventions
//  (ScrollView + VStack of ListendObjectCards, listendPaper background).
//

import SwiftUI
import SwiftData

struct TasteInsightsView: View {
    @Query(sort: \LogEntry.loggedAt, order: .reverse) private var logs: [LogEntry]

    private var insights: TasteInsights {
        TasteInsightsBuilder.make(from: logs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ListendSpacing.xl) {
                switch insights.state {
                case .empty:
                    emptyState
                case .early:
                    earlyHint
                    populatedContent
                case .full:
                    populatedContent
                }
            }
            .padding(.horizontal, ListendSpacing.lg)
            .padding(.top, ListendSpacing.lg)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.listendPaper)
        .navigationTitle("Your Taste So Far")
        .accessibilityIdentifier("tasteInsightsScreen")
    }

    // MARK: - States

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing Logged Yet", systemImage: "waveform")
        } description: {
            Text("Log an album to start your taste recap.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, ListendSpacing.xxl)
    }

    private var earlyHint: some View {
        Text("You're just getting started. These patterns get stronger after a few more logs.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var populatedContent: some View {
        summaryCard

        if !insights.topRatedAlbums.isEmpty {
            topRatedAlbumsCard
        }

        if !insights.topTags.isEmpty {
            topTagsCard
        }

        if insights.totalLogs > 0 {
            ratingDistributionCard
        }

        if let note = insights.tasteNote {
            tasteNoteCard(note)
        }
    }

    // MARK: - Cards

    private var summaryCard: some View {
        ListendObjectCard {
            VStack(alignment: .leading, spacing: ListendSpacing.md) {
                sectionTitle("Summary")
                summaryRow(label: "Total logs", value: insights.totalLogs.formatted())
                summaryRow(label: "Average rating", value: averageRatingText)
                if let topTag = insights.topTag {
                    summaryRow(label: "Top tag", value: topTag)
                }
                if let topArtist = insights.topArtist {
                    summaryRow(label: "Top artist", value: topArtist)
                }
            }
        }
    }

    private var topRatedAlbumsCard: some View {
        ListendObjectCard {
            VStack(alignment: .leading, spacing: ListendSpacing.md) {
                sectionTitle("Top Rated Albums")
                VStack(alignment: .leading, spacing: ListendSpacing.md) {
                    ForEach(insights.topRatedAlbums) { album in
                        TopRatedAlbumRow(album: album)
                    }
                }
            }
        }
    }

    private var topTagsCard: some View {
        ListendObjectCard {
            VStack(alignment: .leading, spacing: ListendSpacing.md) {
                sectionTitle("Top Tags")
                FlowLayout(spacing: ListendSpacing.sm) {
                    ForEach(insights.topTags) { tagCount in
                        TasteTagChip(tag: tagCount.tag, count: tagCount.count)
                    }
                }
            }
        }
    }

    private var ratingDistributionCard: some View {
        ListendObjectCard {
            VStack(alignment: .leading, spacing: ListendSpacing.md) {
                sectionTitle("Rating Distribution")
                VStack(spacing: ListendSpacing.sm) {
                    ForEach(insights.ratingDistribution) { bucket in
                        RatingBar(bucket: bucket, maxCount: maxBucketCount)
                    }
                }
            }
        }
    }

    private func tasteNoteCard(_ note: String) -> some View {
        ListendObjectCard {
            VStack(alignment: .leading, spacing: ListendSpacing.sm) {
                sectionTitle("Taste Notes")
                Text(note)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Derived display values

    private var averageRatingText: String {
        guard let average = insights.averageRating else {
            return "—"
        }

        return average.formatted(.number.precision(.fractionLength(1)))
    }

    private var maxBucketCount: Int {
        max(1, insights.ratingDistribution.map(\.count).max() ?? 0)
    }

    // MARK: - Small helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.bold))
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: ListendSpacing.sm)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Rows / chips

private struct TopRatedAlbumRow: View {
    let album: TopRatedAlbumItem

    var body: some View {
        HStack(alignment: .top, spacing: ListendSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(album.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: ListendSpacing.sm)

            VStack(alignment: .trailing, spacing: 2) {
                Label(ratingText, systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.listendAccent)
                Text(album.loggedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var ratingText: String {
        album.rating.formatted(.number.precision(.fractionLength(1)))
    }
}

private struct TasteTagChip: View {
    let tag: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(tag)
            Text(count.formatted())
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.secondary.opacity(0.12), in: Capsule())
    }
}

private struct RatingBar: View {
    let bucket: RatingBucket
    let maxCount: Int

    var body: some View {
        HStack(spacing: ListendSpacing.sm) {
            HStack(spacing: 2) {
                Text(bucket.star.formatted())
                Image(systemName: "star.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.listendAccent)
            .frame(width: 34, alignment: .leading)

            ProgressView(value: Double(bucket.count), total: Double(maxCount))
                .tint(Color.listendAccent)

            Text(bucket.count.formatted())
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 22, alignment: .trailing)
        }
    }
}

// MARK: - Flow layout

/// A minimal wrapping layout for the tag chips — lays subviews left-to-right and wraps
/// to the next line when the row is full. Self-contained; no external dependency.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalWidth = max(totalWidth, rowWidth)
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        totalWidth = max(totalWidth, rowWidth)
        totalHeight += rowHeight
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview("Empty") {
    NavigationStack {
        TasteInsightsView()
    }
    .modelContainer(PreviewData.coldStartRecommendationContainer)
}

#Preview("Early") {
    NavigationStack {
        TasteInsightsView()
    }
    .modelContainer(PreviewData.lockedPersonaContainer)
}

#Preview("Full") {
    NavigationStack {
        TasteInsightsView()
    }
    .modelContainer(PreviewData.fullerProfileContainer)
}
