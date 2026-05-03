//
//  SoundPrintProviderEnvironment.swift
//  Listend
//
//  Created by Codex on 5/3/26.
//

import SwiftUI

private struct SoundPrintProviderEnvironmentKey: EnvironmentKey {
    static let defaultValue: SoundPrintProvider = MockSoundPrintProvider()
}

extension EnvironmentValues {
    var soundPrintProvider: SoundPrintProvider {
        get { self[SoundPrintProviderEnvironmentKey.self] }
        set { self[SoundPrintProviderEnvironmentKey.self] = newValue }
    }
}
