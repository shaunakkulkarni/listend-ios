//
//  SoundPrintProfileThresholds.swift
//  Listend
//
//  Centralized log-count gates for SoundPrint's dynamic states, so the same numbers
//  drive both profile-building logic and the UI copy/sections that depend on them.
//

enum SoundPrintProfileThresholds {
    /// Below this, dimensions/avoidance signals may exist but there's not enough to call
    /// them anything more than early signals.
    static let earlySignalMinimumLogCount = 3

    /// Persona and compact summary generation both gate on this — see plan decision 8:
    /// they're independent steps sharing one threshold, not staggered.
    static let personaMinimumLogCount = 5

    /// Below this, the UI shows dimensions/persona but not the fuller avoidance + evidence
    /// receipts layout.
    static let fullerProfileMinimumLogCount = 10

    /// "What's changing" is deferred out of v1.5 (see plan) — this constant exists as the
    /// documented extension point for when that ships.
    static let whatsChangingMinimumLogCount = 20
}
