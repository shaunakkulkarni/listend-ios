//
//  SandboxMode.swift
//  Listend
//

enum SandboxMode {
    #if SANDBOX
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif
}
