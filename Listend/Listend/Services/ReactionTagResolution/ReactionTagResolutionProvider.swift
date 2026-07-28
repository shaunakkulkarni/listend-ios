//
//  ReactionTagResolutionProvider.swift
//  Listend
//

import Foundation
import SwiftUI

nonisolated struct ReactionTagResolutionInput: Equatable, Sendable {
    static let maximumCandidateCount = 12
    static let maximumReviewExcerptLength = 240

    let phrase: String
    let currentCategory: ReactionTagCategory?
    let rating: Double?
    let selectedCanonicalIDs: Set<String>
    let reviewExcerpt: String
    let candidates: [ReactionTagDefinition]

    init(
        phrase: String,
        currentCategory: ReactionTagCategory? = nil,
        rating: Double? = nil,
        selectedCanonicalIDs: Set<String> = [],
        reviewExcerpt: String = "",
        candidates: [ReactionTagDefinition]
    ) {
        self.phrase = TagTextNormalizer.displayValue(phrase)
        self.currentCategory = currentCategory
        self.rating = rating
        self.selectedCanonicalIDs = selectedCanonicalIDs
        self.reviewExcerpt = String(
            TagTextNormalizer.displayValue(reviewExcerpt)
                .prefix(Self.maximumReviewExcerptLength)
        )

        var seen = Set<String>()
        var boundedCandidates: [ReactionTagDefinition] = []
        for candidate in candidates where !selectedCanonicalIDs.contains(candidate.id) {
            guard seen.insert(candidate.id).inserted else {
                continue
            }

            boundedCandidates.append(candidate)
            if boundedCandidates.count == Self.maximumCandidateCount {
                break
            }
        }
        self.candidates = boundedCandidates
    }
}

nonisolated enum ReactionTagResolution: Equatable, Sendable {
    case canonical(ReactionTagDefinition)
    case choices([ReactionTagDefinition])
    case custom(displayValue: String)
}

nonisolated protocol ReactionTagResolving: Sendable {
    func resolve(_ input: ReactionTagResolutionInput) async throws -> ReactionTagResolution
}

nonisolated enum ReactionTagResolutionError: Error, Equatable {
    case unavailable
    case emptyOutput
    case malformedOutput
    case unknownID(String)
    case outOfShortlistID(String)
    case duplicateID(String)
    case tooManyChoices
}

nonisolated struct ReactionTagResolutionParser: Sendable {
    let catalog: TaxonomyCatalog

    func parse(
        _ output: String,
        input: ReactionTagResolutionInput
    ) throws -> ReactionTagResolution {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ReactionTagResolutionError.emptyOutput
        }

        let normalizedNewlines = trimmed
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rawLines = normalizedNewlines.components(separatedBy: "\n")
        guard !rawLines.contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw ReactionTagResolutionError.malformedOutput
        }

        let fields = try rawLines.map(parseField)
        guard fields.first?.key == "RESULT" else {
            throw ReactionTagResolutionError.malformedOutput
        }

        switch fields.first?.value {
        case "MATCH":
            guard fields.count == 2, fields[1].key == "MATCH" else {
                throw ReactionTagResolutionError.malformedOutput
            }
            return .canonical(try validatedCandidate(id: fields[1].value, input: input))

        case "AMBIGUOUS":
            if fields.count > 4 {
                throw ReactionTagResolutionError.tooManyChoices
            }
            guard (3...4).contains(fields.count),
                  fields[1].key == "MATCH",
                  fields.dropFirst(2).allSatisfy({ $0.key == "ALTERNATIVE" }) else {
                throw ReactionTagResolutionError.malformedOutput
            }

            var seen = Set<String>()
            let choices = try fields.dropFirst().map { field in
                guard seen.insert(field.value).inserted else {
                    throw ReactionTagResolutionError.duplicateID(field.value)
                }
                return try validatedCandidate(id: field.value, input: input)
            }
            return .choices(choices)

        case "NONE":
            guard fields.count == 1 else {
                throw ReactionTagResolutionError.malformedOutput
            }
            return .custom(displayValue: input.phrase)

        default:
            throw ReactionTagResolutionError.malformedOutput
        }
    }

    private func parseField(_ line: String) throws -> (key: String, value: String) {
        let components = line.components(separatedBy: "|")
        guard components.count == 2 else {
            throw ReactionTagResolutionError.malformedOutput
        }

        let key = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !value.isEmpty else {
            throw ReactionTagResolutionError.malformedOutput
        }

        return (key, value)
    }

    private func validatedCandidate(
        id: String,
        input: ReactionTagResolutionInput
    ) throws -> ReactionTagDefinition {
        guard catalog.reaction(id: id) != nil else {
            throw ReactionTagResolutionError.unknownID(id)
        }
        guard let candidate = input.candidates.first(where: { $0.id == id }) else {
            throw ReactionTagResolutionError.outOfShortlistID(id)
        }
        return candidate
    }
}

nonisolated struct LocalReactionTagResolutionProvider: ReactionTagResolving {
    func resolve(_ input: ReactionTagResolutionInput) async throws -> ReactionTagResolution {
        .custom(displayValue: input.phrase)
    }
}

nonisolated struct MockReactionTagResolver: ReactionTagResolving {
    let resolution: ReactionTagResolution?

    init(resolution: ReactionTagResolution? = nil) {
        self.resolution = resolution
    }

    func resolve(_ input: ReactionTagResolutionInput) async throws -> ReactionTagResolution {
        resolution ?? .custom(displayValue: input.phrase)
    }
}

nonisolated struct FallbackReactionTagResolver: ReactionTagResolving {
    let primary: any ReactionTagResolving
    let fallback: any ReactionTagResolving

    init(
        primary: any ReactionTagResolving = FoundationModelsReactionTagResolver(),
        fallback: any ReactionTagResolving = LocalReactionTagResolutionProvider()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    func resolve(_ input: ReactionTagResolutionInput) async throws -> ReactionTagResolution {
        do {
            return try await primary.resolve(input)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.resolve(input)
        }
    }
}

extension EnvironmentValues {
    @Entry var reactionTagResolver: any ReactionTagResolving = LocalReactionTagResolutionProvider()
}
