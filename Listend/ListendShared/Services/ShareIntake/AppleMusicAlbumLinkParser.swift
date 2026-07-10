//
//  AppleMusicAlbumLinkParser.swift
//  Listend
//

import Foundation

struct AppleMusicAlbumLink: Equatable {
    /// Numeric Apple Music catalog album ID, present only for canonical album URLs.
    let albumID: String?
    /// Human-readable words recovered from the URL slug, for prefilling manual search.
    let titleHint: String?
    let storefront: String?
    let originalURL: URL
}

enum AppleMusicAlbumLinkParser {
    /// Parses pasted text into an Apple Music album link.
    ///
    /// Only canonical `music.apple.com/{storefront}/album/...` URLs are accepted;
    /// an album ID is extracted only when the trailing path component is numeric
    /// (`.../album/{slug}/{id}` or `.../album/{id}`). Album paths without a numeric
    /// ID still return a link carrying a `titleHint` from the slug. Anything else
    /// (other hosts, playlists, artists, songs, non-URL text) returns nil.
    static func parse(_ input: String) -> AppleMusicAlbumLink? {
        guard let url = firstURL(in: input) else {
            return nil
        }

        guard let host = url.host?.lowercased(), host == "music.apple.com" else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }

        guard let albumIndex = pathComponents.firstIndex(of: "album") else {
            return nil
        }

        let storefront = albumIndex > 0 ? pathComponents[albumIndex - 1].lowercased() : nil
        let albumPathComponents = Array(pathComponents[(albumIndex + 1)...])

        guard !albumPathComponents.isEmpty else {
            return nil
        }

        let albumID: String?
        let slug: String?

        if let lastComponent = albumPathComponents.last, isNumericID(lastComponent) {
            albumID = lastComponent
            slug = albumPathComponents.count > 1 ? albumPathComponents.first : nil
        } else {
            albumID = nil
            slug = albumPathComponents.first
        }

        return AppleMusicAlbumLink(
            albumID: albumID,
            titleHint: titleHint(fromSlug: slug),
            storefront: storefront,
            originalURL: url
        )
    }

    private static func firstURL(in input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return nil
        }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return URL(string: trimmed)
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let match = detector.firstMatch(in: trimmed, range: range)
        return match?.url
    }

    private static func isNumericID(_ component: String) -> Bool {
        !component.isEmpty && component.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func titleHint(fromSlug slug: String?) -> String? {
        guard let slug else {
            return nil
        }

        let words = slug
            .split(separator: "-")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else {
            return nil
        }

        return words.joined(separator: " ")
    }
}
