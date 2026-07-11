//
//  AlbumPreviewServiceEnvironment.swift
//  Listend
//
//  Created by Codex on 5/5/26.
//

import SwiftUI

extension EnvironmentValues {
    @Entry var albumPreviewService: AlbumPreviewServiceProtocol = MockAlbumPreviewService()
}
