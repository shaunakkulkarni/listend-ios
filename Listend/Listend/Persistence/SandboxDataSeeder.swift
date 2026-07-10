//
//  SandboxDataSeeder.swift
//  Listend
//

import Foundation
import SwiftData

enum SandboxScenario: String, CaseIterable, Identifiable {
    case richProfile
    case newUser
    case lockedTodayPick
    case activePick
    case savedPicks
    case familiarDiscovery
    case balancedDiscovery
    case adventurousDiscovery

    static let `default`: SandboxScenario = .richProfile

    init(rawValue: String?) {
        guard let rawValue, let scenario = SandboxScenario(rawValue: rawValue) else {
            self = .default
            return
        }

        self = scenario
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .richProfile: return "Rich profile"
        case .newUser: return "New user"
        case .lockedTodayPick: return "Today’s Pick locked"
        case .activePick: return "Active pick"
        case .savedPicks: return "Saved Picks history"
        case .familiarDiscovery: return "Familiar discovery"
        case .balancedDiscovery: return "Balanced discovery"
        case .adventurousDiscovery: return "Adventurous discovery"
        }
    }

    var detail: String {
        switch self {
        case .richProfile: return "Ten detailed logs, SoundPrint, avoidance signals, an active pick, and saved history."
        case .newUser: return "A completely empty account for cold-start and onboarding checks."
        case .lockedTodayPick: return "Three logs, early taste signals, and a locked Today’s Pick."
        case .activePick: return "Seven logs, a generated SoundPrint, and one active recommendation with receipts."
        case .savedPicks: return "Eight logs and multiple saved recommendations without an active pick."
        case .familiarDiscovery: return "Rich taste data with Familiar selected and no active pick."
        case .balancedDiscovery: return "Rich taste data with Balanced selected and no active pick."
        case .adventurousDiscovery: return "Rich taste data with Adventurous selected and no active pick."
        }
    }
}

enum SandboxPreferenceKey {
    static let scenario = "sandbox.scenario"
    static let didSeed = "sandbox.didSeed"
}

@MainActor
enum SandboxDataSeeder {
    static func seedInitialDataIfNeeded(in modelContext: ModelContext) throws {
        guard SandboxMode.isEnabled,
              !UserDefaults.standard.bool(forKey: SandboxPreferenceKey.didSeed) else {
            return
        }

        let scenario = SandboxScenario(
            rawValue: UserDefaults.standard.string(forKey: SandboxPreferenceKey.scenario)
        )
        try resetAndSeed(scenario, in: modelContext)
    }

    static func resetAndSeed(_ scenario: SandboxScenario, in modelContext: ModelContext) throws {
        guard SandboxMode.isEnabled else { return }

        try deleteAllData(in: modelContext)
        UserDefaults.standard.set(scenario.rawValue, forKey: SandboxPreferenceKey.scenario)
        applyRecommendationMode(for: scenario)

        if scenario != .newUser {
            try seed(scenario, in: modelContext)
        }

        try modelContext.save()
        UserDefaults.standard.set(true, forKey: SandboxPreferenceKey.didSeed)
    }

    private static func seed(_ scenario: SandboxScenario, in modelContext: ModelContext) throws {
        let allAlbums = sandboxAlbums
        let logCount: Int

        switch scenario {
        case .lockedTodayPick:
            logCount = 3
        case .activePick:
            logCount = 7
        case .savedPicks:
            logCount = 8
        default:
            logCount = 10
        }

        allAlbums.forEach(modelContext.insert)
        let logs = Array(allAlbums.prefix(logCount)).enumerated().map { index, album in
            let log = LogEntry(
                album: album,
                rating: ratings[index],
                reviewText: reviews[index],
                tags: tags[index],
                favoriteTracks: favoriteTracks[index],
                skipTracks: skipTracks[index],
                standoutMoment: standoutMoments[index],
                sentimentScore: index == 7 ? -0.35 : sentiments[index],
                sentimentConfidence: 0.85,
                loggedAt: Date().addingTimeInterval(TimeInterval(-index * 86_400)),
                updatedAt: Date().addingTimeInterval(TimeInterval(-index * 86_400))
            )
            modelContext.insert(log)
            return log
        }

        seedTasteData(logs: logs, includePersona: logCount >= 5, in: modelContext)

        switch scenario {
        case .richProfile:
            seedRecommendations(logs: logs, includeActive: true, savedCount: 2, in: modelContext)
        case .activePick:
            seedRecommendations(logs: logs, includeActive: true, savedCount: 0, in: modelContext)
        case .savedPicks:
            seedRecommendations(logs: logs, includeActive: false, savedCount: 3, in: modelContext)
        default:
            break
        }
    }

    private static func seedTasteData(logs: [LogEntry], includePersona: Bool, in modelContext: ModelContext) {
        guard let firstLog = logs.first else { return }

        let dimensions = [
            TasteDimension(name: "vocalFocus", label: "Vocal Gravity", weight: 0.88, confidence: 0.86, summary: "Rewards intimate, expressive vocal performances."),
            TasteDimension(name: "productionStyle", label: "Textural Production", weight: 0.79, confidence: 0.81, summary: "Returns to layered production with tactile detail."),
            TasteDimension(name: "replayability", label: "Replay Pull", weight: 0.72, confidence: 0.76, summary: "Values albums that reveal more over repeat listens.")
        ]
        dimensions.forEach(modelContext.insert)
        modelContext.insert(
            TasteEvidence(
                dimensionName: "vocalFocus",
                logEntryID: firstLog.id,
                snippet: "Sparse, intimate vocals that still feel huge.",
                evidenceType: "reviewOrTag",
                strength: 0.88,
                confidence: 0.86,
                isPositiveEvidence: true
            )
        )

        if logs.count > 7 {
            modelContext.insert(
                TasteAvoidanceSignal(
                    name: "skipHeavyAlbums",
                    label: "Skip-Heavy Albums",
                    summary: "Loses patience when the back half stops earning its runtime.",
                    strength: 0.68,
                    confidence: 0.74,
                    evidenceLogEntryIDs: [logs[7].id]
                )
            )
        }

        if includePersona {
            modelContext.insert(
                SoundPrintPersona(
                    personaText: "You gravitate toward albums where expressive vocals and layered production reward close repeat listening. Blonde and Titanic Rising are the clearest anchors, while bloated back halves lose you quickly.",
                    logCountAtGeneration: logs.count,
                    headline: "Detail Without Dead Weight",
                    summaryText: "Expressive vocals, tactile production, and replay value win; uneven tracklists do not.",
                    bullets: ["Rewards vocal intimacy", "Returns for production detail", "Avoids weak back halves"],
                    generationSource: .localFallback
                )
            )
        }
    }

    private static func seedRecommendations(
        logs: [LogEntry],
        includeActive: Bool,
        savedCount: Int,
        in modelContext: ModelContext
    ) {
        guard let anchor = logs.dropFirst().first, let anchorAlbum = anchor.album else { return }

        let candidates = [
            Album(appleMusicID: "sandbox.fetch-the-bolt-cutters", title: "Fetch the Bolt Cutters", artistName: "Fiona Apple", releaseYear: 2020, genreName: "Art Pop"),
            Album(appleMusicID: "sandbox.dragon-new-warm-mountain", title: "Dragon New Warm Mountain I Believe in You", artistName: "Big Thief", releaseYear: 2022, genreName: "Alternative"),
            Album(appleMusicID: "sandbox.carrie-lowell", title: "Carrie & Lowell", artistName: "Sufjan Stevens", releaseYear: 2015, genreName: "Indie Folk"),
            Album(appleMusicID: "sandbox.saint-cloud", title: "Saint Cloud", artistName: "Waxahatchee", releaseYear: 2020, genreName: "Indie Rock")
        ]
        candidates.forEach(modelContext.insert)

        var recommendations: [Recommendation] = []
        if includeActive {
            recommendations.append(
                Recommendation(
                    album: candidates[0],
                    score: 0.84,
                    confidence: 0.82,
                    explanationText: "Today’s Pick is Fetch the Bolt Cutters by Fiona Apple, grounded in your log for Titanic Rising."
                )
            )
        }

        for index in 0..<min(savedCount, candidates.count - 1) {
            recommendations.append(
                Recommendation(
                    album: candidates[index + 1],
                    score: 0.76 - Double(index) * 0.04,
                    confidence: 0.72,
                    status: RecommendationStatus.saved.rawValue,
                    explanationText: "Saved Sandbox pick grounded in your log for \(anchorAlbum.title).",
                    createdAt: Date().addingTimeInterval(TimeInterval(-(index + 1) * 3_600))
                )
            )
        }

        for recommendation in recommendations {
            modelContext.insert(recommendation)
            modelContext.insert(
                RecommendationReceipt(
                    recommendationID: recommendation.id,
                    logEntryID: anchor.id,
                    sourceAlbumTitle: anchorAlbum.title,
                    sourceArtistName: anchorAlbum.artistName,
                    sourceRating: anchor.rating,
                    snippet: "You called \(anchorAlbum.title) lush, layered, and worth returning to.",
                    linkedDimension: "productionStyle"
                )
            )

            if recommendation.status == RecommendationStatus.saved.rawValue {
                modelContext.insert(
                    RecommendationFeedback(
                        recommendationID: recommendation.id,
                        feedbackType: RecommendationFeedbackType.savedForLater.rawValue
                    )
                )
            }
        }
    }

    private static func applyRecommendationMode(for scenario: SandboxScenario) {
        let mode: TodayPickRecommendationMode
        switch scenario {
        case .familiarDiscovery: mode = .familiar
        case .adventurousDiscovery: mode = .adventurous
        default: mode = .balanced
        }
        UserDefaults.standard.set(mode.rawValue, forKey: TodayPickPreferenceKey.recommendationMode)
    }

    private static func deleteAllData(in modelContext: ModelContext) throws {
        try deleteAll(RecommendationReceipt.self, in: modelContext)
        try deleteAll(RecommendationFeedback.self, in: modelContext)
        try deleteAll(Recommendation.self, in: modelContext)
        try deleteAll(TasteEvidence.self, in: modelContext)
        try deleteAll(TasteAvoidanceSignal.self, in: modelContext)
        try deleteAll(TasteDimension.self, in: modelContext)
        try deleteAll(SoundPrintPersona.self, in: modelContext)
        try deleteAll(RecentlyPlayedAlbumSnapshot.self, in: modelContext)
        try deleteAll(AppleMusicRecentPlaySnapshot.self, in: modelContext)
        try deleteAll(AlbumTrack.self, in: modelContext)
        try deleteAll(LogEntry.self, in: modelContext)
        try deleteAll(Album.self, in: modelContext)
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in modelContext: ModelContext) throws {
        for model in try modelContext.fetch(FetchDescriptor<T>()) {
            modelContext.delete(model)
        }
    }

    private static let sandboxAlbums = [
        Album(appleMusicID: "sandbox.blonde", title: "Blonde", artistName: "Frank Ocean", releaseYear: 2016, genreName: "Alternative R&B"),
        Album(appleMusicID: "sandbox.titanic-rising", title: "Titanic Rising", artistName: "Weyes Blood", releaseYear: 2019, genreName: "Art Pop"),
        Album(appleMusicID: "sandbox.madvillainy", title: "Madvillainy", artistName: "Madvillain", releaseYear: 2004, genreName: "Hip-Hop"),
        Album(appleMusicID: "sandbox.vespertine", title: "Vespertine", artistName: "Björk", releaseYear: 2001, genreName: "Art Pop"),
        Album(appleMusicID: "sandbox.simbi", title: "Sometimes I Might Be Introvert", artistName: "Little Simz", releaseYear: 2021, genreName: "Hip-Hop"),
        Album(appleMusicID: "sandbox.in-rainbows", title: "In Rainbows", artistName: "Radiohead", releaseYear: 2007, genreName: "Alternative Rock"),
        Album(appleMusicID: "sandbox.ctrl", title: "Ctrl", artistName: "SZA", releaseYear: 2017, genreName: "R&B"),
        Album(appleMusicID: "sandbox.sos", title: "SOS", artistName: "SZA", releaseYear: 2022, genreName: "R&B"),
        Album(appleMusicID: "sandbox.nfr", title: "Norman Fucking Rockwell!", artistName: "Lana Del Rey", releaseYear: 2019, genreName: "Art Pop"),
        Album(appleMusicID: "sandbox.bitches-brew", title: "Bitches Brew", artistName: "Miles Davis", releaseYear: 1970, genreName: "Jazz")
    ]

    private static let ratings = [5.0, 4.5, 4.5, 4.0, 4.5, 5.0, 4.0, 2.5, 4.0, 4.5]
    private static let sentiments = [0.95, 0.82, 0.80, 0.72, 0.84, 0.93, 0.68, -0.35, 0.70, 0.86]
    private static let reviews = [
        "Sparse, intimate vocals that still feel huge. I hear something new every time.",
        "Lush and layered, but never sleepy. The arrangements keep opening up.",
        "Dense samples with replay value for days and not a wasted second.",
        "Beautiful micro-details and strange textures, even when it turns icy.",
        "Polished storytelling with momentum and a genuinely great final stretch.",
        "Tense, warm, and endlessly replayable. Every transition earns its place.",
        "The writing lands, and the loose edges make it feel lived in.",
        "A strong opening buried under a bloated back half with too many skips.",
        "Elegant and cinematic, though a couple tracks blur together.",
        "Restless, immersive, and adventurous without losing the emotional thread."
    ]
    private static let tags = [
        ["vocals", "late night", "intimate"], ["lush", "layered", "art pop"],
        ["dense", "samples", "replay"], ["experimental", "textured", "beautiful"],
        ["storytelling", "polished", "momentum"], ["warm", "textured", "replay"],
        ["songwriting", "loose", "r&b"], ["uneven", "bloated", "front-loaded"],
        ["cinematic", "melancholy", "polished"], ["jazz", "adventurous", "immersive"]
    ]
    private static let favoriteTracks = [["Nights"], ["Movies"], ["Accordion"], [], ["Introvert"], ["Weird Fishes/Arpeggi"], ["Prom"], [], ["Venice Bitch"], ["Pharaoh's Dance"]]
    private static let skipTracks = [[], [], [], [], [], [], [], ["Track 4", "Track 5", "Track 8"], [], []]
    private static let standoutMoments: [String?] = ["The beat switch in Nights.", "The strings entering during the bridge.", nil, "The tiny percussion details.", nil, "The final lift in Weird Fishes.", nil, nil, "The long outro opening up.", "The first electric trumpet entrance."]
}
