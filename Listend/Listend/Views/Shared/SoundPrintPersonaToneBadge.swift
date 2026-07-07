//
//  SoundPrintPersonaToneBadge.swift
//  Listend
//

import SwiftUI

struct SoundPrintPersonaToneBadge: View {
    let tone: SoundPrintPersonaTone
    @State private var isShowingInfo = false

    var body: some View {
        HStack(spacing: 4) {
            Label(tone.userFacingTitle, systemImage: systemImage)
                .labelStyle(.titleAndIcon)

            Button {
                isShowingInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(tone.userFacingTitle)")
            .popover(isPresented: $isShowingInfo) {
                Text(tone.userFacingDescription)
                    .font(.subheadline)
                    .foregroundStyle(Color.listendInk)
                    .padding(ListendSpacing.lg)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(Color.listendMutedInk)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.listendHairline.opacity(0.45), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("soundPrintPersonaToneBadge")
    }

    private var systemImage: String {
        switch tone {
        case .analyst:
            return "chart.bar.doc.horizontal"
        case .balanced:
            return "scalemass"
        case .wrapped:
            return "party.popper"
        }
    }
}
