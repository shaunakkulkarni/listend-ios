//
//  HomeActivationPresentation.swift
//  Listend
//

enum HomeActivationPhase: Equatable {
    case empty
    case collecting(current: Int, required: Int)
    case readyToCreate
    case hidden
}

struct HomeActivationPresentation: Equatable {
    let phase: HomeActivationPhase

    static func resolve(
        logCount: Int,
        representedLogCount: Int?,
        historyChanged: Bool = false
    ) -> HomeActivationPresentation {
        let status = SoundPrintReflectionStatus.resolve(
            logCount: logCount,
            representedLogCount: representedLogCount,
            historyChanged: historyChanged
        )

        switch status.phase {
        case .collecting where status.logCount == 0:
            return HomeActivationPresentation(phase: .empty)
        case .collecting:
            return HomeActivationPresentation(
                phase: .collecting(
                    current: status.logCount,
                    required: status.requiredLogCount
                )
            )
        case .readyToCreate:
            return HomeActivationPresentation(phase: .readyToCreate)
        case .current, .readyToUpdate:
            return HomeActivationPresentation(phase: .hidden)
        }
    }

    var isVisible: Bool {
        phase != .hidden
    }

    var title: String {
        switch phase {
        case .empty:
            return "Start your listening journal"
        case .collecting:
            return "Your SoundPrint is taking shape"
        case .readyToCreate:
            return "Your first SoundPrint is ready"
        case .hidden:
            return ""
        }
    }

    var description: String {
        switch phase {
        case .empty:
            return "Log an album to begin building a record of what resonates with you."
        case .collecting:
            return "Ratings and reactions make your reflection more specific."
        case .readyToCreate:
            return "Create a private reflection from your ratings, reactions, and notes."
        case .hidden:
            return ""
        }
    }

    var progressText: String? {
        guard case let .collecting(current, required) = phase else {
            return nil
        }

        return "\(current) of \(required) logs"
    }

    var actionTitle: String {
        switch phase {
        case .empty:
            return "Add Your First Log"
        case .collecting:
            return "Add Another Log"
        case .readyToCreate:
            return "Create My Reflection"
        case .hidden:
            return ""
        }
    }
}
