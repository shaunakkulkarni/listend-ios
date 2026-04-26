//
//  MockAlbumCatalogService.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

import Foundation

struct MockAlbumCatalogService: AlbumCatalogServiceProtocol {
    private let albums: [AlbumSearchResult]

    init(albums: [AlbumSearchResult] = Self.defaultAlbums) {
        self.albums = albums
    }

    func searchAlbums(query: String) async throws -> [AlbumSearchResult] {
        let normalizedQuery = query.normalizedCatalogSearchText

        guard !normalizedQuery.isEmpty else {
            return []
        }

        return albums.filter { album in
            album.title.normalizedCatalogSearchText.contains(normalizedQuery)
                || album.artistName.normalizedCatalogSearchText.contains(normalizedQuery)
                || (album.genreName?.normalizedCatalogSearchText.contains(normalizedQuery) ?? false)
        }
    }

    func albumDetails(id: String) async throws -> AlbumSearchResult? {
        albums.first { $0.id == id }
    }
}

extension MockAlbumCatalogService {
    static let defaultAlbums: [AlbumSearchResult] = [
        AlbumSearchResult(
            id: "mock.big-thief.dragon-new-warm-mountain",
            title: "Dragon New Warm Mountain I Believe in You",
            artistName: "Big Thief",
            releaseYear: 2022,
            genreName: "Indie Folk"
        ),
        AlbumSearchResult(
            id: "mock.frank-ocean.blonde",
            title: "Blonde",
            artistName: "Frank Ocean",
            releaseYear: 2016,
            genreName: "Alternative R&B"
        ),
        AlbumSearchResult(
            id: "mock.madvillain.madvillainy",
            title: "Madvillainy",
            artistName: "Madvillain",
            releaseYear: 2004,
            genreName: "Hip-Hop"
        ),
        AlbumSearchResult(
            id: "mock.weyes-blood.titanic-rising",
            title: "Titanic Rising",
            artistName: "Weyes Blood",
            releaseYear: 2019,
            genreName: "Art Pop"
        ),
        AlbumSearchResult(
            id: "mock.sza.sos",
            title: "SOS",
            artistName: "SZA",
            releaseYear: 2022,
            genreName: "R&B"
        ),
        AlbumSearchResult(
            id: "mock.kendrick-lamar.good-kid-maad-city",
            title: "good kid, m.A.A.d city",
            artistName: "Kendrick Lamar",
            releaseYear: 2012,
            genreName: "Hip-Hop"
        ),
        AlbumSearchResult(
            id: "mock.mitski.laurel-hell",
            title: "Laurel Hell",
            artistName: "Mitski",
            releaseYear: 2022,
            genreName: "Indie Rock"
        ),
        AlbumSearchResult(
            id: "mock.radiohead.in-rainbows",
            title: "In Rainbows",
            artistName: "Radiohead",
            releaseYear: 2007,
            genreName: "Alternative Rock"
        ),
        AlbumSearchResult(
            id: "mock.bjork.homogenic",
            title: "Homogenic",
            artistName: "Bjork",
            releaseYear: 1997,
            genreName: "Electronic"
        ),
        AlbumSearchResult(
            id: "mock.fiona-apple.fetch-the-bolt-cutters",
            title: "Fetch the Bolt Cutters",
            artistName: "Fiona Apple",
            releaseYear: 2020,
            genreName: "Art Pop"
        ),
        AlbumSearchResult(
            id: "mock.turnstile.glow-on",
            title: "Glow On",
            artistName: "Turnstile",
            releaseYear: 2021,
            genreName: "Post-Hardcore"
        ),
        AlbumSearchResult(
            id: "mock.lcd-soundsystem.sound-of-silver",
            title: "Sound of Silver",
            artistName: "LCD Soundsystem",
            releaseYear: 2007,
            genreName: "Dance-Punk"
        )
    ]
}

private extension String {
    var normalizedCatalogSearchText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
