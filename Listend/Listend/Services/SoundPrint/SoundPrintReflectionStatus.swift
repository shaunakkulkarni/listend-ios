//
//  SoundPrintReflectionStatus.swift
//  Listend
//
//  Pure reflection eligibility and freshness policy. Callers supply a snapshot
//  rather than a SwiftData model so this state remains deterministic and easy to test.
//

struct SoundPrintReflectionStatus: Equatable {
    enum Phase: Equatable {
        case collecting
        case readyToCreate
        case current
        case readyToUpdate
    }

    enum UpdateReason: Equatable {
        case newLogs(Int)
        case historyChanged
    }

    let phase: Phase
    let logCount: Int
    let requiredLogCount: Int
    let representedLogCount: Int?
    let newLogCount: Int
    let updateReason: UpdateReason?

    static func resolve(
        logCount: Int,
        representedLogCount: Int?,
        historyChanged: Bool
    ) -> SoundPrintReflectionStatus {
        let currentLogCount = max(0, logCount)
        let requiredLogCount = SoundPrintProfileThresholds.personaMinimumLogCount
        let representedLogCount = representedLogCount.map { max(0, $0) }
        let newLogCount = representedLogCount.map {
            max(0, currentLogCount - $0)
        } ?? 0

        guard currentLogCount >= requiredLogCount else {
            return SoundPrintReflectionStatus(
                phase: .collecting,
                logCount: currentLogCount,
                requiredLogCount: requiredLogCount,
                representedLogCount: representedLogCount,
                newLogCount: newLogCount,
                updateReason: nil
            )
        }

        guard let representedLogCount else {
            return SoundPrintReflectionStatus(
                phase: .readyToCreate,
                logCount: currentLogCount,
                requiredLogCount: requiredLogCount,
                representedLogCount: nil,
                newLogCount: 0,
                updateReason: nil
            )
        }

        let updateReason: UpdateReason?
        if historyChanged || currentLogCount < representedLogCount {
            updateReason = .historyChanged
        } else if newLogCount >= SoundPrintProfileThresholds.reflectionRefreshLogIncrement {
            updateReason = .newLogs(newLogCount)
        } else {
            updateReason = nil
        }

        return SoundPrintReflectionStatus(
            phase: updateReason == nil ? .current : .readyToUpdate,
            logCount: currentLogCount,
            requiredLogCount: requiredLogCount,
            representedLogCount: representedLogCount,
            newLogCount: newLogCount,
            updateReason: updateReason
        )
    }
}
