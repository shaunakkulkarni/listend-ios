//
//  SoundPrintGenerationSource.swift
//  Listend
//

enum SoundPrintGenerationSource: String {
    case foundationModels
    case localFallback
    case unavailable
    case unknown

    init(rawValue: String?) {
        guard let rawValue, let source = SoundPrintGenerationSource(rawValue: rawValue) else {
            self = .unknown
            return
        }

        self = source
    }

    var userFacingTitle: String? {
        switch self {
        case .foundationModels:
            return "Apple Intelligence"
        case .localFallback:
            return "Local fallback"
        case .unavailable:
            return "SoundPrint unavailable"
        case .unknown:
            return nil
        }
    }
}
