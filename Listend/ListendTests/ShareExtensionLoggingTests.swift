//
//  ShareExtensionLoggingTests.swift
//  ListendTests
//

import Foundation
import SwiftData
import Testing
@testable import Listend

@MainActor
struct ShareExtensionLoggingTests {

    @Test func migrationCopiesDefaultStoreFilesIntoSharedStoreOnce() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ListendStoreMigration-\(UUID().uuidString)")
        let defaultURL = root.appending(path: "Default/Listend.store")
        let sharedURL = root.appending(path: "Shared/Listend.store")
        try FileManager.default.createDirectory(at: defaultURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        try Data("store".utf8).write(to: defaultURL)
        try Data("wal".utf8).write(to: defaultURL.appendingPathExtension("wal"))
        try Data("shm".utf8).write(to: defaultURL.appendingPathExtension("shm"))

        try ListendSharedStoreMigrator.copyDefaultStoreIfNeeded(
            defaultStoreURL: defaultURL,
            sharedStoreURL: sharedURL
        )

        #expect(try Data(contentsOf: sharedURL) == Data("store".utf8))
        #expect(try Data(contentsOf: sharedURL.appendingPathExtension("wal")) == Data("wal".utf8))
        #expect(try Data(contentsOf: sharedURL.appendingPathExtension("shm")) == Data("shm".utf8))

        try Data("existing".utf8).write(to: sharedURL)
        try Data("new default".utf8).write(to: defaultURL)

        try ListendSharedStoreMigrator.copyDefaultStoreIfNeeded(
            defaultStoreURL: defaultURL,
            sharedStoreURL: sharedURL
        )

        #expect(try Data(contentsOf: sharedURL) == Data("existing".utf8))
        try? FileManager.default.removeItem(at: root)
    }

    @Test func shareExtensionSaveResolvedAlbumCreatesTrimmedLogAndDedupesAlbum() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let existingAlbum = Album(
            appleMusicID: "music.blonde",
            title: "Old Blonde",
            artistName: "Frank Ocean"
        )
        context.insert(existingAlbum)
        try context.save()

        let savedLog = try ShareExtensionLogSaver.save(
            ShareExtensionLogDraft(
                album: .resolved(
                    AlbumSearchResult(
                        id: "music.blonde",
                        title: "Blonde",
                        artistName: "Frank Ocean",
                        releaseYear: 2016,
                        genreName: "Pop",
                        artworkURL: "https://example.com/blonde.jpg"
                    )
                ),
                rating: 4.5,
                reviewText: "  sparse and glowing  ",
                tagsText: " late night, repeat ",
                favoriteTracksText: "Nikes, Ivy",
                skipTracksText: " ",
                standoutMomentText: "  final run  "
            ),
            in: context
        )

        let albums = try context.fetch(FetchDescriptor<Album>())
        let logs = try context.fetch(FetchDescriptor<LogEntry>())

        #expect(albums.count == 1)
        #expect(savedLog.album?.id == existingAlbum.id)
        #expect(savedLog.rating == 4.5)
        #expect(savedLog.reviewText == "sparse and glowing")
        #expect(savedLog.tags == ["late night", "repeat"])
        #expect(savedLog.favoriteTracks == ["Nikes", "Ivy"])
        #expect(savedLog.skipTracks.isEmpty)
        #expect(savedLog.normalizedStandoutMoment == "final run")
        #expect(logs.count == 1)
    }

    @Test func shareExtensionSaveManualAlbumDoesNotRequireMusicKit() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let savedLog = try ShareExtensionLogSaver.save(
            ShareExtensionLogDraft(
                album: .manual(
                    title: "  Titanic Rising ",
                    artistName: " Weyes Blood ",
                    releaseYear: 2019,
                    genreName: "Alternative"
                ),
                rating: 5.0,
                reviewText: "  huge and patient  ",
                tagsText: "",
                favoriteTracksText: "",
                skipTracksText: "",
                standoutMomentText: ""
            ),
            in: context
        )

        #expect(savedLog.album?.title == "Titanic Rising")
        #expect(savedLog.album?.artistName == "Weyes Blood")
        #expect(savedLog.album?.releaseYear == 2019)
        #expect(savedLog.album?.genreName == "Alternative")
        #expect(savedLog.rating == 5.0)
        #expect(savedLog.reviewText == "huge and patient")
    }

    @Test func shareExtensionDeterministicReactionParityPersistsCompatibleValues() throws {
        let catalog = TaxonomyCatalogLoader.shared
        let searchEngine = ReactionBrowserSearchEngine(catalog: catalog)
        var selection = ReactionSelectionState()

        guard case .canonical(let hype) = searchEngine.presentation(for: "hype").exactMatch else {
            Issue.record("Expected the canonical reaction.")
            return
        }
        selection.toggleCanonical(hype)
        #expect(selection.persistedDisplayValues == ["hype"])
        selection.toggleCanonical(hype)
        #expect(selection.persistedDisplayValues.isEmpty)

        guard case .alias(let alias, let aliasTag) = searchEngine.presentation(for: "turnt").exactMatch else {
            Issue.record("Expected the exact local alias.")
            return
        }
        #expect(alias == "turnt")
        #expect(aliasTag.id == hype.id)
        selection.addCanonical(aliasTag)

        guard case .ambiguous(let ambiguousAlias, let candidates) =
            searchEngine.presentation(for: "floaty").exactMatch else {
            Issue.record("Expected the declared ambiguous alias.")
            return
        }
        #expect(ambiguousAlias.term == "floaty")
        #expect(candidates.map(\.id) == ["mood.dreamy", "mood.ethereal", "sonic.airy"])
        selection.addCanonical(try #require(candidates.first))

        let customPresentation = searchEngine.presentation(for: "  graduation   summer ")
        #expect(customPresentation.exactMatch == nil)
        #expect(customPresentation.customDisplayValue == "graduation summer")
        #expect(selection.addCustom("  graduation   summer ") == .valid(displayValue: "graduation summer"))
        #expect(selection.persistedDisplayValues == ["hype", "dreamy", "graduation summer"])

        let restoredAliasShapedCustom = ReactionSelectionState(
            persistedDisplayValues: ["floaty"],
            catalog: catalog
        )
        #expect(restoredAliasShapedCustom.persistedDisplayValues == ["floaty"])
        #expect(restoredAliasShapedCustom.selections.first?.isCustom == true)

        let container = try makeInMemoryContainer()
        let savedLog = try ShareExtensionLogSaver.save(
            ShareExtensionLogDraft(
                album: .manual(
                    title: "Dummy",
                    artistName: "Test Artist",
                    releaseYear: nil,
                    genreName: nil
                ),
                rating: 4.0,
                reviewText: "",
                tagsText: selection.persistedDisplayValues.joined(separator: ", "),
                favoriteTracksText: "",
                skipTracksText: "",
                standoutMomentText: ""
            ),
            in: container.mainContext
        )

        #expect(savedLog.tags == ["hype", "dreamy", "graduation summer"])
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        let schema = ListendModelSchema.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
