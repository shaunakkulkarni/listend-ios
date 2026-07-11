//
//  SandboxMode.swift
//  Listend
//

enum SandboxMode {
    #if SANDBOX
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif
}

enum SandboxIntelligenceProvider: String, CaseIterable, Identifiable {
    case mock
    case onDevice

    static let `default`: Self = .mock

    init(rawValue: String?) {
        guard let rawValue, let provider = Self(rawValue: rawValue) else {
            self = .default
            return
        }

        self = provider
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mock: return "Mock Intelligence"
        case .onDevice: return "On-device Apple Intelligence"
        }
    }

    var detail: String {
        switch self {
        case .mock:
            return "Uses predictable local results for repeatable testing."
        case .onDevice:
            return "Uses Apple Intelligence for SoundPrint, sentiment, tags, and Journal Assist, with safe local fallbacks."
        }
    }
}
