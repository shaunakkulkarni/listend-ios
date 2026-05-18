//
//  JournalAssistServiceEnvironment.swift
//  Listend
//
//  Created by Codex on 5/18/26.
//

import SwiftUI

private struct JournalAssistServiceEnvironmentKey: EnvironmentKey {
    static let defaultValue: JournalAssistServiceProtocol = MockJournalAssistService()
}

extension EnvironmentValues {
    var journalAssistService: JournalAssistServiceProtocol {
        get { self[JournalAssistServiceEnvironmentKey.self] }
        set { self[JournalAssistServiceEnvironmentKey.self] = newValue }
    }
}
