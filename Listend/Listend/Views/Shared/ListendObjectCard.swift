//
//  ListendObjectCard.swift
//  Listend
//

import SwiftUI

struct ListendObjectCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(ListendSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ListendRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: ListendRadius.card)
                    .stroke(.separator.opacity(0.25), lineWidth: 1)
            }
    }
}
