//
//  LogEntry.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import Foundation
import SwiftData

@Model
final class LogEntry {
    var id: UUID
    var album: Album?
    var rating: Double
    var reviewText: String
    var tagsRawValue: String
    var loggedAt: Date
    var updatedAt: Date

    var tags: [String] {
        get {
            tagsRawValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsRawValue = newValue.joined(separator: ",")
        }
    }

    init(
        id: UUID = UUID(),
        album: Album?,
        rating: Double,
        reviewText: String = "",
        tags: [String] = [],
        loggedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.album = album
        self.rating = rating
        self.reviewText = reviewText
        self.tagsRawValue = tags.joined(separator: ",")
        self.loggedAt = loggedAt
        self.updatedAt = updatedAt
    }
}
