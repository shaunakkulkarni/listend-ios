//
//  SoundPrintProfileView.swift
//  Listend
//

import SwiftUI
import SwiftData

struct SoundPrintProfileView: View {
    @AppStorage(SoundPrintPreferenceKey.reflectionNeedsRefresh) private var reflectionNeedsRefresh = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.soundPrintProvider) private var soundPrintProvider
    @Environment(SoundPrintProfileRefreshCoordinator.self) private var soundPrintRefreshCoordinator
    @Query(sort: \SoundPrintPersona.generatedAt, order: .reverse) private var personas: [SoundPrintPersona]
    @Query(sort: \TasteDimension.weight, order: .reverse) private var dimensions: [TasteDimension]
    @Query(sort: \TasteAvoidanceSignal.strength, order: .reverse) private var avoidanceSignals: [TasteAvoidanceSignal]
    @Query private var evidence: [TasteEvidence]
    @Query private var logs: [LogEntry]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ListendSpacing.xl) {
                if let persona = currentPersona,
                   logs.count >= SoundPrintProfileThresholds.personaMinimumLogCount {
                    reflectionContent(persona)
                } else {
                    placeholderState(
                        title: "No SoundPrint Reflection Yet",
                        systemImage: "waveform.path",
                        description: "Return to Profile to keep building or create your first reflection."
                    )
                }
            }
            .padding(.horizontal, ListendSpacing.lg)
            .padding(.top, ListendSpacing.lg)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.listendPaper)
        .navigationTitle("SoundPrint Reflection")
        .accessibilityIdentifier("soundPrintReflectionScreen")
    }

    private var currentPersona: SoundPrintPersona? {
        personas.first
    }

    private var reflectionStatus: SoundPrintReflectionStatus {
        SoundPrintReflectionStatus.resolve(
            logCount: logs.count,
            representedLogCount: currentPersona?.logCountAtGeneration,
            historyChanged: reflectionNeedsRefresh
        )
    }

    @ViewBuilder
    private func reflectionContent(_ persona: SoundPrintPersona) -> some View {
        reflectionCard(persona)
        freshnessCard

        if dimensions.isEmpty {
            placeholderState(
                title: "Receipts Are Still Forming",
                systemImage: "waveform.path",
                description: "Your reflection is saved. More detailed logs will add grounded examples here."
            )
        } else {
            dimensionsSection
        }

        if logs.count >= SoundPrintProfileThresholds.fullerProfileMinimumLogCount,
           !avoidanceSignals.isEmpty {
            avoidanceSection
        }

        privacyFooter(for: persona)
        settingsLink
    }

    private func placeholderState(title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(description))
    }

    private func reflectionCard(_ persona: SoundPrintPersona) -> some View {
        ListendObjectCard {
            VStack(alignment: .leading, spacing: ListendSpacing.md) {
                Text(persona.personaText)
                    .font(.system(.title3, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: ListendSpacing.sm) {
                        reflectionMetadata(persona)
                    }

                    VStack(alignment: .leading, spacing: ListendSpacing.sm) {
                        reflectionMetadata(persona)
                    }
                }
            }
        }
        .accessibilityIdentifier("soundPrintReflectionDetailCard")
    }

    @ViewBuilder
    private func reflectionMetadata(_ persona: SoundPrintPersona) -> some View {
        SoundPrintGenerationSourceBadge(source: persona.generationSource)
        Text("Based on \(persona.logCountAtGeneration) logs")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        Text("Generated \(persona.generatedAt.formatted(date: .abbreviated, time: .omitted))")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var freshnessCard: some View {
        let presentation = SoundPrintReflectionPresentation(status: reflectionStatus)

        if reflectionStatus.phase == .readyToUpdate ||
            reflectionStatus.newLogCount > 0 ||
            soundPrintRefreshCoordinator.isRebuilding ||
            soundPrintRefreshCoordinator.lastError != nil {
            ListendObjectCard {
                VStack(alignment: .leading, spacing: ListendSpacing.sm) {
                    Text(reflectionStatus.phase == .readyToUpdate
                        ? "Your SoundPrint is ready for an update"
                        : "Your next reflection is forming")
                        .font(.headline)

                    if let freshnessText = presentation.freshnessText {
                        Text(freshnessText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if reflectionStatus.phase == .current,
                       reflectionStatus.newLogCount > 0 {
                        let requiredCount = SoundPrintProfileThresholds.reflectionRefreshLogIncrement

                        ProgressView(
                            value: Double(min(reflectionStatus.newLogCount, requiredCount)),
                            total: Double(requiredCount)
                        )
                        .accessibilityLabel("SoundPrint update progress")
                        .accessibilityValue("\(reflectionStatus.newLogCount) of \(requiredCount) new logs")
                        .accessibilityIdentifier("soundPrintUpdateProgress")

                        Text("Your current reflection stays visible until you choose to update it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if reflectionStatus.phase == .readyToUpdate {
                        Button("Update my SoundPrint", action: generateReflection)
                            .buttonStyle(.borderedProminent)
                            .disabled(soundPrintRefreshCoordinator.isRebuilding)
                            .accessibilityIdentifier("updateSoundPrintButton")
                    }

                    if soundPrintRefreshCoordinator.isRebuilding {
                        ProgressView("Reading your latest logs…")
                            .font(.subheadline)
                            .accessibilityIdentifier("soundPrintGenerationProgress")
                    }

                    if let lastError = soundPrintRefreshCoordinator.lastError {
                        Label(lastError, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("soundPrintGenerationError")
                    }
                }
            }
        }
    }

    private func privacyFooter(for persona: SoundPrintPersona) -> some View {
        Label(privacyText(for: persona), systemImage: "lock.shield")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("soundPrintPrivacyNote")
    }

    private var settingsLink: some View {
        NavigationLink {
            SoundPrintSettingsView()
        } label: {
            Label("SoundPrint Settings", systemImage: "gearshape")
                .font(.subheadline.weight(.semibold))
        }
        .accessibilityIdentifier("soundPrintSettingsLink")
    }

    private func privacyText(for persona: SoundPrintPersona) -> String {
        switch persona.generationSource {
        case .foundationModels:
            return "Generated privately on your device from your Listend journal."
        case .localFallback:
            return "Built locally from your Listend journal."
        case .unavailable, .unknown:
            return "Built privately from your ratings, reactions, and notes."
        }
    }

    private func generateReflection() {
        Task {
            await soundPrintRefreshCoordinator.generateReflection(
                in: modelContext,
                provider: soundPrintProvider
            )
        }
    }

    private var dimensionsSection: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What you're rewarding")
                    .font(.title2.weight(.bold))
                Text("Patterns grounded in the albums and reactions behind this reflection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

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
                Text("What tends to lose you")
                    .font(.title2.weight(.bold))
                Text("Patterns grounded in lower-rated or skip-heavy logs.")
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

private struct DimensionCard: View {
    let dimension: TasteDimension
    let evidence: [TasteEvidence]
    let logsByID: [UUID: LogEntry]

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ReceiptSectionTitle(text: "From your logs")

                if receipts.isEmpty {
                    Text("No usable receipts for this dimension yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(receipts) { receipt in
                        ReceiptRow(receipt: receipt)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(dimension.label)
                    .font(.headline)
                Text(dimension.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        }
        .accessibilityHint(isExpanded ? "Collapse supporting logs" : "Expand supporting logs")
    }

    private var receipts: [SoundPrintReceiptDisplay] {
        SoundPrintReceiptDisplay.positiveReceipts(from: evidence, logsByID: logsByID)
    }
}

private struct AvoidanceSignalCard: View {
    let signal: TasteAvoidanceSignal
    let logsByID: [UUID: LogEntry]

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ReceiptSectionTitle(text: "From your logs")

                if receipts.isEmpty {
                    Text("Original log unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(receipts) { receipt in
                        ReceiptRow(receipt: receipt)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(signal.label)
                    .font(.headline)
                Text(signal.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
        }
        .accessibilityHint(isExpanded ? "Collapse supporting logs" : "Expand supporting logs")
    }

    private var receipts: [SoundPrintReceiptDisplay] {
        SoundPrintReceiptDisplay.avoidanceReceipts(logIDs: signal.evidenceLogEntryIDs, logsByID: logsByID)
    }
}

private struct ReceiptSectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct ReceiptRow: View {
    let receipt: SoundPrintReceiptDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.albumTitle)
                    .font(.subheadline.weight(.semibold))

                if let artistName = receipt.artistName {
                    Text(artistName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(receipt.snippet)
                .font(.subheadline)

            Text(receipt.contextText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SoundPrintReceiptDisplay: Identifiable, Equatable {
    enum Kind: Equatable {
        case positive
        case avoidance
    }

    let id: String
    let kind: Kind
    let snippet: String
    let albumTitle: String
    let artistName: String?
    let ratingText: String?
    let contextText: String

    var sectionTitle: String {
        switch kind {
        case .positive:
            return "You reward..."
        case .avoidance:
            return "You tend to avoid..."
        }
    }

    static func positiveReceipts(
        from evidence: [TasteEvidence],
        logsByID: [UUID: LogEntry]
    ) -> [SoundPrintReceiptDisplay] {
        evidence.filter(\.isPositiveEvidence).compactMap { item in
            let log = logsByID[item.logEntryID]

            if log?.isNegativeSignal == true {
                return nil
            }

            return SoundPrintReceiptDisplay(
                id: item.id.uuidString,
                kind: .positive,
                snippet: item.snippet.receiptSnippet(fallback: bestSnippet(from: log, kind: .positive)),
                log: log
            )
        }
    }

    static func avoidanceReceipts(
        logIDs: [UUID],
        logsByID: [UUID: LogEntry]
    ) -> [SoundPrintReceiptDisplay] {
        logIDs.map { logID in
            let log = logsByID[logID]

            return SoundPrintReceiptDisplay(
                id: logID.uuidString,
                kind: .avoidance,
                snippet: bestSnippet(from: log, kind: .avoidance),
                log: log
            )
        }
    }

    private init(id: String, kind: Kind, snippet: String, log: LogEntry?) {
        self.id = id
        self.kind = kind
        self.snippet = snippet

        guard let log else {
            albumTitle = "Original log unavailable"
            artistName = nil
            ratingText = nil
            contextText = "Original log unavailable"
            return
        }

        albumTitle = log.album?.title ?? "Original log unavailable"
        artistName = log.album?.artistName
        ratingText = Self.ratingText(for: log.rating)
        contextText = Self.contextText(for: log, kind: kind)
    }

    private static func bestSnippet(from log: LogEntry?, kind: Kind) -> String {
        guard let log else {
            return "Original log unavailable"
        }

        let review = log.reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !review.isEmpty {
            return review.receiptSnippet(fallback: "Review unavailable")
        }

        switch kind {
        case .positive:
            return log.tags.isEmpty ? "Positive log evidence" : "Tagged \(log.tags.joined(separator: ", "))"
        case .avoidance:
            if !log.skipTracks.isEmpty {
                return "Skipped \(log.skipTracks.joined(separator: ", "))"
            }

            return log.tags.isEmpty ? "Avoidance signal evidence" : "Tagged \(log.tags.joined(separator: ", "))"
        }
    }

    private static func contextText(for log: LogEntry, kind: Kind) -> String {
        var parts = [ratingText(for: log.rating)]

        if !log.tags.isEmpty {
            parts.append("Tagged \(log.tags.joined(separator: ", "))")
        }

        if kind == .avoidance, !log.skipTracks.isEmpty {
            parts.append("Skipped \(log.skipTracks.joined(separator: ", "))")
        }

        return parts.joined(separator: " - ")
    }

    private static func ratingText(for rating: Double) -> String {
        let value = rating.rounded(.towardZero) == rating
            ? Int(rating).formatted()
            : rating.formatted(.number.precision(.fractionLength(1)))

        return "\(value) stars"
    }
}

private extension String {
    func receiptSnippet(fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? fallback : trimmed
        let limit = 96

        guard source.count > limit else {
            return source
        }

        let endIndex = source.index(source.startIndex, offsetBy: limit - 3)
        return String(source[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

#Preview("Cold Start") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.coldStartRecommendationContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Too Early") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.tooEarlyContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Early Signals") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.lockedPersonaContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Current Reflection") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.unlockedPersonaContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Apple Intelligence Reflection") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.appleIntelligencePersonaContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Local Fallback Reflection") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.localFallbackPersonaContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}

#Preview("Update Ready") {
    NavigationStack {
        SoundPrintProfileView()
    }
    .modelContainer(PreviewData.updateReadyReflectionContainer)
    .environment(SoundPrintProfileRefreshCoordinator())
}
