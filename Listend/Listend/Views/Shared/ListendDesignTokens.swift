//
//  ListendDesignTokens.swift
//  Listend
//

import SwiftUI

// Color.listendPaper, .listendSurface, .listendInk, .listendMutedInk,
// .listendHairline, .listendAccent, and .listendAccentSoft are generated
// automatically from Assets.xcassets (Xcode's asset symbol generation).

extension Color {
    static let listendDestructive = Color.red
}

enum ListendSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum ListendRadius {
    static let chip: CGFloat = 10
    static let control: CGFloat = 14
    static let card: CGFloat = 20
    static let artwork: CGFloat = 16
}
