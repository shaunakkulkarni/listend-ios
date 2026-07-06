//
//  SoundPrintProfileView.swift
//  Listend
//

import SwiftUI
import SwiftData

struct SoundPrintProfileView: View {
    @Query(sort: \SoundPrintPersona.generatedAt, order: .reverse) private var personas: [SoundPrintPersona]
    @Query(sort: \TasteDimension.weight, order: .reverse) private var dimensions: [TasteDimension]
    @Query(sort: \TasteAvoidanceSignal.strength, order: .reverse) private var avoidanceSignals: [TasteAvoidanceSignal]
    @Query private var evidence: [TasteEvidence]
    @Query private var logs: [LogEntry]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ListendSpacing.xl) {
                switch profileState {
                case .coldStart:
                    placeholderState(
                        title: "Nothing Logged Yet",
                        systemImage: "waveform.path",
                        description: "Log a few albums and SoundPrint will start noticing patterns."
                    )
                case .tooEarly:
                    placeholderState(
                        title: "Too Early To Tell",
                        systemImage: "waveform.path.ecg",
                        description: "A couple more logs and real patterns will start to show."
                    )
                case .earlySignals:
                    earlySignalsContent
                case .persona:
                    personaStateContent(showsAvoidance: false)
                case .fullerProfile:
                    personaStateContent(showsAvoidance: true)
                }
            }
            .padding(.horizontal, ListendSpacing.lg)
            .padding(.top, ListendSpacing.lg)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.listendPaper)
        .navigationTitle("SoundPrint")
    }

    private var profileState: SoundPrintProfileState {
        SoundPrintProfileState(logCount: logs.count)
    }

    @ViewBuilder
    private var earlySignalsContent: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.sm) {
            Text("Early Signals")
                .font(.title2.weight(.bold))
            Text("Not enough logs yet for a full profile, but a pattern is starting to form.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        if dimensions.isEmpty {
            placeholderState(
                title: "Still Listening",
                systemImage: "waveform.path",
                description: "Keep logging and dimensions will start to appear here."
            )
        } else {
            dimensionsSection
        }
    }

    @ViewBuilder
    private func personaStateContent(showsAvoidance: Bool) -> some View {
        if let persona = personas.first {
            personaSection(persona)

            if persona.headline != nil || persona.summaryText != nil {
                summaryCard(persona)
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("How SoundPrint sees your taste")
                .font(.title2.weight(.bold))
            Text("Built from your logs and their receipts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        if dimensions.isEmpty {
            placeholderState(
                title: "No SoundPrint Yet",
                systemImage: "waveform.path",
                description: "Positive logs with reviews or tags will build your taste profile."
            )
        } else {
            dimensionsSection
        }

        if showsAvoidance && !avoidanceSignals.isEmpty {
            avoidanceSection
        }
    }

    private func placeholderState(title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
    }

    private func personaSection(_ persona: SoundPrintPersona) -> some View {
        ListendObjectCard {
            VStack(alignment: .leading, spacing: ListendSpacing.sm) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Persona")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    SoundPrintGenerationSourceBadge(source: persona.generationSource)
                }

                Text(persona.personaText)
                    .font(.system(.title3, design: .serif))
            }
        }
    }

    private func summaryCard(_ persona: SoundPrintPersona) -> some View {
        ListendObjectCard {
            VStack(alignment: .leading, spacing: ListendSpacing.sm) {
                if let headline = persona.headline {
                    Text(headline)
                        .font(.headline)
                }

                if let summaryText = persona.summaryText {
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !persona.bullets.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(persona.bullets, id: \.self) { bullet in
                            HStack(alignment: .top, spacing: 6) {
                                Text("-")
                                    .foregroundStyle(.secondary)
                                Text(bullet)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var dimensionsSection: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.md) {
            Text("Taste Dimensions (\(dimensions.count))")
                .font(.headline)

            VStack(spacing: ListendSpacing.md) {
                ForEach(dimensions) { dimension in
                    ListendObjectCard {
                        DimensionCard(
                            dimension: dimension,
                            evidence: evidenceByDimension[dimension.name, default: []],
                            logsByID: logsByID
                        )
                    }
                }
            }
        }
    }

    private var avoidanceSection: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What You Tend To Reject")
                    .font(.headline)
                Text("Patterns that show up in lower-rated or skip-heavy logs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: ListendSpacing.md) {
                ForEach(avoidanceSignals) { signal in
                    ListendObjectCard {
                        AvoidanceSignalCard(signal: signal, logsByID: logsByID)
                    }
                }
            }
        }
    }

    private var evidenceByDimension: [String: [TasteEvidence]] {
        Dictionary(grouping: evidence.filter(\.isPositiveEvidence), by: \.dimensionName)
            .mapValues { evidence in
                evidence.sorted {
                    if $0.strength == $1.strength {
                        return $0.snippet < $1.snippet
                    }

                    return $0.strength > $1.strength
                }
            }
    }

    private var logsByID: [UUID: LogEntry] {
        Dictionary(uniqueKeysWithValues: logs.map { ($0.id, $0) })
    }
}

private enum SoundPrintProfileState {
    case coldStart
    case tooEarly
    case earlySignals
    case persona
    case fullerProfile

    init(logCount: Int) {
        switch logCount {
        case 0:
            self = .coldStart
        case 1..<3:
            self = .tooEarly
        case 3..<SoundPrintProfileThresholds.personaMinimumLogCount:
            self = .earlySignals
        case SoundPrintProfileThresholds.personaMinimumLogCount..<SoundPrintProfileThresholds.fullerProfileMinimumLogCount:
            self = .persona
        default:
            self = .fullerProfile
        }
    }
}

private struct DimensionCard: View {
    let dimension: TasteDimension
    let evidence: [TasteEvidence]
    let logsByID: [UUID: LogEntry]

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(evidence) { item in
                    ReceiptRow(snippet: item.snippet, log: logsByID[item.logEntryID])
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

                MetricBar(title: "Weight", value: dimension.weight, tint: Color.listendAccent)
                MetricBar(title: "Confidence", value: dimension.confidence, tint: Color.listendAccent)
            }
            .padding(.vertical, 6)
        }
    }
}

private struct AvoidanceSignalCard: View {
    let signal: TasteAvoidanceSignal
    let logsByID: [UUID: LogEntry]

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(contributingLogs, id: \.id) { log in
                    ReceiptRow(snippet: log.reviewText, log: log)
                }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(signal.label)
                        .font(.headline)
                    Text(signal.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                MetricBar(title: "Strength", value: signal.strength, tint: Color.listendMutedInk)
                MetricBar(title: "Confidence", value: signal.confidence, tint: Color.listendMutedInk)
            }
            .padding(.vertical, 6)
        }
    }

    private var contributingLogs: [LogEntry] {
        signal.evidenceLogEntryIDs.compactMap { logsByID[$0] }
    }
}

private struct MetricBar: View {
    let title: String
    let value: Double
    let tint: Color

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
                .tint(tint)
        }
    }
}

private struct ReceiptRow: View {
    let snippet: String
    let log: LogEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snippet)
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

#Preview("Cold Start") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.coldStartRecommendationContainer)
}

#Preview("Too Early") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.tooEarlyContainer)
}

#Preview("Early Signals") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.lockedPersonaContainer)
}

#Preview("Persona") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.unlockedPersonaContainer)
}

#Preview("Persona Apple Intelligence") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.appleIntelligencePersonaContainer)
}

#Preview("Persona Local Fallback") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.localFallbackPersonaContainer)
}

#Preview("Fuller Profile") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.fullerProfileContainer)
}
