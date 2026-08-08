//
//  TodayPickPresentation.swift
//  Listend
//

import Foundation

struct TodayPickAlbumTitlePresentation: Equatable {
    let primaryTitle: String
    let qualifiers: [String]

    var qualifierText: String? {
        guard !qualifiers.isEmpty else { return nil }
        return qualifiers.joined(separator: " · ")
    }
}

enum TodayPickAlbumTitleFormatter {
    private struct QualifierRule {
        let suffix: String
        let label: String
        let order: Int
    }

    private static let rules = [
        QualifierRule(suffix: " (original motion picture soundtrack)", label: "Soundtrack", order: 5),
        QualifierRule(suffix: " - original motion picture soundtrack", label: "Soundtrack", order: 5),
        QualifierRule(suffix: " (motion picture soundtrack)", label: "Soundtrack", order: 5),
        QualifierRule(suffix: " - motion picture soundtrack", label: "Soundtrack", order: 5),
        QualifierRule(suffix: " (original soundtrack)", label: "Soundtrack", order: 5),
        QualifierRule(suffix: " - original soundtrack", label: "Soundtrack", order: 5),
        QualifierRule(suffix: " (soundtrack)", label: "Soundtrack", order: 5),
        QualifierRule(suffix: " - soundtrack", label: "Soundtrack", order: 5),
        QualifierRule(suffix: " (deluxe album)", label: "Deluxe", order: 1),
        QualifierRule(suffix: " - deluxe album", label: "Deluxe", order: 1),
        QualifierRule(suffix: " (deluxe edition)", label: "Deluxe", order: 1),
        QualifierRule(suffix: " - deluxe edition", label: "Deluxe", order: 1),
        QualifierRule(suffix: " (deluxe version)", label: "Deluxe", order: 1),
        QualifierRule(suffix: " - deluxe version", label: "Deluxe", order: 1),
        QualifierRule(suffix: " (deluxe)", label: "Deluxe", order: 1),
        QualifierRule(suffix: " - deluxe", label: "Deluxe", order: 1),
        QualifierRule(suffix: " (expanded edition)", label: "Expanded", order: 2),
        QualifierRule(suffix: " - expanded edition", label: "Expanded", order: 2),
        QualifierRule(suffix: " (expanded)", label: "Expanded", order: 2),
        QualifierRule(suffix: " - expanded", label: "Expanded", order: 2),
        QualifierRule(suffix: " (special edition)", label: "Special edition", order: 3),
        QualifierRule(suffix: " - special edition", label: "Special edition", order: 3),
        QualifierRule(suffix: " (remastered)", label: "Remastered", order: 4),
        QualifierRule(suffix: " - remastered", label: "Remastered", order: 4),
        QualifierRule(suffix: " (bonus tracks)", label: "Bonus tracks", order: 6),
        QualifierRule(suffix: " - bonus tracks", label: "Bonus tracks", order: 6)
    ]

    static func presentation(for canonicalTitle: String) -> TodayPickAlbumTitlePresentation {
        let originalTitle = canonicalTitle
        var primaryTitle = canonicalTitle
        var qualifiers: [QualifierRule] = []

        while let match = rules.first(where: { rule in
            strippedTitle(from: primaryTitle, suffix: rule.suffix) != nil
        }), let strippedTitle = strippedTitle(from: primaryTitle, suffix: match.suffix) {
            primaryTitle = strippedTitle
            if !qualifiers.contains(where: { $0.label == match.label }) {
                qualifiers.append(match)
            }
        }

        guard !qualifiers.isEmpty else {
            return TodayPickAlbumTitlePresentation(
                primaryTitle: originalTitle,
                qualifiers: []
            )
        }

        return TodayPickAlbumTitlePresentation(
            primaryTitle: primaryTitle,
            qualifiers: qualifiers.sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.label < rhs.label
                }
                return lhs.order < rhs.order
            }.map(\.label)
        )
    }

    private static func strippedTitle(from title: String, suffix: String) -> String? {
        guard title.lowercased().hasSuffix(suffix) else { return nil }

        let suffixStart = title.index(title.endIndex, offsetBy: -suffix.count)
        let candidate = String(title[..<suffixStart])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        return candidate
    }
}

struct TodayPickReceiptPresentation: Equatable, Identifiable {
    let id: UUID
    let headline: String
    let whyItMattered: String
    let supportingEvidence: String
    let sourceMetadata: String?
}

enum TodayPickPresentation {
    static func whyThisPick(
        source: RecommendationSource?,
        receipts: [RecommendationReceipt]
    ) -> String {
        let receiptCount = receiptPresentations(for: receipts).count

        switch source {
        case .relatedAlbum:
            if receiptCount > 1 {
                return "It stays close to positive albums you logged, with more than one signal pointing the same way."
            }
            return "It stays close to a positive album you logged, using a related-album connection as the bridge."
        case .similarArtist:
            if receiptCount > 1 {
                return "It widens from positive albums you logged through a similar-artist connection, with more than one signal behind it."
            }
            return "It takes a wider step from a positive album you logged through a similar-artist connection."
        case .applePersonalRecommendations:
            if receiptCount > 0 {
                return "Apple Music surfaced it, and your positive logs provide the local context."
            }
            return "Apple Music surfaced it, but your local history is still thin here."
        case .listendFallback, nil:
            switch receiptCount {
            case 0:
                return "Your history is still thin here, so this is an exploratory pick based on the signals Listend has."
            case 1:
                return "One positive signal in your history points toward this connected listen."
            default:
                return "Positive signals from your history point toward this connected listen."
            }
        }
    }

    static func receiptPresentations(
        for receipts: [RecommendationReceipt],
        limit: Int = 3
    ) -> [TodayPickReceiptPresentation] {
        guard limit > 0 else { return [] }

        var seenReasons = Set<String>()
        var presentations: [TodayPickReceiptPresentation] = []

        for receipt in receipts {
            let presentation = receiptPresentation(for: receipt)
            let reasonKey = "\(presentation.headline.normalizedTodayPickPresentationText)|\(presentation.supportingEvidence.normalizedTodayPickPresentationText)"
            guard seenReasons.insert(reasonKey).inserted else { continue }

            presentations.append(presentation)
            if presentations.count == limit {
                break
            }
        }

        return presentations
    }

    private static func receiptPresentation(for receipt: RecommendationReceipt) -> TodayPickReceiptPresentation {
        let headline = headline(for: receipt)
        return TodayPickReceiptPresentation(
            id: receipt.id,
            headline: headline,
            whyItMattered: whyItMattered(for: receipt, headline: headline),
            supportingEvidence: supportingEvidence(for: receipt),
            sourceMetadata: sourceMetadata(for: receipt)
        )
    }

    private static func headline(for receipt: RecommendationReceipt) -> String {
        if let linkedDimension = receipt.linkedDimension?.trimmingCharacters(in: .whitespacesAndNewlines),
           !linkedDimension.isEmpty {
            return humanizedDimension(linkedDimension)
        }

        let snippet = receipt.snippet.lowercased()
        if snippet.contains("standout moment") {
            return "Standout moment"
        }
        if snippet.contains("favorite track") {
            return "Favorite tracks"
        }
        if snippet.contains("tagged") {
            return "Tags"
        }
        if snippet.contains("review") {
            return "Written review"
        }
        if snippet.contains("rated") {
            return receipt.sourceRating >= 4 ? "High rating" : "Rating"
        }
        return "Listening note"
    }

    private static func whyItMattered(
        for receipt: RecommendationReceipt,
        headline: String
    ) -> String {
        if let linkedDimension = receipt.linkedDimension?.trimmingCharacters(in: .whitespacesAndNewlines),
           !linkedDimension.isEmpty {
            return "The recommendation shares a catalog detail tied to this positive pattern."
        }

        switch headline {
        case "Standout moment":
            return "A specific moment gives this connection more detail than a rating alone."
        case "Favorite tracks":
            return "Track-level detail shows what held your attention."
        case "Tags":
            return "Your tags add a concrete detail to the connection."
        case "Written review":
            return "Your written note gives the connection more context than a rating alone."
        case "High rating":
            return "A high rating makes this album a positive anchor in your history."
        case "Rating":
            return "Your rating is the positive anchor available for this link."
        default:
            return "This is one of the strongest positive links available in your history."
        }
    }

    private static func supportingEvidence(for receipt: RecommendationReceipt) -> String {
        let snippet = receipt.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceTitle = receipt.sourceAlbumTitle
        let prefixes = [
            "Your standout moment on \(sourceTitle): ",
            "Your review of \(sourceTitle) said: ",
            "Favorite track from \(sourceTitle): ",
            "Favorite tracks from \(sourceTitle): ",
            "You tagged \(sourceTitle) "
        ]

        for prefix in prefixes where snippet.hasPrefix(prefix) {
            let evidence = String(snippet.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !evidence.isEmpty {
                if prefix.hasPrefix("Your review") || prefix.hasPrefix("Your standout") {
                    return "“\(evidence.trimmingCharacters(in: CharacterSet(charactersIn: ".")))”"
                }
                if prefix.hasPrefix("Favorite") {
                    return "Favorite tracks: \(evidence)"
                }
                return "Tags: \(evidence)"
            }
        }

        if snippet.hasPrefix("Rated \(sourceTitle) ") {
            return String(snippet.dropFirst("Rated \(sourceTitle) ".count))
        }

        return snippet.isEmpty ? "You logged a positive signal for this album." : snippet
    }

    private static func sourceMetadata(for receipt: RecommendationReceipt) -> String? {
        var parts: [String] = []
        let albumTitle = receipt.sourceAlbumTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artistName = receipt.sourceArtistName.trimmingCharacters(in: .whitespacesAndNewlines)

        if !albumTitle.isEmpty, albumTitle != "Unknown Album" {
            parts.append(albumTitle)
        }
        if !artistName.isEmpty, artistName != "Unknown Artist" {
            parts.append("by \(artistName)")
        }
        if receipt.sourceRating > 0 {
            parts.append("\(receipt.sourceRating.formatted(.number.precision(.fractionLength(1)))) stars")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func humanizedDimension(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var separated = ""
        var previousCharacter: Character?

        for character in trimmed {
            if (character == "_" || character == "-") {
                separated.append(" ")
            } else {
                if character.isUppercase, previousCharacter?.isLowercase == true {
                    separated.append(" ")
                }
                separated.append(character)
            }
            previousCharacter = character
        }

        let collapsed = separated
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return trimmed }
        if collapsed.contains(" ") {
            return collapsed.lowercased().capitalized
        }
        return collapsed.prefix(1).uppercased() + collapsed.dropFirst()
    }
}

private extension String {
    var normalizedTodayPickPresentationText: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
