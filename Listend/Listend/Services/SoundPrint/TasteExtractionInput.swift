//
//  TasteExtractionInput.swift
//  Listend
//
//  Created by Codex on 4/25/26.
//

import Foundation

struct TasteExtractionInput {
    let logID: UUID
    let albumTitle: String
    let artistName: String
    let genreName: String?
    let releaseYear: Int?
    let rating: Double
    let reviewText: String
    let tags: [String]
    let sentimentScore: Double?
}
