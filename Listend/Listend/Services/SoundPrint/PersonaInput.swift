//
//  PersonaInput.swift
//  Listend
//
//  Created by Codex on 4/26/26.
//

struct PersonaInput {
    let dimensions: [TasteDimension]
    let recentLogs: [PersonaLogInput]
    let totalLogCount: Int
    let topTags: [String]
    let averageRating: Double?
}

struct PersonaLogInput {
    let albumTitle: String
    let artistName: String
    let rating: Double
    let reviewSnippet: String
    let tags: [String]
    let isPositiveSignal: Bool
}
