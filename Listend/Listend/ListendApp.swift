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
    private let catalogService: AlbumCatalogServiceProtocol
    private let recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol
    private let albumPreviewService: AlbumPreviewServiceProtocol
    private let tagSuggestionProvider: TagSuggestionProvider
    private let journalAssistService: JournalAssistServiceProtocol
    private let albumTrackService: AlbumTrackServiceProtocol
    private let appleMusicRecommendationService: AppleMusicRecommendationServiceProtocol?

    var sharedModelContainer: ModelContainer = {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing")
        let shouldResetUITestingData = arguments.contains("-reset-ui-testing-data")
        let schema = Schema([
            Album.self,
            LogEntry.self,
            TasteDimension.self,
            TasteEvidence.self,
            SoundPrintPersona.self,
            TasteAvoidanceSignal.self,
            Recommendation.self,
            RecommendationReceipt.self,
            RecommendationFeedback.self,
            RecentlyPlayedAlbumSnapshot.self,
            AppleMusicRecentPlaySnapshot.self,
            AlbumTrack.self,
        ])
        let modelConfiguration: ModelConfiguration

        if isUITesting {
            let storeID = ProcessInfo.processInfo.environment["LISTEND_UI_TEST_STORE_ID"]
            let storeURL = uiTestingStoreURL(storeID: storeID)

            if shouldResetUITestingData {
                resetStore(at: storeURL)
            }

            modelConfiguration = ModelConfiguration("ListendUITests", schema: schema, url: storeURL)
        } else {
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        catalogService = Self.makeCatalogService()
        recentlyPlayedAlbumService = Self.makeRecentlyPlayedAlbumService()
        albumPreviewService = Self.makeAlbumPreviewService()
        tagSuggestionProvider = Self.makeTagSuggestionProvider()
        journalAssistService = Self.makeJournalAssistService()
        albumTrackService = Self.makeAlbumTrackService()
        appleMusicRecommendationService = Self.makeAppleMusicRecommendationService()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                catalogService: catalogService,
                recentlyPlayedAlbumService: recentlyPlayedAlbumService,
                appleMusicRecommendationService: appleMusicRecommendationService
            )
                .environment(soundPrintRefreshCoordinator)
                .environment(\.soundPrintProvider, Self.makeSoundPrintProvider(preferAppleIntelligence: preferAppleIntelligence))
                .environment(\.albumPreviewService, albumPreviewService)
                .environment(\.tagSuggestionProvider, tagSuggestionProvider)
                .environment(\.journalAssistService, journalAssistService)
                .environment(\.albumTrackService, albumTrackService)
        }
        .modelContainer(sharedModelContainer)
    }

    private static func makeCatalogService() -> AlbumCatalogServiceProtocol {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-ui-testing") {
            return MockAlbumCatalogService()
        }

        return FallbackAlbumCatalogService(primary: MusicKitAlbumCatalogService())
    }

    private static func makeRecentlyPlayedAlbumService() -> RecentlyPlayedAlbumServiceProtocol {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-ui-testing") {
            return MockRecentlyPlayedAlbumService()
        }

        return MusicKitRecentlyPlayedAlbumService()
    }

    private static func makeAppleMusicRecommendationService() -> AppleMusicRecommendationServiceProtocol? {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-ui-testing") {
            return nil
        }

        return AppleMusicRecommendationService()
    }

    private static func makeSoundPrintProvider(preferAppleIntelligence: Bool) -> SoundPrintProvider {
        let arguments = ProcessInfo.processInfo.arguments

        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif

        return SoundPrintProviderFactory.makeProvider(
            preferAppleIntelligence: preferAppleIntelligence,
            isUITesting: arguments.contains("-ui-testing"),
            isSimulator: isSimulator
        )
    }

    private static func makeAlbumPreviewService() -> AlbumPreviewServiceProtocol {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-ui-testing") {
            return MockAlbumPreviewService()
        }

        return FallbackAlbumPreviewService(
            primary: MusicKitAlbumPreviewService(),
            fallback: MockAlbumPreviewService()
        )
    }

    private static func makeTagSuggestionProvider() -> TagSuggestionProvider {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-ui-testing") {
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

    private static func makeJournalAssistService() -> JournalAssistServiceProtocol {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-ui-testing") {
            return MockJournalAssistService()
        }

        return FallbackJournalAssistService(
            primary: FoundationModelsJournalAssistService(),
            fallback: MockJournalAssistService()
        )
    }

    private static func makeAlbumTrackService() -> AlbumTrackServiceProtocol {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-ui-testing") {
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
