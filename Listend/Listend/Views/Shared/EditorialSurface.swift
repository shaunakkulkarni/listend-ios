//
//  EditorialSurface.swift
//  Listend
//
//  Created by Codex on 5/5/26.
//

import SwiftUI

struct EditorialSurface<Content: View>: View {
    let isInteractive: Bool
    let content: Content

    init(isInteractive: Bool = false, @ViewBuilder content: () -> Content) {
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(EditorialSurfaceStyle(isInteractive: isInteractive))
    }
}

private struct EditorialSurfaceStyle: ViewModifier {
    let isInteractive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                content
                    .glassEffect(.regular.tint(.primary.opacity(0.04)).interactive(isInteractive), in: .rect(cornerRadius: 8))
            }
        } else {
            content
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.35), lineWidth: 1)
                }
        }
    }
}

extension View {
    @ViewBuilder
    func listendProminentButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}
