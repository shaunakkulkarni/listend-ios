//
//  SoundPrintReflectionPresentation.swift
//  Listend
//

struct SoundPrintReflectionPresentation: Equatable {
    enum PrimaryAction: Equatable {
        case none
        case create
        case view
        case update
    }

    let title: String
    let description: String
    let progressText: String?
    let freshnessText: String?
    let primaryAction: PrimaryAction
    let canOpenReflection: Bool

    init(status: SoundPrintReflectionStatus) {
        switch status.phase {
        case .collecting:
            title = "SoundPrint"
            description = status.logCount == 0
                ? "A reflection on what your listening journal is revealing."
                : "Ratings and reactions make your first reflection more specific."
            progressText = "\(status.logCount) of \(status.requiredLogCount) logs"
            freshnessText = nil
            primaryAction = .none
            canOpenReflection = false

        case .readyToCreate:
            title = "Your first SoundPrint is ready"
            description = "Create a private reflection from your ratings, reactions, and notes."
            progressText = nil
            freshnessText = nil
            primaryAction = .create
            canOpenReflection = false

        case .current:
            title = "SoundPrint Reflection"
            description = "A reflection on what your listening journal is revealing."
            progressText = nil
            freshnessText = status.newLogCount > 0
                ? Self.newLogsText(status.newLogCount)
                : nil
            primaryAction = .view
            canOpenReflection = true

        case .readyToUpdate:
            title = "SoundPrint Reflection"
            description = "Your SoundPrint is ready for an update."
            progressText = nil
            freshnessText = Self.updateReasonText(status.updateReason)
            primaryAction = .update
            canOpenReflection = true
        }
    }

    private static func newLogsText(_ count: Int) -> String {
        "\(count) new \(count == 1 ? "log" : "logs") since this reflection"
    }

    private static func updateReasonText(_ reason: SoundPrintReflectionStatus.UpdateReason?) -> String {
        switch reason {
        case .newLogs(let count):
            return newLogsText(count)
        case .historyChanged:
            return "Your listening history changed since this reflection."
        case nil:
            return "Your recent listening is ready to be reflected."
        }
    }
}
