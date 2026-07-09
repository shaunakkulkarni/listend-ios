//
//  SharedAlbumIntakeTests.swift
//  ListendTests
//

import Testing
import Foundation
@testable import Listend

struct SharedAlbumIntakeTests {

    // MARK: - SharedAlbumDeepLink

    @Test func recognizesSharedAlbumURL() {
        #expect(SharedAlbumDeepLink.isSharedAlbumURL(URL(string: "listend://shared-album")!))
        #expect(SharedAlbumDeepLink.isSharedAlbumURL(URL(string: "listend://shared-album?foo=bar")!))
    }

    @Test func rejectsWrongHost() {
        #expect(!SharedAlbumDeepLink.isSharedAlbumURL(URL(string: "listend://something-else")!))
    }

    @Test func rejectsWrongScheme() {
        #expect(!SharedAlbumDeepLink.isSharedAlbumURL(URL(string: "https://shared-album")!))
        #expect(!SharedAlbumDeepLink.isSharedAlbumURL(URL(string: "https://music.apple.com/us/album/blonde/1146195596")!))
    }

    // MARK: - PendingSharedAlbumStore

    @Test func savesThenConsumesReturnsValueOnce() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save("https://music.apple.com/us/album/sos/1652177611")

        #expect(store.consume() == "https://music.apple.com/us/album/sos/1652177611")
        // Second read must be empty: the payload is consumed exactly once so it
        // never re-opens on relaunch.
        #expect(store.consume() == nil)
    }

    @Test func consumeReturnsNilWhenEmpty() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.consume() == nil)
    }

    @Test func saveTrimsWhitespaceAndIgnoresBlank() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save("   ")
        #expect(store.consume() == nil)

        store.save("  https://music.apple.com/us/album/blonde/1146195596 \n")
        #expect(store.consume() == "https://music.apple.com/us/album/blonde/1146195596")
    }

    @Test func clearRemovesPendingPayload() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.save("https://music.apple.com/us/album/sos/1652177611")
        store.clear()

        #expect(store.consume() == nil)
    }

    // MARK: - Helpers

    private func makeStore() -> (PendingSharedAlbumStore, UserDefaults, String) {
        let suite = "test.sharedalbum.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (PendingSharedAlbumStore(defaults: defaults), defaults, suite)
    }
}
