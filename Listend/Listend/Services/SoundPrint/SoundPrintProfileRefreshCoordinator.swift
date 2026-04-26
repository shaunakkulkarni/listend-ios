//
//  SoundPrintProfileRefreshCoordinator.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class SoundPrintProfileRefreshCoordinator {
    private(set) var isRebuilding = false
    private(set) var lastError: String?

    private var needsAnotherRefresh = false

    func refreshProfile(in modelContext: ModelContext) async {
        await refreshProfile(in: modelContext, provider: MockSoundPrintProvider())
    }

    func refreshProfile(in modelContext: ModelContext, provider: SoundPrintProvider) async {
        if isRebuilding {
            needsAnotherRefresh = true
            return
        }

        isRebuilding = true
        defer {
            isRebuilding = false
        }

        repeat {
            needsAnotherRefresh = false

            do {
                try await SoundPrintProfileBuilder(provider: provider).rebuildProfile(in: modelContext)
                lastError = nil
            } catch {
                lastError = "Could not refresh SoundPrint profile."
            }
        } while needsAnotherRefresh
    }
}
