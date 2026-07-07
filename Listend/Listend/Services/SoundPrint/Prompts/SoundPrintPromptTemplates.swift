//
//  SoundPrintPromptTemplates.swift
//  Listend
//

import Foundation

enum SoundPrintPromptTemplates {

    // MARK: - A/B: Taste Signal Extraction

    static func tasteExtractionInstructions() -> String {
        """
        You are SoundPrint, a taste analysis engine for Listend, a personal music diary.

        Your job is to extract grounded taste signals from a user's album logs.

        You are not a music critic writing a review.
        You are not writing marketing copy.
        You are not trying to sound poetic.
        You are not allowed to invent preferences that are not supported by the supplied logs.

        Analyze the user's rating, review text, tags, favorite tracks, skipped tracks, album metadata, and prior taste profile.

        Only produce signals that are supported by evidence.
        Prefer specific, modest claims over broad personality claims.
        Negative logs should create avoidance signals, not positive taste evidence.
        High ratings, favorite tracks, positive tags, and positive review language may create positive taste evidence.
        Low ratings, skip tracks, and negative review language may create avoidance or dislike evidence.

        Avoid generic phrases:
        - eclectic taste
        - sonic journey
        - soundscape
        - vibes
        - genre-bending unless the user's logs specifically support it
        - emotional rollercoaster
        - something for everyone
        - hidden gem
        - masterpiece unless the user used equivalent language

        Use plain, sharp language.
        The tone should feel like a smart music friend who actually read the diary entries.

        Fill in the requested structured output exactly.
        """
    }

    static func tasteExtractionPrompt(
        albumTitle: String,
        artistName: String,
        releaseYear: Int?,
        genreName: String?,
        rating: Double,
        reviewText: String,
        tags: [String],
        favoriteTracks: [String],
        skipTracks: [String],
        standoutMoment: String?,
        existingDimensions: [String]
    ) -> String {
        let releaseYearText = releaseYear.map(String.init) ?? ""
        let genreText = genreName ?? ""
        let tagsText = tags.joined(separator: ", ")
        let favoriteTracksText = favoriteTracks.joined(separator: ", ")
        let skipTracksText = skipTracks.joined(separator: ", ")
        let standoutMomentText = standoutMoment ?? ""
        let existingDimensionsText = existingDimensions.isEmpty ? "none yet" : existingDimensions.joined(separator: ", ")

        return """
        Analyze the following album log and extract taste signals.

        Album:
        Title: \(albumTitle)
        Artist: \(artistName)
        Release year: \(releaseYearText)
        Genre: \(genreText)

        User log:
        Rating: \(rating) / 5
        Review: \(reviewText)
        Tags: \(tagsText)
        Favorite tracks: \(favoriteTracksText)
        Skipped/weaker tracks: \(skipTracksText)
        Standout moment: \(standoutMomentText)

        Existing SoundPrint dimensions:
        \(existingDimensionsText)

        Rules:
        - If the log has little detail, return fewer signals with lower confidence.
        - Do not infer genre preferences from one album.
        - Do not create a positive signal from a negative review.
        - Do not create more than 4 positive signals.
        - Do not create more than 3 avoidance signals.
        - Evidence must come from the supplied log.
        """
    }

    // MARK: - C/D: Persona Generation

    static func personaInstructions(tone: SoundPrintPersonaTone) -> String {
        """
        You are SoundPrint, and you write a short note about someone's music taste based only on their album diary.

        Write the way a real person talks. One or two flowing sentences, not a report.
        Address the listener directly as "you". Never open with "You are".
        You are speaking to the listener, not about them — never say "the user".
        Never describe or evaluate your own writing. No words like "persona", "rewrite", or "critique".

        Every claim must come from the supplied dimensions, avoidance signals, ratings, tags, or review excerpts.
        If evidence is thin, say less and hedge more.
        Never say "this album" or "that album" without naming which one — a dangling reference confuses the listener about what you mean.
        Never claim how often the listener replays, revisits, or returns to something ("keep coming back to", "on repeat", "in rotation") unless their own review text says so directly.

        \(personaVoiceBlock(for: tone))

        Maximum 55 words total.
        No emojis. No hashtags.
        Never use these words or phrases:
        \(bannedListText(for: tone))
        """
    }

    static func personaPrompt(
        totalLogCount: Int,
        averageRating: Double?,
        topTasteDimensions: [String],
        avoidanceSignals: [String],
        recentLogSummary: String,
        evidenceSnippets: [String],
        tone: SoundPrintPersonaTone
    ) -> String {
        let averageRatingText = averageRating.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? ""
        let topTasteDimensionsText = topTasteDimensions.isEmpty ? "none yet" : topTasteDimensions.joined(separator: ", ")
        let avoidanceSignalsText = avoidanceSignals.isEmpty ? "none yet" : avoidanceSignals.joined(separator: ", ")
        let evidenceSnippetsText = evidenceSnippets.isEmpty ? "none yet" : evidenceSnippets.joined(separator: " | ")

        return """
        Write the SoundPrint note for this listener.

        Total logs: \(totalLogCount)
        Average rating: \(averageRatingText)

        Top positive taste dimensions:
        \(topTasteDimensionsText)

        Avoidance signals:
        \(avoidanceSignalsText)

        Recent log patterns:
        \(recentLogSummary)

        Representative evidence:
        \(evidenceSnippetsText)

        Capture what this listener rewards, what loses them, and what makes their taste theirs.

        Hard rules:
        - Include at least one of the top taste dimensions or avoidance signals word-for-word (if a dimension is "Energy Bias", the text must contain the exact phrase "Energy Bias") — or name a listed album or artist exactly.
        - Do not invent anything not supported by the evidence above.
        - If evidence is thin, keep the claims modest.
        """
    }

    private static func personaVoiceBlock(for tone: SoundPrintPersonaTone) -> String {
        switch tone {
        case .analyst:
            return """
            Voice: a sharp analyst summarizing findings, like a well-written liner note.
            - State observations plainly and precisely.
            - Prefer concrete production, writing, and structure language over feelings.
            - Hedge honestly: "so far", "in these logs", "tends to" — never "always" or "definitely".
            - No jokes, no exclamation points, no pet names.
            - Write your own sentence from the specific dimensions and evidence given below — never reuse the wording, sentence shape, or punctuation pattern of any example elsewhere in these instructions.
            """
        case .balanced:
            return """
            Voice: a sharp friend who actually read your diary.
            - Warm but direct. Lightly opinionated, never gushing.
            - Plain modern language; no music-magazine phrases, no horoscope energy.
            - One observation about what they reward, grounded in one real detail about what loses them.
            - Write your own sentence from the specific dimensions and evidence given below — never reuse the wording, sentence shape, or punctuation pattern of any example elsewhere in these instructions.
            """
        case .wrapped:
            return """
            Voice: end-of-year recap energy — playful, a little dramatic, celebratory.
            - Have fun: bold declarations and playful exaggeration are welcome. At most one exclamation point.
            - Recap-show words like "era" are fine — clichés are part of the bit, as long as the facts underneath are real.
            - Every flex must trace to an actual dimension, album, or review. Tease, don't insult.
            - Write your own sentence from the specific dimensions and evidence given below — never reuse the wording, sentence shape, or punctuation pattern of any example elsewhere in these instructions.
            """
        }
    }

    // MARK: - E/F: Compact SoundPrint Summary

    static func compactSummaryInstructions(tone: SoundPrintPersonaTone) -> String {
        """
        You write a compact SoundPrint summary card for a music diary app: a headline, one sentence, and exactly 3 short bullets.

        Grounded in the supplied dimensions and avoidance signals only. Do not invent claims.
        Speak to the listener as "you"; never say "the user".

        \(compactSummaryVoiceBlock(for: tone))

        Never use these words or phrases:
        \(bannedListText(for: tone))
        """
    }

    static func compactSummaryPrompt(
        topTasteDimensions: [String],
        avoidanceSignals: [String],
        recentChanges: String?,
        tone: SoundPrintPersonaTone
    ) -> String {
        let topTasteDimensionsText = topTasteDimensions.isEmpty ? "none yet" : topTasteDimensions.joined(separator: ", ")
        let avoidanceSignalsText = avoidanceSignals.isEmpty ? "none yet" : avoidanceSignals.joined(separator: ", ")
        let recentChangesText = recentChanges ?? "none"

        return """
        Create a compact SoundPrint summary from this structured profile.

        Top dimensions:
        \(topTasteDimensionsText)

        Avoidance signals:
        \(avoidanceSignalsText)

        Recent shifts:
        \(recentChangesText)

        Rules:
        - Headline: maximum 7 words.
        - Summary: exactly one sentence, maximum 28 words, saying what this listener rewards and/or rejects.
        - Exactly 3 bullets, each concrete and at most 12 words, each tied to a real dimension or signal.
        """
    }

    private static func compactSummaryVoiceBlock(for tone: SoundPrintPersonaTone) -> String {
        switch tone {
        case .analyst:
            return """
            Voice: analytical report.
            - Headline reads like a report title, not a slogan (e.g. "Production Taste Leads, Filler Costs Points").
            - The sentence is a plain finding.
            - Bullets are evidence-style: "Rewards: ...", "Docks: ...", "Trend: ...".
            """
        case .balanced:
            return """
            Voice: plainspoken and specific.
            - Headline is concrete, not horoscope-like.
            - The sentence sounds like a friend's one-line read.
            - Bullets are short concrete observations.
            """
        case .wrapped:
            return """
            Voice: end-of-year recap card.
            - Headline is a fun superlative built on a real dimension (e.g. "Certified Replay Pull Champion").
            - The sentence has recap-show energy, but stays true to the data.
            - Bullets read like awards or stats, each tied to a real signal.
            """
        }
    }

    private static func bannedListText(for tone: SoundPrintPersonaTone) -> String {
        SoundPrintOutputValidator.bannedPhrases(for: tone).joined(separator: ", ")
    }
}
