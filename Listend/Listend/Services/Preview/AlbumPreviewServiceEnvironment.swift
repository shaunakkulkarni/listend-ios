//
//  AlbumPreviewServiceEnvironment.swift
//  Listend
//
//  Created by Codex on 5/5/26.
//

import SwiftUI

private struct AlbumPreviewServiceEnvironmentKey: EnvironmentKey {
    static let defaultValue: AlbumPreviewServiceProtocol = MockAlbumPreviewService()
}

extension EnvironmentValues {
    var albumPreviewService: AlbumPreviewServiceProtocol {
        get { self[AlbumPreviewServiceEnvironmentKey.self] }
        set { self[AlbumPreviewServiceEnvironmentKey.self] = newValue }
    }
}
