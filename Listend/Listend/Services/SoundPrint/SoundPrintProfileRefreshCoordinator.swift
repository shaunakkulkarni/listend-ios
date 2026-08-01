//
//  SoundPrintProfileRefreshCoordinator.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

import Foundation
import Observation
import SwiftData

enum SoundPrintLogMutation: Equatable {
    case created
    case updated
}

@Observable
@MainActor
final class SoundPrintProfileRefreshCoordinator {
    private(set) var isRebuilding = false
    private(set) var lastError: String?

    private var activeMode: SoundPrintProfileBuildMode?
    private var pendingMode: SoundPrintProfileBuildMode?

    func processSavedLog(
        _ log: LogEntry,
        mutation: SoundPrintLogMutation,
        in modelContext: ModelContext,
        provider: SoundPrintProvider
    ) async {
        if mutation == .updated {
            markHistoryChangedIfReflectionExists(in: modelContext)
        }

        do {
            try await LogSentimentUpdater(provider: provider).updateSentiment(for: log, in: modelContext)
        } catch is CancellationError {
            return
        } catch {
            // Sentiment persistence must not block deterministic signal maintenance.
        }

        await requestRebuild(.signalsOnly, in: modelContext, provider: provider)
    }

    func processDeletedLog(in modelContext: ModelContext, provider: SoundPrintProvider) async {
        markHistoryChangedIfReflectionExists(in: modelContext)
        await requestRebuild(.signalsOnly, in: modelContext, provider: provider)
    }

    func generateReflection(in modelContext: ModelContext, provider: SoundPrintProvider) async {
        await requestRebuild(.generateReflection, in: modelContext, provider: provider)
    }

    private func requestRebuild(
        _ requestedMode: SoundPrintProfileBuildMode,
        in modelContext: ModelContext,
        provider: SoundPrintProvider
    ) async {
        if isRebuilding {
            enqueue(requestedMode)
            return
        }

        isRebuilding = true
        defer {
            isRebuilding = false
            activeMode = nil
        }

        var nextMode: SoundPrintProfileBuildMode? = requestedMode
        repeat {
            guard let mode = nextMode else {
                return
            }

            activeMode = mode
            pendingMode = nil

            do {
                try await SoundPrintProfileBuilder(provider: provider).rebuildProfile(
                    in: modelContext,
                    mode: mode
                )
                lastError = nil
            } catch is CancellationError {
                return
            } catch let error as SoundPrintProfileBuildError {
                lastError = userFacingMessage(for: error)
            } catch {
                lastError = mode == .generateReflection
                    ? "Could not create your SoundPrint Reflection. Try again."
                    : "Could not refresh SoundPrint signals."
            }

            nextMode = pendingMode
        } while nextMode != nil
    }

    private func enqueue(_ requestedMode: SoundPrintProfileBuildMode) {
        if activeMode == .generateReflection && requestedMode == .generateReflection {
            return
        }

        if pendingMode == .generateReflection || requestedMode == .generateReflection {
            pendingMode = .generateReflection
        } else {
            pendingMode = .signalsOnly
        }
    }

    private func markHistoryChangedIfReflectionExists(in modelContext: ModelContext) {
        let count = try? modelContext.fetchCount(FetchDescriptor<SoundPrintPersona>())
        if (count ?? 0) > 0 {
            UserDefaults.standard.set(true, forKey: SoundPrintPreferenceKey.reflectionNeedsRefresh)
        }
    }

    private func userFacingMessage(for error: SoundPrintProfileBuildError) -> String {
        switch error {
        case .insufficientLogs:
            return "Log at least five albums before creating your SoundPrint."
        case .invalidReflection:
            return "SoundPrint could not create a valid reflection. Try again."
        case .unavailable:
            return "SoundPrint could not create a reflection right now. Try again."
        }
    }
}
