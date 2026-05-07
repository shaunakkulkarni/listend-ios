//
//  TagSuggestionProviderEnvironment.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

import SwiftUI

private struct TagSuggestionProviderEnvironmentKey: EnvironmentKey {
    static let defaultValue: TagSuggestionProvider = MockTagSuggestionProvider()
}

extension EnvironmentValues {
    var tagSuggestionProvider: TagSuggestionProvider {
        get { self[TagSuggestionProviderEnvironmentKey.self] }
        set { self[TagSuggestionProviderEnvironmentKey.self] = newValue }
    }
}

