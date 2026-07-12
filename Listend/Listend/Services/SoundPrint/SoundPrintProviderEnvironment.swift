//
//  SoundPrintProviderEnvironment.swift
//  Listend
//
//  Created by Codex on 5/3/26.
//

import SwiftUI

extension EnvironmentValues {
    @Entry var soundPrintProvider: SoundPrintProvider = MockSoundPrintProvider()
}
