//
//  ShareIntakeTests.swift
//  ListendTests
//

import Testing
import Foundation
@testable import Listend

struct ShareIntakeTests {

    // MARK: - AppleMusicAlbumLinkParser

    @Test func parsesCanonicalAlbumURLWithSlugAndID() {
        let link = AppleMusicAlbumLinkParser.parse("https://music.apple.com/us/album/titanic-rising/1450602852")

        #expect(link?.albumID == "1450602852")
        #expect(link?.titleHint == "titanic rising")
        #expect(link?.storefront == "us")
    }

    @Test func parsesAlbumURLWithoutSlug() {
        let link = AppleMusicAlbumLinkParser.parse("https://music.apple.com/us/album/1450602852")

        #expect(link?.albumID == "1450602852")
        #expect(link?.titleHint == nil)
        #expect(link?.storefront == "us")
    }

    @Test func parsesAlbumIDFromSongShareLinkWithinAlbum() {
        let link = AppleMusicAlbumLinkParser.parse("https://music.apple.com/us/album/sos/1652177611?i=1652178990")

        #expect(link?.albumID == "1652177611")
        #expect(link?.titleHint == "sos")
    }

    @Test func parsesURLEmbeddedInSharedText() {
        let link = AppleMusicAlbumLinkParser.parse("Check this out! https://music.apple.com/us/album/blonde/1146195596 so good")

        #expect(link?.albumID == "1146195596")
        #expect(link?.titleHint == "blonde")
    }

    @Test func albumPathWithoutNumericIDYieldsTitleHintOnly() {
        let link = AppleMusicAlbumLinkParser.parse("https://music.apple.com/us/album/titanic-rising")

        #expect(link != nil)
        #expect(link?.albumID == nil)
        #expect(link?.titleHint == "titanic rising")
    }

    @Test func rejectsPlaylistURL() {
        let link = AppleMusicAlbumLinkParser.parse("https://music.apple.com/us/playlist/chill-mix/pl.u-123abc")

        #expect(link == nil)
    }

    @Test func rejectsArtistURL() {
        let link = AppleMusicAlbumLinkParser.parse("https://music.apple.com/us/artist/frank-ocean/442122051")

        #expect(link == nil)
    }

    @Test func rejectsNonCanonicalAppleHosts() {
        #expect(AppleMusicAlbumLinkParser.parse("https://geo.music.apple.com/us/album/blonde/1146195596") == nil)
        #expect(AppleMusicAlbumLinkParser.parse("https://itunes.apple.com/us/album/blonde/id1146195596") == nil)
    }

    @Test func rejectsNonAppleHost() {
        let link = AppleMusicAlbumLinkParser.parse("https://open.spotify.com/album/3mH6qwIy9crq0I9YQbOuDf")

        #expect(link == nil)
    }

    @Test func rejectsTextWithoutURL() {
        let link = AppleMusicAlbumLinkParser.parse("just some words about an album")

        #expect(link == nil)
    }

    @Test func rejectsEmptyInput() {
        #expect(AppleMusicAlbumLinkParser.parse("") == nil)
        #expect(AppleMusicAlbumLinkParser.parse("   \n ") == nil)
    }

    // MARK: - AppleMusicShareIntakeService

    @Test func resolvesCanonicalURLToCatalogAlbum() async {
        let album = AlbumSearchResult(
            id: "1652177611",
            title: "SOS",
            artistName: "SZA",
            releaseYear: 2022,
            genreName: "R&B/Soul"
        )
        let service = AppleMusicShareIntakeService(
            catalogService: StubAlbumCatalogService(albumsByID: [album.id: album])
        )

        let result = await service.resolve("https://music.apple.com/us/album/sos/1652177611")

        #expect(result == .resolved(album))
    }

    @Test func trimsSurroundingWhitespaceBeforeResolving() async {
        let album = AlbumSearchResult(
            id: "1146195596",
            title: "Blonde",
            artistName: "Frank Ocean",
            releaseYear: 2016,
            genreName: "Pop"
        )
        let service = AppleMusicShareIntakeService(
            catalogService: StubAlbumCatalogService(albumsByID: [album.id: album])
        )

        let result = await service.resolve("  https://music.apple.com/us/album/blonde/1146195596 \n")

        #expect(result == .resolved(album))
    }

    @Test func unknownAlbumIDFallsBackToTitleHintSearch() async {
        let service = AppleMusicShareIntakeService(
            catalogService: StubAlbumCatalogService()
        )

        let result = await service.resolve("https://music.apple.com/us/album/titanic-rising/1450602852")

        #expect(result == .needsManualSearch(suggestedQuery: "titanic rising"))
    }

    @Test func catalogErrorFallsBackToTitleHintSearchWithoutThrowing() async {
        let service = AppleMusicShareIntakeService(
            catalogService: StubAlbumCatalogService(error: StubCatalogError.unavailable)
        )

        let result = await service.resolve("https://music.apple.com/us/album/titanic-rising/1450602852")

        #expect(result == .needsManualSearch(suggestedQuery: "titanic rising"))
    }

    @Test func albumURLWithoutIDFallsBackToTitleHintWithoutCatalogLookup() async {
        let service = AppleMusicShareIntakeService(
            catalogService: StubAlbumCatalogService(error: StubCatalogError.unavailable)
        )

        let result = await service.resolve("https://music.apple.com/us/album/blonde")

        #expect(result == .needsManualSearch(suggestedQuery: "blonde"))
    }

    @Test func unparseableInputFallsBackToTrimmedRawInput() async {
        let service = AppleMusicShareIntakeService(
            catalogService: StubAlbumCatalogService()
        )

        let result = await service.resolve("  frank ocean blonde  ")

        #expect(result == .needsManualSearch(suggestedQuery: "frank ocean blonde"))
    }

    @Test func nonAppleURLFallsBackToTrimmedRawInput() async {
        let service = AppleMusicShareIntakeService(
            catalogService: StubAlbumCatalogService()
        )

        let result = await service.resolve("https://open.spotify.com/album/3mH6qwIy9crq0I9YQbOuDf")

        #expect(result == .needsManualSearch(suggestedQuery: "https://open.spotify.com/album/3mH6qwIy9crq0I9YQbOuDf"))
    }
}

// MARK: - Test doubles

private enum StubCatalogError: Error {
    case unavailable
}

private struct StubAlbumCatalogService: AlbumCatalogServiceProtocol {
    var albumsByID: [String: AlbumSearchResult] = [:]
    var resultsByQuery: [String: [AlbumSearchResult]] = [:]
    var error: Error?

    func searchAlbums(query: String) async throws -> [AlbumSearchResult] {
        if let error {
            throw error
        }

        return resultsByQuery[query] ?? []
    }

    func albumDetails(id: String) async throws -> AlbumSearchResult? {
        if let error {
            throw error
        }

        return albumsByID[id]
    }

    func appleMusicURL(for id: String) async throws -> URL? {
        if let error {
            throw error
        }

        return nil
    }
}
