//
//  JournalAssistServiceEnvironment.swift
//  Listend
//
//  Created by Codex on 5/18/26.
//

import SwiftUI

extension EnvironmentValues {
    @Entry var journalAssistService: JournalAssistServiceProtocol = MockJournalAssistService()
}
