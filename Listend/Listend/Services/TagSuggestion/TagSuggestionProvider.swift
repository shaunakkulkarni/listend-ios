//
//  TagSuggestionProvider.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

import Foundation

struct TagSuggestionInput: Equatable {
    let albumTitle: String
    let artistName: String
    let genreName: String?
    let releaseYear: Int?
    let reviewText: String
    let existingTags: [String]

    init(
        albumTitle: String,
        artistName: String,
        genreName: String? = nil,
        releaseYear: Int? = nil,
        reviewText: String,
        existingTags: [String]
    ) {
        self.albumTitle = albumTitle
        self.artistName = artistName
        self.genreName = genreName
        self.releaseYear = releaseYear
        self.reviewText = reviewText
        self.existingTags = existingTags
    }

    init(album: Album, reviewText: String, existingTags: [String]) {
        self.init(
            albumTitle: album.title,
            artistName: album.artistName,
            genreName: album.genreName,
            releaseYear: album.releaseYear,
            reviewText: reviewText,
            existingTags: existingTags
        )
    }
}

protocol TagSuggestionProvider {
    func suggestedTags(for input: TagSuggestionInput) async throws -> [String]
}

enum TagSuggestionProviderError: Error, Equatable {
    case unavailable
    case emptyOutput
    case malformedOutput
    case validationFailed
}

