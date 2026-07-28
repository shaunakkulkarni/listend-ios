//
//  TaxonomyModels.swift
//  Listend
//

import Foundation

nonisolated enum ReactionTagCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case moodVibe = "mood-vibe"
    case energyMovement = "energy-movement"
    case sonicCharacter = "sonic-character"
    case craftPerformance = "craft-performance"
    case listeningContext = "listening-context"
    case personalReaction = "personal-reaction"
    case frictionCritique = "friction-critique"

    var displayName: String {
        switch self {
        case .moodVibe:
            return "Mood & Vibe"
        case .energyMovement:
            return "Energy & Movement"
        case .sonicCharacter:
            return "Sonic Character"
        case .craftPerformance:
            return "Craft & Performance"
        case .listeningContext:
            return "Listening Context"
        case .personalReaction:
            return "Personal Reaction"
        case .frictionCritique:
            return "Friction & Critique"
        }
    }
}

nonisolated enum ReactionTagPolarity: String, Codable, CaseIterable, Hashable, Sendable {
    case positive
    case neutral
    case negative
    case mixed
}

nonisolated enum RecommendationTagRole: String, Codable, CaseIterable, Hashable, Sendable {
    case tasteSignalOnly
    case avoidanceSignal
    case displayOnly
}

nonisolated enum GenreRecommendationRole: String, Codable, CaseIterable, Hashable, Sendable {
    case catalogQuery
}

nonisolated struct ReactionTagDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let category: ReactionTagCategory
    let definition: String
    let aliases: [String]
    let polarity: ReactionTagPolarity
    let genreAffinityFamilies: [String]
    let soundPrintDimensions: [String]
    let avoidanceSignals: [String]
    let recommendationRole: RecommendationTagRole
    let isPrimarySuggestion: Bool
}

nonisolated struct ReactionTagCategoryDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: ReactionTagCategory
    let displayName: String
}

nonisolated struct ReactionTagCatalog: Codable, Hashable, Sendable {
    let taxonomyVersion: String
    let generatedDate: String
    let purpose: String
    let categories: [ReactionTagCategoryDefinition]
    let allowedPolarities: [ReactionTagPolarity]
    let allowedRecommendationRoles: [RecommendationTagRole]
    let soundPrintDimensions: [String]
    let avoidanceSignals: [String]
    let tags: [ReactionTagDefinition]

    static let empty = ReactionTagCatalog(
        taxonomyVersion: "unavailable",
        generatedDate: "",
        purpose: "",
        categories: [],
        allowedPolarities: [],
        allowedRecommendationRoles: [],
        soundPrintDimensions: [],
        avoidanceSignals: [],
        tags: []
    )
}

nonisolated struct GenreFamilyDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let displayName: String
}

nonisolated struct GenreStyleDefinition: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let family: String
    let aliases: [String]
    let parentID: String?
    let recommendationRole: GenreRecommendationRole
}

nonisolated struct GenreStyleCatalog: Codable, Hashable, Sendable {
    let taxonomyVersion: String
    let generatedDate: String
    let purpose: String
    let families: [GenreFamilyDefinition]
    let styles: [GenreStyleDefinition]

    static let empty = GenreStyleCatalog(
        taxonomyVersion: "unavailable",
        generatedDate: "",
        purpose: "",
        families: [],
        styles: []
    )
}

nonisolated struct AmbiguousTagAlias: Identifiable, Codable, Hashable, Sendable {
    var id: String { term }

    let term: String
    let candidateIDs: [String]
    let prompt: String
}

nonisolated struct AmbiguousAliasCatalog: Codable, Hashable, Sendable {
    let taxonomyVersion: String
    let generatedDate: String
    let purpose: String
    let aliases: [AmbiguousTagAlias]

    static let empty = AmbiguousAliasCatalog(
        taxonomyVersion: "unavailable",
        generatedDate: "",
        purpose: "",
        aliases: []
    )
}

nonisolated struct TaxonomyCatalog: Sendable {
    let reactions: ReactionTagCatalog
    let genres: GenreStyleCatalog
    let ambiguousAliases: AmbiguousAliasCatalog

    private let reactionsByID: [String: ReactionTagDefinition]
    private let genreStylesByID: [String: GenreStyleDefinition]

    var isEmpty: Bool {
        reactions.tags.isEmpty && genres.styles.isEmpty
    }

    init(
        reactions: ReactionTagCatalog,
        genres: GenreStyleCatalog,
        ambiguousAliases: AmbiguousAliasCatalog,
        expectedCounts: TaxonomyExpectedCounts? = nil
    ) throws {
        try TaxonomyValidator.validate(
            reactions: reactions,
            genres: genres,
            ambiguousAliases: ambiguousAliases,
            expectedCounts: expectedCounts
        )

        self.reactions = reactions
        self.genres = genres
        self.ambiguousAliases = ambiguousAliases
        self.reactionsByID = Dictionary(uniqueKeysWithValues: reactions.tags.map { ($0.id, $0) })
        self.genreStylesByID = Dictionary(uniqueKeysWithValues: genres.styles.map { ($0.id, $0) })
    }

    func reaction(id: String) -> ReactionTagDefinition? {
        reactionsByID[id]
    }

    func genreStyle(id: String) -> GenreStyleDefinition? {
        genreStylesByID[id]
    }

    static let empty = TaxonomyCatalog(
        uncheckedReactions: .empty,
        uncheckedGenres: .empty,
        uncheckedAmbiguousAliases: .empty
    )

    private init(
        uncheckedReactions reactions: ReactionTagCatalog,
        uncheckedGenres genres: GenreStyleCatalog,
        uncheckedAmbiguousAliases ambiguousAliases: AmbiguousAliasCatalog
    ) {
        self.reactions = reactions
        self.genres = genres
        self.ambiguousAliases = ambiguousAliases
        self.reactionsByID = [:]
        self.genreStylesByID = [:]
    }
}
