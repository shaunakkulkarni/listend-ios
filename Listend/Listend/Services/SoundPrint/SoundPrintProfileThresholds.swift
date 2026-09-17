//
//  SoundPrintProfileThresholds.swift
//  Listend
//
//  Centralized log-count gates for SoundPrint's dynamic states, so the same numbers
//  drive both profile-building logic and the UI copy/sections that depend on them.
//

enum SoundPrintProfileThresholds {
    /// Persona and compact summary generation both gate on this — see plan decision 8:
    /// they're independent steps sharing one threshold, not staggered.
    static let personaMinimumLogCount = 5

    /// A current SoundPrint Reflection becomes eligible for an explicit update after
    /// this many additional saved logs.
    static let reflectionRefreshLogIncrement = 5

    /// Below this, the UI shows dimensions/persona but not the fuller avoidance + evidence
    /// receipts layout.
    static let fullerProfileMinimumLogCount = 10
}
