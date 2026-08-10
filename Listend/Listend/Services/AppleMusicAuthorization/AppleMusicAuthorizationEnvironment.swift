//
//  AppleMusicAuthorizationEnvironment.swift
//  Listend
//
//  Created by Codex on 8/7/26.
//

import SwiftUI

extension EnvironmentValues {
    @Entry var appleMusicAuthorizationService: AppleMusicAuthorizationServiceProtocol = UnavailableAppleMusicAuthorizationService()
}
