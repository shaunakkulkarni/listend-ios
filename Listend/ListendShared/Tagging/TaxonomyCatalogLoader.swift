//
//  TaxonomyCatalogLoader.swift
//  Listend
//

import Foundation

nonisolated enum TaxonomyCatalogLoaderError: Error, Equatable, Sendable {
    case missingResource(name: String, bundlePath: String)
}

nonisolated enum TaxonomyCatalogLoader {
    static let reactionResourceName = "Listend_Reaction_Tags_v1"
    static let genreResourceName = "Listend_Genre_Styles_v1"
    static let ambiguousAliasResourceName = "Listend_Ambiguous_Aliases_v1"

    static let resourceFilenames = [
        "\(reactionResourceName).json",
        "\(genreResourceName).json",
        "\(ambiguousAliasResourceName).json"
    ]

    static let shared: TaxonomyCatalog = loadBundledCatalog()

    nonisolated static func load(
        from bundle: Bundle,
        expectedCounts: TaxonomyExpectedCounts? = .canonicalV1
    ) throws -> TaxonomyCatalog {
        try decode(
            reactionData: resourceData(named: reactionResourceName, in: bundle),
            genreData: resourceData(named: genreResourceName, in: bundle),
            ambiguousAliasData: resourceData(named: ambiguousAliasResourceName, in: bundle),
            expectedCounts: expectedCounts
        )
    }

    nonisolated static func decode(
        reactionData: Data,
        genreData: Data,
        ambiguousAliasData: Data,
        expectedCounts: TaxonomyExpectedCounts? = .canonicalV1,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> TaxonomyCatalog {
        let reactions = try decoder.decode(ReactionTagCatalog.self, from: reactionData)
        let genres = try decoder.decode(GenreStyleCatalog.self, from: genreData)
        let ambiguousAliases = try decoder.decode(AmbiguousAliasCatalog.self, from: ambiguousAliasData)

        return try TaxonomyCatalog(
            reactions: reactions,
            genres: genres,
            ambiguousAliases: ambiguousAliases,
            expectedCounts: expectedCounts
        )
    }

    private nonisolated static func resourceData(named name: String, in bundle: Bundle) throws -> Data {
        guard let url = resourceURL(named: name, in: bundle) else {
            throw TaxonomyCatalogLoaderError.missingResource(
                name: "\(name).json",
                bundlePath: bundle.bundlePath
            )
        }

        return try Data(contentsOf: url)
    }

    private nonisolated static func resourceURL(named name: String, in bundle: Bundle) -> URL? {
        let subdirectories = [
            "Taxonomy",
            "Resources/Taxonomy",
            "ListendShared/Resources/Taxonomy"
        ]

        if let flatURL = bundle.url(forResource: name, withExtension: "json") {
            return flatURL
        }

        for subdirectory in subdirectories {
            if let url = bundle.url(
                forResource: name,
                withExtension: "json",
                subdirectory: subdirectory
            ) {
                return url
            }
        }

        return nil
    }

    private static func loadBundledCatalog() -> TaxonomyCatalog {
        do {
            return try load(from: .main)
        } catch {
            #if DEBUG
            fatalError("Bundled taxonomy failed validation: \(error)")
            #else
            return .empty
            #endif
        }
    }
}
