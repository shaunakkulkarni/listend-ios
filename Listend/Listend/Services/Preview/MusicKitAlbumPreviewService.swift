//
//  MusicKitAlbumPreviewService.swift
//  Listend
//
//  Created by Codex on 5/5/26.
//

import Foundation

#if canImport(MusicKit)
import MusicKit
#endif

enum MusicKitAlbumPreviewError: Error, Equatable {
    case unavailable
    case unauthorized
}

struct MusicKitPreviewTrackMetadata: Equatable {
    let title: String
    let previewAssetURLs: [URL]
}

struct MusicKitAlbumPreviewMapper {
    nonisolated static func preview(
        albumCatalogID: String,
        tracks: [MusicKitPreviewTrackMetadata]
    ) -> AlbumPreview? {
        let trimmedAlbumCatalogID = albumCatalogID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAlbumCatalogID.isEmpty else {
            return nil
        }

        for track in tracks {
            let trimmedTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedTitle.isEmpty else {
                continue
            }

            if let previewURL = track.previewAssetURLs.first(where: Self.isValidPreviewURL) {
                return AlbumPreview(
                    albumCatalogID: trimmedAlbumCatalogID,
                    trackTitle: trimmedTitle,
                    previewURL: previewURL
                )
            }
        }

        return nil
    }

    private nonisolated static func isValidPreviewURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            return false
        }

        return url.host?.isEmpty == false
    }
}

#if canImport(MusicKit)
struct MusicKitAlbumPreviewService: AlbumPreviewServiceProtocol {
    func preview(for lookup: AlbumPreviewLookup) async throws -> AlbumPreview? {
        guard let albumCatalogID = lookup.albumCatalogID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !albumCatalogID.isEmpty
        else {
            return nil
        }

        try await ensureAuthorized()

        let request = MusicCatalogResourceRequest<MusicKit.Album>(
            matching: \.id,
            equalTo: MusicItemID(albumCatalogID)
        )
        let response = try await request.response()
        try Task.checkCancellation()

        guard let album = response.items.first else {
            return nil
        }

        let albumWithTracks = try await album.with(.tracks)
        try Task.checkCancellation()

        let tracks = albumWithTracks.tracks?.map(Self.trackMetadata) ?? []
        return MusicKitAlbumPreviewMapper.preview(
            albumCatalogID: albumCatalogID,
            tracks: tracks
        )
    }

    private func ensureAuthorized() async throws {
        switch MusicAuthorization.currentStatus {
        case .authorized:
            return
        case .notDetermined:
            let status = await MusicAuthorization.request()

            guard status == .authorized else {
                throw MusicKitAlbumPreviewError.unauthorized
            }
        case .denied, .restricted:
            throw MusicKitAlbumPreviewError.unauthorized
        @unknown default:
            throw MusicKitAlbumPreviewError.unavailable
        }
    }

    private static func trackMetadata(from track: MusicKit.Track) -> MusicKitPreviewTrackMetadata {
        MusicKitPreviewTrackMetadata(
            title: track.title,
            previewAssetURLs: track.previewAssets?.compactMap(\.url) ?? []
        )
    }
}
#else
struct MusicKitAlbumPreviewService: AlbumPreviewServiceProtocol {
    func preview(for lookup: AlbumPreviewLookup) async throws -> AlbumPreview? {
        throw MusicKitAlbumPreviewError.unavailable
    }
}
#endif
