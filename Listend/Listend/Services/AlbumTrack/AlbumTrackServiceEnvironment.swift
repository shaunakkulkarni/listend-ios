//
//  AlbumTrackServiceEnvironment.swift
//  Listend
//
//  Created by Codex on 6/30/26.
//

import SwiftUI

extension EnvironmentValues {
    @Entry var albumTrackService: AlbumTrackServiceProtocol = EmptyAlbumTrackService()
}
