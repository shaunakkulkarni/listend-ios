//
//  OnboardingView.swift
//  Listend
//

import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.appleMusicAuthorizationService) private var appleMusicAuthorizationService
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \LogEntry.loggedAt, order: .reverse) private var logs: [LogEntry]
    @Query(sort: \SoundPrintPersona.generatedAt, order: .reverse) private var personas: [SoundPrintPersona]

    private let catalogService: AlbumCatalogServiceProtocol
    private let recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol
    private let isReplay: Bool
    private let finish: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var authorizationState: AppleMusicAuthorizationState = .unavailable
    @State private var isRequestingAuthorization = false
    @State private var isShowingLogFlow = false
    @State private var albumForNewLog: Album?

    init(
        catalogService: AlbumCatalogServiceProtocol = MockAlbumCatalogService(),
        recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol = MockRecentlyPlayedAlbumService(),
        isReplay: Bool,
        finish: @escaping () -> Void
    ) {
        self.catalogService = catalogService
        self.recentlyPlayedAlbumService = recentlyPlayedAlbumService
        self.isReplay = isReplay
        self.finish = finish
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ListendSpacing.xl) {
                    progressHeader
                    stepContent
                    stepActions
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, ListendSpacing.xl)
                .padding(.top, ListendSpacing.lg)
                .padding(.bottom, 40)
            }
            .background(Color.listendPaper)
            .navigationTitle(isReplay ? "Introduction" : "Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isReplay {
                        Button("Close", action: finish)
                            .accessibilityIdentifier("onboardingCloseButton")
                    } else if step != .welcome && step != .completion {
                        Button {
                            goBack()
                        } label: {
                            Label("Back", systemImage: "chevron.backward")
                        }
                        .accessibilityIdentifier("onboardingBackButton")
                    }
                }

                if !isReplay && step != .completion {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Skip", action: finish)
                            .accessibilityIdentifier("onboardingSkipButton")
                    }
                }
            }
        }
        .task {
            refreshAuthorizationState()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshAuthorizationState()
            }
        }
        .sheet(isPresented: $isShowingLogFlow, onDismiss: {
            albumForNewLog = nil
        }) {
            onboardingLogFlow
        }
        .accessibilityIdentifier("onboardingView")
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.sm) {
            Text("GETTING STARTED")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(Color.listendMutedInk)

            ProgressView(
                value: Double(step.rawValue + 1),
                total: Double(OnboardingStep.allCases.count)
            )
            .tint(Color.listendAccent)
            .accessibilityLabel("Introduction progress")
            .accessibilityValue("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeContent
        case .tasteLoop:
            tasteLoopContent
        case .appleMusic:
            appleMusicContent
        case .journal:
            journalContent
        case .completion:
            completionContent
        }
    }

    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.lg) {
            Image(systemName: "record.circle")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Color.listendAccent)
                .accessibilityHidden(true)

            Text("A journal for the albums that stay with you.")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.listendInk)
                .fixedSize(horizontal: false, vertical: true)

            Text("Rate albums, remember why they mattered, and watch your listening patterns develop over time.")
                .font(.title3)
                .foregroundStyle(Color.listendMutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboardingWelcomeStage")
    }

    private var tasteLoopContent: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.lg) {
            Text("How Listend becomes personal")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.listendInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboardingTasteLoopStage")

            Text("Your ratings, reactions, notes, favorite tracks, and weaker tracks add context to every entry.")
                .font(.body)
                .foregroundStyle(Color.listendMutedInk)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: ListendSpacing.md) {
                OnboardingLoopRow(
                    number: 1,
                    title: "Log what you heard",
                    detail: "Save the album and the details that mattered to you."
                )
                OnboardingLoopRow(
                    number: 2,
                    title: "See your taste take shape",
                    detail: "Listend builds grounded signals from the journal you create."
                )
                OnboardingLoopRow(
                    number: 3,
                    title: "Get one thoughtful discovery",
                    detail: "More listening history gives each future pick stronger context."
                )
            }
        }
    }

    private var appleMusicContent: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.lg) {
            Image(systemName: "apple.logo")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(Color.listendInk)
                .accessibilityHidden(true)

            Text("Make logging faster with Apple Music")
                .font(.largeTitle.bold())
                .foregroundStyle(Color.listendInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboardingAppleMusicStage")

            Text("Connect Apple Music to bring in recently played albums and make logging faster.")
                .font(.title3)
                .foregroundStyle(Color.listendMutedInk)
                .fixedSize(horizontal: false, vertical: true)

            ListendObjectCard {
                HStack(alignment: .top, spacing: ListendSpacing.md) {
                    Image(systemName: appleMusicStatusSymbol)
                        .font(.title2)
                        .foregroundStyle(Color.listendAccent)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: ListendSpacing.xs) {
                        Text(appleMusicStatusTitle)
                            .font(.headline)
                        Text(appleMusicStatusDetail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("onboardingAppleMusicStatus")

            Text("Apple Music is optional. You can keep logging if access is unavailable or you decide not to connect.")
                .font(.footnote)
                .foregroundStyle(Color.listendMutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var journalContent: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.lg) {
            Image(systemName: logs.isEmpty ? "square.and.pencil" : "checkmark.circle.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(Color.listendAccent)
                .accessibilityHidden(true)

            Text(logs.isEmpty ? "Start your listening journal" : journalProgressTitle)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.listendInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("onboardingJournalStage")

            Text(journalProgressDetail)
                .font(.title3)
                .foregroundStyle(Color.listendMutedInk)
                .fixedSize(horizontal: false, vertical: true)

            if !logs.isEmpty {
                ListendObjectCard {
                    VStack(alignment: .leading, spacing: ListendSpacing.sm) {
                        Text("\(min(logs.count, firstReflectionThreshold)) of \(firstReflectionThreshold) logs")
                            .font(.headline)
                        ProgressView(
                            value: Double(min(logs.count, firstReflectionThreshold)),
                            total: Double(firstReflectionThreshold)
                        )
                        .tint(Color.listendAccent)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("SoundPrint progress")
                .accessibilityValue("\(min(logs.count, firstReflectionThreshold)) of \(firstReflectionThreshold) logs")
                .accessibilityIdentifier("onboardingJournalProgress")
            }
        }
    }

    private var completionContent: some View {
        VStack(alignment: .leading, spacing: ListendSpacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(Color.listendAccent)
                .accessibilityHidden(true)

            Text(completionTitle)
                .font(.largeTitle.bold())
                .foregroundStyle(Color.listendInk)
                .fixedSize(horizontal: false, vertical: true)

            Text(completionDetail)
                .font(.title3)
                .foregroundStyle(Color.listendMutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboardingCompletionStage")
    }

    @ViewBuilder
    private var stepActions: some View {
        switch step {
        case .welcome:
            primaryButton("Get Started", identifier: "onboardingGetStartedButton") {
                step = .tasteLoop
            }
        case .tasteLoop:
            primaryButton("Continue", identifier: "onboardingTasteLoopContinueButton") {
                step = .appleMusic
            }
        case .appleMusic:
            appleMusicActions
        case .journal:
            journalActions
        case .completion:
            primaryButton("Open Listend", identifier: "onboardingOpenListendButton", action: finish)
        }
    }

    @ViewBuilder
    private var appleMusicActions: some View {
        VStack(spacing: ListendSpacing.sm) {
            if authorizationState == .authorized {
                primaryButton("Continue", identifier: "onboardingAppleMusicContinueButton") {
                    step = .journal
                }
            } else {
                Button {
                    requestAppleMusicAuthorization()
                } label: {
                    HStack(spacing: ListendSpacing.sm) {
                        if isRequestingAuthorization {
                            ProgressView()
                        }
                        Text(isRequestingAuthorization ? "Connecting Apple Music…" : "Connect Apple Music")
                    }
                    .frame(maxWidth: .infinity)
                }
                .listendProminentButtonStyle()
                .controlSize(.large)
                .disabled(isRequestingAuthorization || authorizationState == .restricted || authorizationState == .unavailable)
                .accessibilityLabel(isRequestingAuthorization ? "Connecting Apple Music" : "Connect Apple Music")
                .accessibilityIdentifier("onboardingConnectAppleMusicButton")

                Button("Not Now") {
                    step = .journal
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("onboardingAppleMusicNotNowButton")
            }
        }
    }

    @ViewBuilder
    private var journalActions: some View {
        VStack(spacing: ListendSpacing.sm) {
            if logs.isEmpty {
                primaryButton("Add Your First Log", identifier: "onboardingAddFirstLogButton") {
                    isShowingLogFlow = true
                }

                Button("Do This Later") {
                    step = .completion
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("onboardingDoThisLaterButton")
            } else {
                primaryButton("Continue", identifier: "onboardingJournalContinueButton") {
                    step = .completion
                }

                Button("Add Another Log") {
                    isShowingLogFlow = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("onboardingAddAnotherLogButton")
            }
        }
    }

    private func primaryButton(
        _ title: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .listendProminentButtonStyle()
        .controlSize(.large)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var onboardingLogFlow: some View {
        if let albumForNewLog {
            LogEntryEditorView(preselectedAlbum: albumForNewLog)
        } else {
            NavigationStack {
                AlbumSelectionView(
                    catalogService: catalogService,
                    recentlyPlayedAlbumService: recentlyPlayedAlbumService,
                    automaticallyLoadsRecentlyPlayed: authorizationState == .authorized
                ) { album in
                    albumForNewLog = album
                }
            }
        }
    }

    private var firstReflectionThreshold: Int {
        SoundPrintProfileThresholds.personaMinimumLogCount
    }

    private var hasValidReflection: Bool {
        guard let persona = personas.first else {
            return false
        }

        return !persona.personaText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var journalProgressTitle: String {
        switch logs.count {
        case 1:
            return "Your first album is in."
        case 2..<firstReflectionThreshold:
            return "Your SoundPrint is starting to take shape."
        default:
            return hasValidReflection
                ? "Your journal keeps building context."
                : "You have enough history for a SoundPrint Reflection."
        }
    }

    private var journalProgressDetail: String {
        if logs.isEmpty {
            return "Add an album through the existing journal flow, or continue and do it later."
        }

        if logs.count < firstReflectionThreshold {
            return "Ratings and reactions help make your first reflection more specific. You can continue now or add another album."
        }

        return hasValidReflection
            ? "Each new entry gives your listening journal more grounded context."
            : "Create your first reflection from Profile whenever you are ready."
    }

    private var completionTitle: String {
        switch logs.count {
        case 0:
            return "Your journal is ready."
        case 1:
            return "Your first album is in."
        case 2..<firstReflectionThreshold:
            return "Your SoundPrint is starting to take shape."
        default:
            if !hasValidReflection {
                return "You have enough history to create your first SoundPrint Reflection."
            }
            return "Your journal is ready."
        }
    }

    private var completionDetail: String {
        if logs.isEmpty {
            return "Start with any album when you are ready. Logging always remains available without optional integrations."
        }

        if logs.count < firstReflectionThreshold {
            return "Keep logging the albums that matter to you. Your journal will show the progress as it grows."
        }

        if !hasValidReflection {
            return "Open Profile to create the reflection explicitly from the history you have built."
        }

        return "Keep adding listening notes whenever an album gives you something worth remembering."
    }

    private var appleMusicStatusTitle: String {
        switch authorizationState {
        case .notDetermined:
            return "Not connected"
        case .authorized:
            return "Apple Music connected"
        case .denied:
            return "Access denied"
        case .restricted:
            return "Access restricted"
        case .unavailable:
            return "Apple Music unavailable"
        }
    }

    private var appleMusicStatusDetail: String {
        switch authorizationState {
        case .notDetermined:
            return "Access is requested only after you choose Connect Apple Music."
        case .authorized:
            return "Recently played albums can appear when you start a log."
        case .denied:
            return "You can continue without access and change this later in Settings."
        case .restricted:
            return "This device does not currently allow Apple Music access. Logging is still available."
        case .unavailable:
            return "Apple Music features are not available here. Logging is still available."
        }
    }

    private var appleMusicStatusSymbol: String {
        switch authorizationState {
        case .authorized:
            return "checkmark.circle.fill"
        case .denied, .restricted:
            return "exclamationmark.circle"
        case .notDetermined, .unavailable:
            return "music.note"
        }
    }

    private func requestAppleMusicAuthorization() {
        guard !isRequestingAuthorization else {
            return
        }

        isRequestingAuthorization = true
        Task {
            authorizationState = await appleMusicAuthorizationService.requestAuthorization()
            isRequestingAuthorization = false
        }
    }

    private func refreshAuthorizationState() {
        authorizationState = appleMusicAuthorizationService.currentState
    }

    private func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else {
            return
        }
        step = previous
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case tasteLoop
    case appleMusic
    case journal
    case completion
}

private struct OnboardingLoopRow: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        ListendObjectCard {
            HStack(alignment: .top, spacing: ListendSpacing.md) {
                Text(String(number))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.listendAccent)
                    .frame(width: 28, height: 28)
                    .background(Color.listendAccentSoft, in: Circle())

                VStack(alignment: .leading, spacing: ListendSpacing.xs) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Introduction") {
    OnboardingView(isReplay: true) {}
        .modelContainer(for: ListendModelSchema.modelTypes, inMemory: true)
        .environment(SoundPrintProfileRefreshCoordinator())
}
