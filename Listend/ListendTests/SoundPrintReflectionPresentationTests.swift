//
//  SoundPrintReflectionPresentationTests.swift
//  ListendTests
//

import Testing
@testable import Listend

struct SoundPrintReflectionPresentationTests {
    @Test func collectingMapsToAccurateProgressWithoutAction() {
        let presentation = makePresentation(logCount: 3)

        #expect(presentation.title == "SoundPrint")
        #expect(presentation.progressText == "3 of 5 logs")
        #expect(presentation.primaryAction == .none)
        #expect(!presentation.canOpenReflection)
    }

    @Test func readyMapsToExplicitCreateCopyAndAction() {
        let presentation = makePresentation(logCount: 5)

        #expect(presentation.title == "Your first SoundPrint is ready")
        #expect(presentation.description.contains("ratings, reactions, and notes"))
        #expect(presentation.primaryAction == .create)
        #expect(!presentation.canOpenReflection)
    }

    @Test func currentMapsToReflectionLinkAndNewLogStatus() {
        let presentation = makePresentation(logCount: 7, representedLogCount: 5)

        #expect(presentation.title == "SoundPrint Reflection")
        #expect(presentation.freshnessText == "2 of 5 new logs toward your next SoundPrint update")
        #expect(presentation.primaryAction == .view)
        #expect(presentation.canOpenReflection)
    }

    @Test func oneNewLogStillExplainsTheFiveLogUpdateThreshold() {
        let presentation = makePresentation(logCount: 6, representedLogCount: 5)

        #expect(presentation.freshnessText == "1 of 5 new logs toward your next SoundPrint update")
    }

    @Test func fiveNewLogsMapToExplicitUpdateAction() {
        let presentation = makePresentation(logCount: 10, representedLogCount: 5)

        #expect(presentation.description == "Your SoundPrint is ready for an update.")
        #expect(presentation.freshnessText == nil)
        #expect(presentation.primaryAction == .update)
        #expect(presentation.canOpenReflection)
    }

    @Test func historyChangeExplainsEarlyUpdate() {
        let presentation = makePresentation(
            logCount: 6,
            representedLogCount: 5,
            historyChanged: true
        )

        #expect(presentation.freshnessText == "Your listening history changed since this reflection.")
        #expect(presentation.primaryAction == .update)
    }

    private func makePresentation(
        logCount: Int,
        representedLogCount: Int? = nil,
        historyChanged: Bool = false
    ) -> SoundPrintReflectionPresentation {
        SoundPrintReflectionPresentation(
            status: SoundPrintReflectionStatus.resolve(
                logCount: logCount,
                representedLogCount: representedLogCount,
                historyChanged: historyChanged
            )
        )
    }
}
