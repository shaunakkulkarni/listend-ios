//
//  SoundPrintSettings.swift
//  Listend
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum SoundPrintPreferenceKey {
    static let preferAppleIntelligence = "soundPrint.preferAppleIntelligence"
}

enum SoundPrintProviderFactory {
    static func makeProvider(
        preferAppleIntelligence: Bool,
        isUITesting: Bool,
        isSimulator: Bool
    ) -> SoundPrintProvider {
        if isUITesting || isSimulator || !preferAppleIntelligence {
            return MockSoundPrintProvider()
        }

        return FallbackSoundPrintProvider(
            primary: FoundationModelsSoundPrintProvider(),
            fallback: MockSoundPrintProvider()
        )
    }
}

struct SoundPrintAppleIntelligenceAvailability: Equatable {
    enum State: Equatable {
        case available
        case supportedUnavailable(String)
        case unsupported(String)
    }

    let state: State

    static var current: SoundPrintAppleIntelligenceAvailability {
        #if targetEnvironment(simulator)
        return SoundPrintAppleIntelligenceAvailability(state: .unsupported("Apple Intelligence is not available in Simulator."))
        #elseif canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return SoundPrintAppleIntelligenceAvailability(state: .available)
            case .unavailable(.appleIntelligenceNotEnabled):
                return SoundPrintAppleIntelligenceAvailability(
                    state: .supportedUnavailable("Apple Intelligence is off. Turn it on in Settings > Apple Intelligence & Siri.")
                )
            case .unavailable(.modelNotReady):
                return SoundPrintAppleIntelligenceAvailability(
                    state: .supportedUnavailable("Apple Intelligence models are not ready yet. Keep the device on Wi-Fi and power, then try again.")
                )
            case .unavailable(.deviceNotEligible):
                return SoundPrintAppleIntelligenceAvailability(
                    state: .unsupported("This device, OS, language, region, or Apple Account is not eligible for Apple Intelligence.")
                )
            @unknown default:
                return SoundPrintAppleIntelligenceAvailability(
                    state: .supportedUnavailable("Foundation Models availability: \(String(describing: SystemLanguageModel.default.availability))")
                )
            }
        }

        return SoundPrintAppleIntelligenceAvailability(state: .unsupported("Apple Intelligence requires iOS 26 or later."))
        #else
        return SoundPrintAppleIntelligenceAvailability(state: .unsupported("This build does not include Foundation Models support."))
        #endif
    }

    var isToggleVisible: Bool {
        switch state {
        case .available, .supportedUnavailable:
            return true
        case .unsupported:
            return false
        }
    }

    var headline: String {
        switch state {
        case .available:
            return "Apple Intelligence is ready for SoundPrint."
        case .supportedUnavailable:
            return "Apple Intelligence is supported, but not available right now."
        case .unsupported:
            return "SoundPrint is using Local fallback on this device."
        }
    }

    var technicalDetail: String {
        switch state {
        case .available:
            return "Foundation Models availability: available"
        case .supportedUnavailable(let detail), .unsupported(let detail):
            return detail
        }
    }
}

struct SoundPrintSettingsDisplayState: Equatable {
    let preferAppleIntelligence: Bool
    let latestSource: SoundPrintGenerationSource
    let availability: SoundPrintAppleIntelligenceAvailability

    var statusTitle: String {
        switch latestSource {
        case .foundationModels:
            return "Apple Intelligence"
        case .localFallback where preferAppleIntelligence:
            return "Apple Intelligence preferred, using Local fallback"
        case .localFallback:
            return "Using Local fallback"
        case .unavailable:
            return "SoundPrint unavailable"
        case .unknown:
            return "SoundPrint not generated yet"
        }
    }

    var statusDetail: String {
        switch latestSource {
        case .foundationModels:
            return "Latest SoundPrint was generated with Apple Intelligence."
        case .localFallback where preferAppleIntelligence && availability.state == .available:
            return "Apple Intelligence is available, but the latest SoundPrint fell back locally after generation did not produce a valid profile."
        case .localFallback where preferAppleIntelligence:
            return "Listend will try Apple Intelligence first and keep SoundPrint available locally when needed."
        case .localFallback:
            return "SoundPrint is set to use the local fallback."
        case .unavailable:
            return "SoundPrint could not generate a profile from the current logs."
        case .unknown:
            return "Try Apple Intelligence after you have enough logs for a persona."
        }
    }

    var currentGeneratorTitle: String {
        latestSource.userFacingTitle ?? "Not generated yet"
    }
}
