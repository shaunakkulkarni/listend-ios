//
//  FallbackAlbumPreviewService.swift
//  Listend
//
//  Created by Codex on 5/5/26.
//

struct FallbackAlbumPreviewService: AlbumPreviewServiceProtocol {
    private let primary: AlbumPreviewServiceProtocol
    private let fallback: AlbumPreviewServiceProtocol

    init(
        primary: AlbumPreviewServiceProtocol,
        fallback: AlbumPreviewServiceProtocol = MockAlbumPreviewService()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func preview(for lookup: AlbumPreviewLookup) async throws -> AlbumPreview? {
        do {
            if let preview = try await primary.preview(for: lookup) {
                return preview
            }

            return try await fallback.preview(for: lookup)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.preview(for: lookup)
        }
    }
}
