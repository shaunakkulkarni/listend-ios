//
//  HomeActivationAndTasteSignalTests.swift
//  ListendTests
//

import Foundation
import Testing
@testable import Listend

@MainActor
struct HomeActivationAndTasteSignalTests {
    @Test func zeroLogsShowFirstLogActivation() {
        let presentation = HomeActivationPresentation.resolve(
            logCount: 0,
            representedLogCount: nil
        )

        #expect(presentation.phase == .empty)
        #expect(presentation.isVisible)
        #expect(presentation.progressText == nil)
        #expect(presentation.actionTitle == "Add Your First Log")
    }

    @Test func everyPreThresholdLogCountShowsActualCollectingProgress() {
        let required = SoundPrintProfileThresholds.personaMinimumLogCount

        for current in 1..<required {
            let presentation = HomeActivationPresentation.resolve(
                logCount: current,
                representedLogCount: nil
            )

            #expect(presentation.phase == .collecting(current: current, required: required))
            #expect(presentation.progressText == "\(current) of \(required) logs")
            #expect(presentation.actionTitle == "Add Another Log")
        }
    }

    @Test func thresholdWithoutReflectionIsReadyToCreate() {
        let presentation = HomeActivationPresentation.resolve(
            logCount: SoundPrintProfileThresholds.personaMinimumLogCount,
            representedLogCount: nil
        )

        #expect(presentation.phase == .readyToCreate)
        #expect(presentation.isVisible)
        #expect(presentation.progressText == nil)
        #expect(presentation.actionTitle == "Create My Reflection")
    }

    @Test func currentAndReadyToUpdateReflectionsHideActivation() {
        let represented = SoundPrintProfileThresholds.personaMinimumLogCount
        let current = HomeActivationPresentation.resolve(
            logCount: represented,
            representedLogCount: represented
        )
        let readyToUpdate = HomeActivationPresentation.resolve(
            logCount: represented,
            representedLogCount: represented,
            historyChanged: true
        )

        #expect(current.phase == .hidden)
        #expect(!current.isVisible)
        #expect(readyToUpdate.phase == .hidden)
        #expect(!readyToUpdate.isVisible)
    }

    @Test func selectorUsesLatestPositiveEvidenceAndRanksStrengthThenConfidence() {
        let latestLogID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let olderLogID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let dimensions = [
            dimension(name: "vocalFocus", label: "Vocal focus"),
            dimension(name: "productionStyle", label: "Layered production"),
            dimension(name: "replayability", label: "Replay pull")
        ]
        let evidence = [
            tasteEvidence(
                dimensionName: "replayability",
                logEntryID: latestLogID,
                strength: 0.8,
                confidence: 1.0
            ),
            tasteEvidence(
                dimensionName: "productionStyle",
                logEntryID: latestLogID,
                strength: 0.9,
                confidence: 0.5
            ),
            tasteEvidence(
                dimensionName: "vocalFocus",
                logEntryID: latestLogID,
                strength: 0.9,
                confidence: 0.7
            ),
            tasteEvidence(
                dimensionName: "replayability",
                logEntryID: olderLogID,
                strength: 1.0,
                confidence: 1.0
            )
        ]

        let result = LatestTasteSignalSelector.select(
            latestLogID: latestLogID,
            evidence: evidence,
            dimensions: dimensions
        )

        #expect(result == [
            LatestTasteSignal(dimensionName: "vocalFocus", displayLabel: "Vocal focus"),
            LatestTasteSignal(dimensionName: "productionStyle", displayLabel: "Layered production")
        ])
    }

    @Test func selectorRejectsNegativeAndUnmappedEvidenceAndDeduplicatesLabels() {
        let latestLogID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let dimensions = [
            dimension(name: "productionStyle", label: "Layered production"),
            dimension(name: "texture", label: "Layered production"),
            dimension(name: "vocalFocus", label: "Vocal focus")
        ]
        let evidence = [
            tasteEvidence(
                dimensionName: "unmappedInternalName",
                logEntryID: latestLogID,
                strength: 1.0,
                confidence: 1.0
            ),
            tasteEvidence(
                dimensionName: "vocalFocus",
                logEntryID: latestLogID,
                strength: 0.99,
                confidence: 1.0,
                isPositiveEvidence: false
            ),
            tasteEvidence(
                dimensionName: "productionStyle",
                logEntryID: latestLogID,
                strength: 0.9,
                confidence: 1.0
            ),
            tasteEvidence(
                dimensionName: "texture",
                logEntryID: latestLogID,
                strength: 0.8,
                confidence: 1.0
            ),
            tasteEvidence(
                dimensionName: "vocalFocus",
                logEntryID: latestLogID,
                strength: 0.7,
                confidence: 1.0
            )
        ]

        let result = LatestTasteSignalSelector.select(
            latestLogID: latestLogID,
            evidence: evidence,
            dimensions: dimensions
        )

        #expect(result == [
            LatestTasteSignal(dimensionName: "productionStyle", displayLabel: "Layered production"),
            LatestTasteSignal(dimensionName: "vocalFocus", displayLabel: "Vocal focus")
        ])
    }

    @Test func selectorUsesStableTextOrderingForTies() {
        let latestLogID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let dimensions = [
            dimension(name: "vocalFocus", label: "Vocal focus"),
            dimension(name: "productionStyle", label: "Layered production")
        ]
        let vocalEvidence = tasteEvidence(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
            dimensionName: "vocalFocus",
            logEntryID: latestLogID,
            strength: 0.8,
            confidence: 0.8
        )
        let productionEvidence = tasteEvidence(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
            dimensionName: "productionStyle",
            logEntryID: latestLogID,
            strength: 0.8,
            confidence: 0.8
        )

        let forward = LatestTasteSignalSelector.select(
            latestLogID: latestLogID,
            evidence: [vocalEvidence, productionEvidence],
            dimensions: dimensions
        )
        let reversed = LatestTasteSignalSelector.select(
            latestLogID: latestLogID,
            evidence: [productionEvidence, vocalEvidence],
            dimensions: dimensions
        )

        #expect(forward == reversed)
        #expect(forward.map(\.dimensionName) == ["productionStyle", "vocalFocus"])
    }

    @Test func selectorOmitsSignalsWithoutLatestLogOrUsableLabel() {
        let latestLogID = UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
        let evidence = [
            tasteEvidence(
                dimensionName: "vocalFocus",
                logEntryID: latestLogID,
                strength: 1.0,
                confidence: 1.0
            )
        ]

        #expect(LatestTasteSignalSelector.select(
            latestLogID: nil,
            evidence: evidence,
            dimensions: [dimension(name: "vocalFocus", label: "Vocal focus")]
        ).isEmpty)
        #expect(LatestTasteSignalSelector.select(
            latestLogID: latestLogID,
            evidence: evidence,
            dimensions: [dimension(name: "vocalFocus", label: "   ")]
        ).isEmpty)
    }

    @Test func selectorFreshnessRejectsSignalsOlderThanTheLatestLog() {
        let now = Date()

        #expect(!LatestTasteSignalSelector.hasFreshProfile(
            logUpdatedAt: now,
            profileUpdatedAt: nil
        ))
        #expect(!LatestTasteSignalSelector.hasFreshProfile(
            logUpdatedAt: now,
            profileUpdatedAt: now.addingTimeInterval(-1)
        ))
        #expect(LatestTasteSignalSelector.hasFreshProfile(
            logUpdatedAt: now,
            profileUpdatedAt: now
        ))
    }

    private func dimension(name: String, label: String) -> TasteDimension {
        TasteDimension(
            name: name,
            label: label,
            weight: 1.0,
            confidence: 1.0,
            summary: ""
        )
    }

    private func tasteEvidence(
        id: UUID = UUID(),
        dimensionName: String,
        logEntryID: UUID,
        strength: Double,
        confidence: Double,
        isPositiveEvidence: Bool = true
    ) -> TasteEvidence {
        TasteEvidence(
            id: id,
            dimensionName: dimensionName,
            logEntryID: logEntryID,
            snippet: dimensionName,
            evidenceType: "test",
            strength: strength,
            confidence: confidence,
            isPositiveEvidence: isPositiveEvidence
        )
    }
}
