//
//  FoundationModelsReactionTagResolver.swift
//  Listend
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// iOS 26-safe Foundation Models path: plain text response plus strict local parsing.
nonisolated struct FoundationModelsReactionTagResolver: ReactionTagResolving {
    private let parser: ReactionTagResolutionParser

    init(catalog: TaxonomyCatalog = TaxonomyCatalogLoader.shared) {
        parser = ReactionTagResolutionParser(catalog: catalog)
    }

    func resolve(_ input: ReactionTagResolutionInput) async throws -> ReactionTagResolution {
        guard !input.candidates.isEmpty else {
            return .custom(displayValue: input.phrase)
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else {
                throw ReactionTagResolutionError.unavailable
            }

            let session = LanguageModelSession(instructions: Self.instructions)
            let response = try await session.respond(to: Self.prompt(for: input))
            return try parser.parse(response.content, input: input)
        }
        #endif

        throw ReactionTagResolutionError.unavailable
    }

    private static let instructions = """
    You classify a listener's custom music reaction against only the supplied candidates.
    Return exactly one documented result shape and no commentary.
    """

    private static func prompt(for input: ReactionTagResolutionInput) -> String {
        let rating = input.rating.map { String($0) } ?? "unknown"
        let category = input.currentCategory?.displayName ?? "unknown"
        let selectedIDs = input.selectedCanonicalIDs.sorted().joined(separator: ", ")
        let candidateLines = input.candidates.map { candidate in
            let definition = String(
                TagTextNormalizer.displayValue(candidate.definition).prefix(180)
            )
            return "\(candidate.id) | \(candidate.displayName) | \(definition)"
        }
        .joined(separator: "\n")

        return """
        Phrase: \(input.phrase)
        Current category: \(category)
        Rating: \(rating)
        Already selected canonical IDs: \(selectedIDs)
        Short review excerpt: \(input.reviewExcerpt)

        Candidate IDs, display names, and definitions:
        \(candidateLines)

        Allowed output:
        RESULT | MATCH
        MATCH | candidate.id

        or, for two or three plausible choices:
        RESULT | AMBIGUOUS
        MATCH | candidate.id
        ALTERNATIVE | candidate.id
        ALTERNATIVE | candidate.id

        or:
        RESULT | NONE

        Use only candidate IDs listed above. Do not add fields, prose, or formatting.
        """
    }
}
