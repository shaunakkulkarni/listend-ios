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
    private let catalogService: AlbumCatalogServiceProtocol
    private let recentlyPlayedAlbumService: RecentlyPlayedAlbumServiceProtocol
    private let soundPrintProvider: SoundPrintProvider
    private let albumPreviewService: AlbumPreviewServiceProtocol

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
            Recommendation.self,
            RecommendationReceipt.self,
            RecommendationFeedback.self,
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
        soundPrintProvider = Self.makeSoundPrintProvider()
        albumPreviewService = Self.makeAlbumPreviewService()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                catalogService: catalogService,
                recentlyPlayedAlbumService: recentlyPlayedAlbumService
            )
                .environment(soundPrintRefreshCoordinator)
                .environment(\.soundPrintProvider, soundPrintProvider)
                .environment(\.albumPreviewService, albumPreviewService)
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

    private static func makeSoundPrintProvider() -> SoundPrintProvider {
        let arguments = ProcessInfo.processInfo.arguments

        if arguments.contains("-ui-testing") {
            return MockSoundPrintProvider()
        }

        #if targetEnvironment(simulator)
        return MockSoundPrintProvider()
        #else
        return FallbackSoundPrintProvider(
            primary: FoundationModelsSoundPrintProvider(),
            fallback: MockSoundPrintProvider()
        )
        #endif
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
