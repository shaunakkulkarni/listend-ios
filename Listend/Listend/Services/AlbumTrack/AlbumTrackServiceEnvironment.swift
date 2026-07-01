//
//  AlbumTrackServiceEnvironment.swift
//  Listend
//
//  Created by Codex on 6/30/26.
//

import SwiftUI

private struct AlbumTrackServiceEnvironmentKey: EnvironmentKey {
    static let defaultValue: AlbumTrackServiceProtocol = EmptyAlbumTrackService()
}

extension EnvironmentValues {
    var albumTrackService: AlbumTrackServiceProtocol {
        get { self[AlbumTrackServiceEnvironmentKey.self] }
        set { self[AlbumTrackServiceEnvironmentKey.self] = newValue }
    }
}
