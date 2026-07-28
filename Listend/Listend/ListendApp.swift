//
//  ListendApp.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI
import SwiftData

@main
struct ListendApp: App {
    @State private var soundPrintRefreshCoordinator = SoundPrintProfileRefreshCoordinator()
    @AppStorage(SoundPrintPreferenceKey.preferAppleIntelligence) private var preferAppleIntelligence = true
    @AppStorage(SandboxPreferenceKey.intelligenceProvider) private var sandboxIntelligenceProviderRawValue = SandboxIntelligenceProvider.default.rawValue
    private let catalogService: AlbumCatalogServiceProtocol
    private let recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol
    private let albumPreviewService: AlbumPreviewServiceProtocol
    private let albumTrackService: AlbumTrackServiceProtocol
    private let appleMusicRecommendationService: AppleMusicRecommendationServiceProtocol?

    var sharedModelContainer: ModelContainer = {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing")
        let shouldResetUITestingData = arguments.contains("-reset-ui-testing-data")
        let schema = ListendModelSchema.schema
        let modelConfiguration: ModelConfiguration

        if isUITesting {
            let storeID = ProcessInfo.processInfo.environment["LISTEND_UI_TEST_STORE_ID"]
            let storeURL = uiTestingStoreURL(storeID: storeID)

            if shouldResetUITestingData {
                resetStore(at: storeURL)
                UserDefaults.standard.removeObject(forKey: TodayPickPreferenceKey.recommendationMode)
            }

            modelConfiguration = ModelConfiguration("ListendUITests", schema: schema, url: storeURL)
        } else {
            modelConfiguration = ListendSharedStore.productionConfiguration()
        }

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])

            if isUITesting,
               arguments.contains("-seed-today-pick-eligible"),
               try container.mainContext.fetchCount(FetchDescriptor<LogEntry>()) == 0 {
                for (index, result) in MockAlbumCatalogService.defaultAlbums.prefix(5).enumerated() {
                    let album = Album(
                        appleMusicID: result.catalogID,
                        title: result.title,
                        artistName: result.artistName,
                        releaseYear: result.releaseYear,
                        genreName: result.genreName
                    )
                    container.mainContext.insert(album)
                    container.mainContext.insert(LogEntry(album: album, rating: 3.0 + Double(index) * 0.5))
                }
                try container.mainContext.save()
            }

            if isUITesting,
               arguments.contains("-seed-reaction-existing-custom"),
               try container.mainContext.fetchCount(FetchDescriptor<LogEntry>()) == 0 {
                let album = Album(
                    appleMusicID: "mock.sza.sos",
                    title: "SOS",
                    artistName: "SZA",
                    releaseYear: 2022,
                    genreName: "R&B"
                )
                container.mainContext.insert(album)
                container.mainContext.insert(LogEntry(
                    album: album,
                    rating: 4,
                    reviewText: "The atmosphere kept pulling me back.",
                    tags: ["floaty"]
                ))
                try container.mainContext.save()
            }

            if SandboxMode.isEnabled {
                try SandboxDataSeeder.seedInitialDataIfNeeded(in: container.mainContext)
            }

            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        catalogService = Self.makeCatalogService()
        recentlyPlayedAlbumService = Self.makeRecentlyPlayedAlbumService()
        albumPreviewService = Self.makeAlbumPreviewService()
        albumTrackService = Self.makeAlbumTrackService()
        appleMusicRecommendationService = Self.makeAppleMusicRecommendationService()
    }

    var body: some Scene {
        let sandboxIntelligenceProvider = SandboxIntelligenceProvider(
            rawValue: Optional(sandboxIntelligenceProviderRawValue)
        )

        WindowGroup {
            ContentView(
                catalogService: catalogService,
                recentlyPlayedAlbumService: recentlyPlayedAlbumService,
                appleMusicRecommendationService: appleMusicRecommendationService
            )
                .environment(soundPrintRefreshCoordinator)
                .environment(\.soundPrintProvider, Self.makeSoundPrintProvider(
                    preferAppleIntelligence: SandboxMode.isEnabled && sandboxIntelligenceProvider == .onDevice
                        ? true
                        : preferAppleIntelligence,
                    sandboxIntelligenceProvider: sandboxIntelligenceProvider
                ))
                .environment(\.albumPreviewService, albumPreviewService)
                .environment(\.tagSuggestionProvider, Self.makeTagSuggestionProvider(
                    sandboxIntelligenceProvider: sandboxIntelligenceProvider
                ))
                .environment(\.journalAssistService, Self.makeJournalAssistService(
                    sandboxIntelligenceProvider: sandboxIntelligenceProvider
                ))
                .environment(\.reactionTagResolver, Self.makeReactionTagResolver(
                    preferAppleIntelligence: SandboxMode.isEnabled && sandboxIntelligenceProvider == .onDevice
                        ? true
                        : preferAppleIntelligence,
                    sandboxIntelligenceProvider: sandboxIntelligenceProvider
                ))
                .environment(\.albumTrackService, albumTrackService)
        }
        .modelContainer(sharedModelContainer)
    }

    private static func makeCatalogService() -> AlbumCatalogServiceProtocol {
        let arguments = ProcessInfo.processInfo.arguments

        if SandboxMode.isEnabled || arguments.contains("-ui-testing") {
            return MockAlbumCatalogService()
        }

        return FallbackAlbumCatalogService(primary: MusicKitAlbumCatalogService())
    }

    private static func makeRecentlyPlayedAlbumService() -> RecentlyPlayedAlbumServiceProtocol {
        let arguments = ProcessInfo.processInfo.arguments

        if SandboxMode.isEnabled || arguments.contains("-ui-testing") {
            return MockRecentlyPlayedAlbumService()
        }

        return MusicKitRecentlyPlayedAlbumService()
    }

    private static func makeAppleMusicRecommendationService() -> AppleMusicRecommendationServiceProtocol? {
        let arguments = ProcessInfo.processInfo.arguments

        if SandboxMode.isEnabled || arguments.contains("-ui-testing") {
            return nil
        }

        return AppleMusicRecommendationService()
    }

    private static func makeSoundPrintProvider(
        preferAppleIntelligence: Bool,
        sandboxIntelligenceProvider: SandboxIntelligenceProvider
    ) -> SoundPrintProvider {
        let arguments = ProcessInfo.processInfo.arguments

        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif

        return SoundPrintProviderFactory.makeProvider(
            preferAppleIntelligence: preferAppleIntelligence,
            isUITesting: arguments.contains("-ui-testing")
                || (SandboxMode.isEnabled && sandboxIntelligenceProvider == .mock),
            isSimulator: isSimulator
        )
    }

    private static func makeAlbumPreviewService() -> AlbumPreviewServiceProtocol {
        let arguments = ProcessInfo.processInfo.arguments

        if SandboxMode.isEnabled || arguments.contains("-ui-testing") {
            return MockAlbumPreviewService()
        }

        return FallbackAlbumPreviewService(
            primary: MusicKitAlbumPreviewService(),
            fallback: MockAlbumPreviewService()
        )
    }

    private static func makeTagSuggestionProvider(
        sandboxIntelligenceProvider: SandboxIntelligenceProvider
    ) -> TagSuggestionProvider {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-ui-testing")
            || (SandboxMode.isEnabled && sandboxIntelligenceProvider == .mock) {
            return MockTagSuggestionProvider()
        }

        #if targetEnvironment(simulator)
        return MockTagSuggestionProvider()
        #else
        return FallbackTagSuggestionProvider(
            primary: FoundationModelsTagSuggestionProvider(),
            fallback: LocalTagSuggestionProvider()
        )
        #endif
    }

    private static func makeJournalAssistService(
        sandboxIntelligenceProvider: SandboxIntelligenceProvider
    ) -> JournalAssistServiceProtocol {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-ui-testing")
            || (SandboxMode.isEnabled && sandboxIntelligenceProvider == .mock) {
            return MockJournalAssistService()
        }

        return FallbackJournalAssistService(
            primary: FoundationModelsJournalAssistService(),
            fallback: MockJournalAssistService()
        )
    }

    private static func makeReactionTagResolver(
        preferAppleIntelligence: Bool,
        sandboxIntelligenceProvider: SandboxIntelligenceProvider
    ) -> any ReactionTagResolving {
        let arguments = ProcessInfo.processInfo.arguments

        guard preferAppleIntelligence else {
            return LocalReactionTagResolutionProvider()
        }

        if arguments.contains("-ui-testing")
            || (SandboxMode.isEnabled && sandboxIntelligenceProvider == .mock) {
            return MockReactionTagResolver()
        }

        #if targetEnvironment(simulator)
        return MockReactionTagResolver()
        #else
        return FallbackReactionTagResolver(
            primary: FoundationModelsReactionTagResolver(),
            fallback: LocalReactionTagResolutionProvider()
        )
        #endif
    }

    private static func makeAlbumTrackService() -> AlbumTrackServiceProtocol {
        let arguments = ProcessInfo.processInfo.arguments

        if SandboxMode.isEnabled || arguments.contains("-ui-testing") {
            return MockAlbumTrackService()
        }

        return FallbackAlbumTrackService(
            primary: MusicKitAlbumTrackService(),
            fallback: EmptyAlbumTrackService()
        )
    }

    private static func uiTestingStoreURL(storeID: String?) -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sanitizedStoreID = storeID?
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }

        if let sanitizedStoreID, !sanitizedStoreID.isEmpty {
            return directory.appending(path: "ListendUITests-\(sanitizedStoreID).store")
        }

        return directory.appending(path: "ListendUITests.store")
    }

    private static func resetStore(at storeURL: URL) {
        let storeDirectoryURL = storeURL.deletingLastPathComponent()
        let storeFileName = storeURL.lastPathComponent
        let fileURLs = [
            storeURL,
            storeDirectoryURL.appending(path: "\(storeFileName)-shm"),
            storeDirectoryURL.appending(path: "\(storeFileName)-wal"),
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal")
        ]

        for fileURL in fileURLs {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
