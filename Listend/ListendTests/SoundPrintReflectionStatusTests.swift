//
//  SoundPrintReflectionStatusTests.swift
//  ListendTests
//

import Testing
@testable import Listend

@MainActor
struct SoundPrintReflectionStatusTests {
    @Test func zeroLogsAreCollecting() {
        let status = SoundPrintReflectionStatus.resolve(
            logCount: 0,
            representedLogCount: nil,
            historyChanged: false
        )

        #expect(status.phase == .collecting)
        #expect(status.logCount == 0)
        #expect(status.requiredLogCount == 5)
        #expect(status.representedLogCount == nil)
        #expect(status.newLogCount == 0)
        #expect(status.updateReason == nil)
    }

    @Test func fourLogsAreCollectingWithAccurateProgress() {
        let status = SoundPrintReflectionStatus.resolve(
            logCount: 4,
            representedLogCount: nil,
            historyChanged: false
        )

        #expect(status.phase == .collecting)
        #expect(status.logCount == 4)
        #expect(status.requiredLogCount == 5)
    }

    @Test func fiveLogsWithoutReflectionAreReadyToCreate() {
        let status = SoundPrintReflectionStatus.resolve(
            logCount: 5,
            representedLogCount: nil,
            historyChanged: false
        )

        #expect(status.phase == .readyToCreate)
        #expect(status.representedLogCount == nil)
        #expect(status.newLogCount == 0)
    }

    @Test func representedAtFiveWithFiveTotalIsCurrent() {
        let status = SoundPrintReflectionStatus.resolve(
            logCount: 5,
            representedLogCount: 5,
            historyChanged: false
        )

        #expect(status.phase == .current)
        #expect(status.representedLogCount == 5)
        #expect(status.newLogCount == 0)
        #expect(status.updateReason == nil)
    }

    @Test func representedAtFiveWithNineTotalIsCurrent() {
        let status = SoundPrintReflectionStatus.resolve(
            logCount: 9,
            representedLogCount: 5,
            historyChanged: false
        )

        #expect(status.phase == .current)
        #expect(status.newLogCount == 4)
        #expect(status.updateReason == nil)
    }

    @Test func representedAtFiveWithTenTotalIsReadyToUpdate() {
        let status = SoundPrintReflectionStatus.resolve(
            logCount: 10,
            representedLogCount: 5,
            historyChanged: false
        )

        #expect(status.phase == .readyToUpdate)
        #expect(status.newLogCount == 5)
        #expect(status.updateReason == .newLogs(5))
    }

    @Test func explicitHistoryChangeIsReadyToUpdateBeforeFiveNewLogs() {
        let status = SoundPrintReflectionStatus.resolve(
            logCount: 6,
            representedLogCount: 5,
            historyChanged: true
        )

        #expect(status.phase == .readyToUpdate)
        #expect(status.newLogCount == 1)
        #expect(status.updateReason == .historyChanged)
    }

    @Test func totalBelowRepresentedCountIsReadyToUpdate() {
        let status = SoundPrintReflectionStatus.resolve(
            logCount: 5,
            representedLogCount: 6,
            historyChanged: false
        )

        #expect(status.phase == .readyToUpdate)
        #expect(status.newLogCount == 0)
        #expect(status.updateReason == .historyChanged)
    }

    @Test func belowThresholdTotalCollectsEvenWithStaleRepresentation() {
        let status = SoundPrintReflectionStatus.resolve(
            logCount: 4,
            representedLogCount: 5,
            historyChanged: true
        )

        #expect(status.phase == .collecting)
        #expect(status.representedLogCount == 5)
        #expect(status.newLogCount == 0)
        #expect(status.updateReason == nil)
    }

    @Test func newLogCountNeverBecomesNegative() {
        let status = SoundPrintReflectionStatus.resolve(
            logCount: 5,
            representedLogCount: 8,
            historyChanged: false
        )

        #expect(status.newLogCount == 0)
    }
}
