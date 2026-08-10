//
//  HomeActivationViews.swift
//  Listend
//

import SwiftUI

struct HomeActivationModule: View {
    let presentation: HomeActivationPresentation
    let primaryAction: () -> Void

    var body: some View {
        ListendObjectCard {
            VStack(alignment: .leading, spacing: ListendSpacing.md) {
                Label(presentation.title, systemImage: iconName)
                    .font(.headline)
                    .foregroundStyle(Color.listendInk)

                Text(presentation.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let progressText = presentation.progressText {
                    Text(progressText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .accessibilityLabel("SoundPrint progress")
                        .accessibilityValue(progressText)
                        .accessibilityIdentifier("homeActivationProgressText")
                }

                Button(presentation.actionTitle, action: primaryAction)
                    .listendProminentButtonStyle()
                    .accessibilityIdentifier("homeActivationActionButton")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeActivationModule")
    }

    private var iconName: String {
        switch presentation.phase {
        case .empty:
            return "square.and.pencil"
        case .collecting:
            return "waveform.path"
        case .readyToCreate:
            return "sparkles"
        case .hidden:
            return "waveform.path"
        }
    }
}

struct LatestTasteSignalLine: View {
    let signals: [LatestTasteSignal]

    private var labelsText: String {
        signals.map(\.displayLabel).joined(separator: " · ")
    }

    var body: some View {
        Text("Your latest log reinforced: \(labelsText)")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.listendInk)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Your latest log reinforced: \(labelsText)")
            .accessibilityIdentifier("homeLatestTasteSignalText")
    }
}
