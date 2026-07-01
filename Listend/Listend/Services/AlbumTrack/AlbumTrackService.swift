//
//  AlbumTrackService.swift
//  Listend
//
//  Created by Codex on 6/30/26.
//

import Foundation
import SwiftData

#if canImport(MusicKit)
import MusicKit
#endif

protocol AlbumTrackServiceProtocol {
    @MainActor
    func tracks(for album: Album, in modelContext: ModelContext) async throws -> [AlbumTrackCandidate]
}

struct AlbumTrackCandidate: Identifiable, Equatable {
    let id: String
    let albumAppleMusicID: String
    let appleMusicTrackID: String?
    let title: String
    let artistName: String?
    let trackNumber: Int?
    let discNumber: Int?
    let durationMilliseconds: Int?
    let previewURL: String?
    let returnedOrder: Int

    init(
        albumAppleMusicID: String,
        appleMusicTrackID: String? = nil,
        title: String,
        artistName: String? = nil,
        trackNumber: Int? = nil,
        discNumber: Int? = nil,
        durationMilliseconds: Int? = nil,
        previewURL: String? = nil,
        returnedOrder: Int = 0
    ) {
        self.albumAppleMusicID = albumAppleMusicID
        self.appleMusicTrackID = appleMusicTrackID
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.artistName = artistName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.durationMilliseconds = durationMilliseconds
        self.previewURL = previewURL
        self.returnedOrder = returnedOrder

        let key = appleMusicTrackID ?? "\(albumAppleMusicID)-\(returnedOrder)-\(self.title)"
        id = key.isEmpty ? UUID().uuidString : key
    }

    init(track: AlbumTrack) {
        self.init(
            albumAppleMusicID: track.albumAppleMusicID,
            appleMusicTrackID: track.appleMusicTrackID,
            title: track.title,
            artistName: track.artistName,
            trackNumber: track.trackNumber,
            discNumber: track.discNumber,
            durationMilliseconds: track.durationMilliseconds,
            previewURL: track.previewURL,
            returnedOrder: track.returnedOrder
        )
    }

    var selectionKey: String {
        title.normalizedAlbumTrackSelectionText
    }

    var accessibilityID: String {
        selectionKey
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" {
                    result.append(character)
                }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

extension Array where Element == AlbumTrackCandidate {
    func sortedForAlbumDisplay() -> [AlbumTrackCandidate] {
        enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element
                let right = rhs.element
                let leftDisc = left.discNumber ?? Int.max
                let rightDisc = right.discNumber ?? Int.max

                if leftDisc != rightDisc {
                    return leftDisc < rightDisc
                }

                let leftTrack = left.trackNumber ?? Int.max
                let rightTrack = right.trackNumber ?? Int.max

                if leftTrack != rightTrack {
                    return leftTrack < rightTrack
                }

                if left.returnedOrder != right.returnedOrder {
                    return left.returnedOrder < right.returnedOrder
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

struct AlbumTrackSelectionState: Equatable {
    private(set) var favoriteTrackKeys: Set<String> = []
    private(set) var skipTrackKeys: Set<String> = []

    mutating func toggleFavorite(_ track: AlbumTrackCandidate) {
        let key = track.selectionKey

        if favoriteTrackKeys.contains(key) {
            favoriteTrackKeys.remove(key)
        } else {
            favoriteTrackKeys.insert(key)
            skipTrackKeys.remove(key)
        }
    }

    mutating func toggleSkip(_ track: AlbumTrackCandidate) {
        let key = track.selectionKey

        if skipTrackKeys.contains(key) {
            skipTrackKeys.remove(key)
        } else {
            skipTrackKeys.insert(key)
            favoriteTrackKeys.remove(key)
        }
    }

    mutating func applySavedTracks(favorites: [String], skips: [String], candidates: [AlbumTrackCandidate]) -> (favoriteManual: [String], skipManual: [String]) {
        let candidateKeys = Set(candidates.map(\.selectionKey))
        favoriteTrackKeys = Set(favorites.map(\.normalizedAlbumTrackSelectionText)).intersection(candidateKeys)
        skipTrackKeys = Set(skips.map(\.normalizedAlbumTrackSelectionText)).intersection(candidateKeys)
        favoriteTrackKeys.subtract(skipTrackKeys)

        return (
            favoriteManual: favorites.filter { !candidateKeys.contains($0.normalizedAlbumTrackSelectionText) },
            skipManual: skips.filter { !candidateKeys.contains($0.normalizedAlbumTrackSelectionText) }
        )
    }

    func isFavorite(_ track: AlbumTrackCandidate) -> Bool {
        favoriteTrackKeys.contains(track.selectionKey)
    }

    func isSkip(_ track: AlbumTrackCandidate) -> Bool {
        skipTrackKeys.contains(track.selectionKey)
    }

    func savedFavoriteTrackTitles(from candidates: [AlbumTrackCandidate], manualText: String) -> [String] {
        savedTrackTitles(from: candidates, selectedKeys: favoriteTrackKeys, manualText: manualText)
    }

    func savedSkipTrackTitles(from candidates: [AlbumTrackCandidate], manualText: String) -> [String] {
        savedTrackTitles(from: candidates, selectedKeys: skipTrackKeys, manualText: manualText)
    }

    private func savedTrackTitles(from candidates: [AlbumTrackCandidate], selectedKeys: Set<String>, manualText: String) -> [String] {
        let selectedTitles = candidates
            .sortedForAlbumDisplay()
            .filter { selectedKeys.contains($0.selectionKey) }
            .map(\.title)

        return ListTextNormalizer.normalizedTrackNames(selectedTitles + ListTextNormalizer.parsedTrackNames(from: manualText))
    }
}

enum AlbumTrackCache {
    static let freshnessInterval: TimeInterval = 30 * 24 * 60 * 60

    @MainActor
    static func cachedTracks(
        albumAppleMusicID: String,
        in modelContext: ModelContext,
        now: Date = Date()
    ) throws -> [AlbumTrackCandidate]? {
        let trimmedID = albumAppleMusicID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            return nil
        }

        let descriptor = FetchDescriptor<AlbumTrack>(
            predicate: #Predicate { track in
                track.albumAppleMusicID == trimmedID
            }
        )
        let tracks = try modelContext.fetch(descriptor)

        guard !tracks.isEmpty,
              tracks.allSatisfy({ now.timeIntervalSince($0.cachedAt) <= freshnessInterval }) else {
            return nil
        }

        return tracks.map(AlbumTrackCandidate.init).sortedForAlbumDisplay()
    }

    @MainActor
    static func replaceCachedTracks(
        _ tracks: [AlbumTrackCandidate],
        albumAppleMusicID: String,
        in modelContext: ModelContext,
        now: Date = Date()
    ) throws {
        let trimmedID = albumAppleMusicID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            return
        }

        let descriptor = FetchDescriptor<AlbumTrack>(
            predicate: #Predicate { track in
                track.albumAppleMusicID == trimmedID
            }
        )
        try modelContext.fetch(descriptor).forEach(modelContext.delete)

        for track in tracks.sortedForAlbumDisplay() where !track.title.isEmpty {
            modelContext.insert(
                AlbumTrack(
                    albumAppleMusicID: trimmedID,
                    appleMusicTrackID: track.appleMusicTrackID,
                    title: track.title,
                    artistName: track.artistName,
                    trackNumber: track.trackNumber,
                    discNumber: track.discNumber,
                    durationMilliseconds: track.durationMilliseconds,
                    previewURL: track.previewURL,
                    returnedOrder: track.returnedOrder,
                    cachedAt: now
                )
            )
        }

        try modelContext.save()
    }
}

struct FallbackAlbumTrackService: AlbumTrackServiceProtocol {
    private let primary: AlbumTrackServiceProtocol
    private let fallback: AlbumTrackServiceProtocol

    init(primary: AlbumTrackServiceProtocol, fallback: AlbumTrackServiceProtocol = EmptyAlbumTrackService()) {
        self.primary = primary
        self.fallback = fallback
    }

    @MainActor
    func tracks(for album: Album, in modelContext: ModelContext) async throws -> [AlbumTrackCandidate] {
        guard let albumAppleMusicID = album.appleMusicID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !albumAppleMusicID.isEmpty else {
            return []
        }

        if let cachedTracks = try? AlbumTrackCache.cachedTracks(albumAppleMusicID: albumAppleMusicID, in: modelContext),
           !cachedTracks.isEmpty {
            return cachedTracks
        }

        do {
            let tracks = try await primary.tracks(for: album, in: modelContext).sortedForAlbumDisplay()
            guard !tracks.isEmpty else {
                return try await fallback.tracks(for: album, in: modelContext)
            }

            try? AlbumTrackCache.replaceCachedTracks(tracks, albumAppleMusicID: albumAppleMusicID, in: modelContext)
            return tracks
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.tracks(for: album, in: modelContext)
        }
    }
}

struct EmptyAlbumTrackService: AlbumTrackServiceProtocol {
    @MainActor
    func tracks(for album: Album, in modelContext: ModelContext) async throws -> [AlbumTrackCandidate] {
        []
    }
}

struct MockAlbumTrackService: AlbumTrackServiceProtocol {
    private let tracksByAlbumID: [String: [AlbumTrackCandidate]]

    init(tracksByAlbumID: [String: [AlbumTrackCandidate]] = Self.defaultTracksByAlbumID) {
        self.tracksByAlbumID = tracksByAlbumID
    }

    @MainActor
    func tracks(for album: Album, in modelContext: ModelContext) async throws -> [AlbumTrackCandidate] {
        guard let albumAppleMusicID = album.appleMusicID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !albumAppleMusicID.isEmpty else {
            return []
        }

        return (tracksByAlbumID[albumAppleMusicID] ?? []).sortedForAlbumDisplay()
    }
}

extension MockAlbumTrackService {
    static let defaultTracksByAlbumID: [String: [AlbumTrackCandidate]] = [
        "mock.sza.sos": [
            AlbumTrackCandidate(albumAppleMusicID: "mock.sza.sos", appleMusicTrackID: "mock.sza.sos.1", title: "SOS", artistName: "SZA", trackNumber: 1, discNumber: 1, returnedOrder: 1),
            AlbumTrackCandidate(albumAppleMusicID: "mock.sza.sos", appleMusicTrackID: "mock.sza.sos.2", title: "Kill Bill", artistName: "SZA", trackNumber: 2, discNumber: 1, returnedOrder: 2),
            AlbumTrackCandidate(albumAppleMusicID: "mock.sza.sos", appleMusicTrackID: "mock.sza.sos.8", title: "Snooze", artistName: "SZA", trackNumber: 8, discNumber: 1, returnedOrder: 8),
            AlbumTrackCandidate(albumAppleMusicID: "mock.sza.sos", appleMusicTrackID: "mock.sza.sos.23", title: "Good Days", artistName: "SZA", trackNumber: 23, discNumber: 1, returnedOrder: 23)
        ]
    ]
}

enum MusicKitAlbumTrackError: Error, Equatable {
    case unavailable
    case unauthorized
    case unusableResponse
}

#if canImport(MusicKit)
struct MusicKitAlbumTrackService: AlbumTrackServiceProtocol {
    @MainActor
    func tracks(for album: Album, in modelContext: ModelContext) async throws -> [AlbumTrackCandidate] {
        guard let albumAppleMusicID = album.appleMusicID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !albumAppleMusicID.isEmpty else {
            return []
        }

        try await ensureAuthorized()

        let request = MusicCatalogResourceRequest<MusicKit.Album>(matching: \.id, equalTo: MusicItemID(albumAppleMusicID))
        let response = try await request.response()
        try Task.checkCancellation()

        guard let musicAlbum = response.items.first else {
            throw MusicKitAlbumTrackError.unusableResponse
        }

        let detailedAlbum = try await musicAlbum.with([.tracks])
        let tracks = (detailedAlbum.tracks ?? []).enumerated().compactMap { offset, track -> AlbumTrackCandidate? in
            switch track {
            case .song(let song):
                return AlbumTrackCandidate(
                    albumAppleMusicID: albumAppleMusicID,
                    appleMusicTrackID: song.id.rawValue,
                    title: song.title,
                    artistName: song.artistName,
                    trackNumber: song.trackNumber,
                    discNumber: song.discNumber,
                    durationMilliseconds: song.duration.map { Int($0 * 1000) },
                    previewURL: song.previewAssets?.first?.url?.absoluteString,
                    returnedOrder: offset
                )
            default:
                return nil
            }
        }

        guard !tracks.isEmpty else {
            throw MusicKitAlbumTrackError.unusableResponse
        }

        return tracks.sortedForAlbumDisplay()
    }

    private func ensureAuthorized() async throws {
        switch MusicAuthorization.currentStatus {
        case .authorized:
            return
        case .notDetermined:
            let status = await MusicAuthorization.request()

            guard status == .authorized else {
                throw MusicKitAlbumTrackError.unauthorized
            }
        case .denied, .restricted:
            throw MusicKitAlbumTrackError.unauthorized
        @unknown default:
            throw MusicKitAlbumTrackError.unavailable
        }
    }
}
#else
struct MusicKitAlbumTrackService: AlbumTrackServiceProtocol {
    @MainActor
    func tracks(for album: Album, in modelContext: ModelContext) async throws -> [AlbumTrackCandidate] {
        throw MusicKitAlbumTrackError.unavailable
    }
}
#endif

private extension String {
    var normalizedAlbumTrackSelectionText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
