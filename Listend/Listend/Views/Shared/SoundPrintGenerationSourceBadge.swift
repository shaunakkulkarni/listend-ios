//
//  SoundPrintGenerationSourceBadge.swift
//  Listend
//

import SwiftUI

struct SoundPrintGenerationSourceBadge: View {
    let source: SoundPrintGenerationSource
    @State private var isShowingInfo = false

    var body: some View {
        if let title = source.userFacingTitle {
            HStack(spacing: 4) {
                Label(title, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)

                Button {
                    isShowingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(title)")
                .popover(isPresented: $isShowingInfo) {
                    Text("Local fallback keeps SoundPrint available when Apple Intelligence is unavailable on this device.")
                        .font(.subheadline)
                        .foregroundStyle(Color.listendInk)
                        .padding(ListendSpacing.lg)
                        .presentationCompactAdaptation(.popover)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("soundPrintGenerationSourceBadge")
        }
    }

    private var systemImage: String {
        switch source {
        case .foundationModels:
            return "sparkles"
        case .localFallback:
            return "waveform.path"
        case .unavailable:
            return "exclamationmark.triangle"
        case .unknown:
            return "questionmark"
        }
    }

    private var foregroundColor: Color {
        switch source {
        case .foundationModels:
            return Color.listendAccent
        case .localFallback, .unavailable, .unknown:
            return Color.listendMutedInk
        }
    }

    private var backgroundColor: Color {
        switch source {
        case .foundationModels:
            return Color.listendAccentSoft
        case .localFallback, .unavailable, .unknown:
            return Color.listendHairline.opacity(0.45)
        }
    }
}
