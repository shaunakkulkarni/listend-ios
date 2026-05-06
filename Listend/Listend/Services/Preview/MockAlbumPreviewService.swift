//
//  MockAlbumPreviewService.swift
//  Listend
//
//  Created by Codex on 5/5/26.
//

struct MockAlbumPreviewService: AlbumPreviewServiceProtocol {
    func preview(for lookup: AlbumPreviewLookup) async throws -> AlbumPreview? {
        nil
    }
}
