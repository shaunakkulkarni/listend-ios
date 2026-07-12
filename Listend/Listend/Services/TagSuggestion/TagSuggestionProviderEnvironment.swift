//
//  TagSuggestionProviderEnvironment.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

import SwiftUI

extension EnvironmentValues {
    @Entry var tagSuggestionProvider: TagSuggestionProvider = MockTagSuggestionProvider()
}
