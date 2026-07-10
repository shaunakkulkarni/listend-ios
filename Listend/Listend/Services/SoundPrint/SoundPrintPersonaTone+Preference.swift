//
//  SoundPrintPersonaTone+Preference.swift
//  Listend
//

import Foundation

extension SoundPrintPersonaTone {
    /// The tone currently selected in Settings. Read at profile-rebuild time so a
    /// tone change takes effect on the next regeneration without reconstructing
    /// the app-scoped provider.
    static var current: SoundPrintPersonaTone {
        SoundPrintPersonaTone(rawValue: UserDefaults.standard.string(forKey: SoundPrintPreferenceKey.personaTone))
    }
}
