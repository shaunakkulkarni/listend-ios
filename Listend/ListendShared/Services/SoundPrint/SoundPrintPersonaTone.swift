//
//  SoundPrintPersonaTone.swift
//  Listend
//

import Foundation

/// User-selectable voice for all generated SoundPrint text (persona and compact summary).
enum SoundPrintPersonaTone: String, CaseIterable, Identifiable {
    case analyst
    case balanced
    case wrapped

    static let `default`: SoundPrintPersonaTone = .balanced

    init(rawValue: String?) {
        guard let rawValue, let tone = SoundPrintPersonaTone(rawValue: rawValue) else {
            self = .default
            return
        }

        self = tone
    }

    var id: String { rawValue }

    var userFacingTitle: String {
        switch self {
        case .analyst:
            return "Analyst"
        case .balanced:
            return "Balanced"
        case .wrapped:
            return "Wrapped"
        }
    }

    var userFacingDescription: String {
        switch self {
        case .analyst:
            return "Precise and grounded, like a well-written liner note. No jokes, no hype."
        case .balanced:
            return "A sharp friend who actually read your diary. Warm but direct."
        case .wrapped:
            return "End-of-year recap energy. Playful, a little dramatic, still true to your logs."
        }
    }

}
