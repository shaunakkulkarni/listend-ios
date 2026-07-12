//
//  ShareViewController.swift
//  ListendShareExtension
//

import Combine
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

#if canImport(MusicKit)
import MusicKit
#endif

private enum SharePalette {
    static let paper = adaptive(light: 0xF4F1EA, dark: 0x0F141A)
    static let surface = adaptive(light: 0xFFFDF7, dark: 0x181F27)
    static let ink = adaptive(light: 0x171A1F, dark: 0xF3F0EA)
    static let mutedInk = adaptive(light: 0x6D7178, dark: 0xAEB5BE)
    static let hairline = adaptive(light: 0xDDD8CE, dark: 0x2A333D)
    static let accent = adaptive(light: 0x243B53, dark: 0x7FA7C7)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            color(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        installShareLogEditor()
    }

    private func installShareLogEditor() {
        do {
            let schema = ListendModelSchema.schema
            let configuration = ListendSharedStore.productionConfiguration()
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
                .flatMap { $0.attachments ?? [] } ?? []
            let rootView = ShareLogRootView(
                providers: providers,
                finish: { [weak self] in self?.complete() }
            )
            .modelContainer(container)

            embed(UIHostingController(rootView: rootView))
        } catch {
            embed(UIHostingController(rootView: ShareLogSetupErrorView(
                errorMessage: "Listend could not open its shared library.",
                finish: { [weak self] in self?.complete() }
            )))
        }
    }

    private func embed<Content: View>(_ hostingController: UIHostingController<Content>) {
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .systemBackground
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}

private struct ShareLogRootView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: ShareLogViewModel
    @FocusState private var focusedField: ShareFocusField?

    init(providers: [NSItemProvider], finish: @escaping @MainActor () -> Void) {
        _viewModel = StateObject(wrappedValue: ShareLogViewModel(providers: providers, finish: finish))
    }

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isResolving {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Resolving shared album")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                albumSection
                logSection

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSpacing(10)
            .scrollContentBackground(.hidden)
            .background(SharePalette.paper)
            .foregroundStyle(SharePalette.ink)
            .tint(SharePalette.accent)
            .navigationTitle("Log Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SharePalette.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.finish()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        viewModel.save(in: modelContext)
                    } label: {
                        if viewModel.isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!viewModel.canSave)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .task {
                await viewModel.resolveSharedAlbum()
            }
        }
    }

    @ViewBuilder
    private var albumSection: some View {
        Group {
            if let album = viewModel.resolvedAlbum {
                Section("Album") {
                HStack(spacing: 14) {
                    ShareArtworkView(urlString: album.artworkURL)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(album.title)
                            .font(.headline)
                        Text(album.artistName)
                            .foregroundStyle(.secondary)

                        let details = [album.releaseYear.map(String.init), album.genreName]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                            .joined(separator: " - ")
                        if !details.isEmpty {
                            Text(details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
                }
            } else {
                Section("Album") {
                    TextField("Title", text: $viewModel.manualTitle)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .albumTitle)
                    TextField("Artist", text: $viewModel.manualArtist)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .albumArtist)
                    TextField("Year", text: $viewModel.manualReleaseYear)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .albumYear)
                    TextField("Genre", text: $viewModel.manualGenre)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .albumGenre)
                }
            }
        }
        .listRowBackground(SharePalette.paper)
        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
    }

    private var logSection: some View {
        Section("Log") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Rating")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ShareStarRatingControl(rating: $viewModel.rating)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Review")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ZStack(alignment: .topLeading) {
                    if viewModel.reviewText.isEmpty {
                        Text("What did this album leave with you?")
                            .foregroundStyle(SharePalette.mutedInk)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $viewModel.reviewText)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .focused($focusedField, equals: .review)
                        .onChange(of: viewModel.reviewText) { _, _ in
                            viewModel.refreshTagSuggestions()
                        }
                }
                .frame(height: 96)
                .background(SharePalette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(SharePalette.hairline, lineWidth: 1)
                }
            }

            TextField("Tags", text: $viewModel.tagsText)
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .tags)

            if !viewModel.suggestedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.suggestedTags, id: \.self) { tag in
                            Button(tag) {
                                viewModel.addSuggestedTag(tag)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Track highlights")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Track highlight type", selection: $viewModel.trackMode) {
                    ForEach(ShareTrackMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.isLoadingTracks {
                    Label("Loading tracklist…", systemImage: "music.note")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if viewModel.tracks.isEmpty {
                    TextField(
                        viewModel.trackMode == .favorites ? "Favorite tracks" : "Skips or weaker tracks",
                        text: viewModel.manualTrackText
                    )
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .manualTracks)

                    Text("Tracklist unavailable. You can still enter track names manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(viewModel.trackMode.helperText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.tracks) { track in
                        Button {
                            viewModel.toggle(track)
                        } label: {
                            HStack(spacing: 10) {
                                Text(track.displayNumber)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)

                                Text(track.title)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if let duration = track.displayDuration {
                                    Text(duration)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }

                                Image(systemName: viewModel.selectionSymbol(for: track))
                                    .foregroundStyle(viewModel.isSelected(track) ? SharePalette.accent : SharePalette.mutedInk)
                                    .frame(width: 30, height: 30)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(viewModel.accessibilityLabel(for: track))
                    }

                    DisclosureGroup("Can’t find a track?") {
                        TextField(
                            viewModel.trackMode == .favorites ? "Other favorite tracks" : "Other skips or weaker tracks",
                            text: viewModel.manualTrackText
                        )
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .manualTracks)
                    }
                }
            }
            TextField("Standout moment", text: $viewModel.standoutMomentText, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
        }
        .listRowBackground(SharePalette.paper)
        .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
    }
}

private enum ShareFocusField: Hashable {
    case albumTitle
    case albumArtist
    case albumYear
    case albumGenre
    case review
    case tags
    case manualTracks
}

@MainActor
private final class ShareLogViewModel: ObservableObject {
    @Published var resolvedAlbum: AlbumSearchResult?
    @Published var manualTitle: String = ""
    @Published var manualArtist: String = ""
    @Published var manualReleaseYear: String = ""
    @Published var manualGenre: String = ""
    @Published var rating: Double = 0
    @Published var reviewText: String = ""
    @Published var tagsText: String = ""
    @Published var favoriteTracksText: String = ""
    @Published var skipTracksText: String = ""
    @Published var standoutMomentText: String = ""
    @Published var suggestedTags: [String] = []
    @Published var tracks: [ShareTrackCandidate] = []
    @Published var favoriteTrackIDs = Set<String>()
    @Published var skipTrackIDs = Set<String>()
    @Published var trackMode: ShareTrackMode = .favorites
    @Published var isLoadingTracks = false
    @Published var isResolving = true
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let providers: [NSItemProvider]
    private let finishAction: @MainActor () -> Void
    private var hasResolved = false

    var manualTrackText: Binding<String> {
        Binding(
            get: { self.trackMode == .favorites ? self.favoriteTracksText : self.skipTracksText },
            set: { value in
                if self.trackMode == .favorites {
                    self.favoriteTracksText = value
                } else {
                    self.skipTracksText = value
                }
            }
        )
    }

    init(providers: [NSItemProvider], finish: @escaping @MainActor () -> Void) {
        self.providers = providers
        self.finishAction = finish
    }

    var canSave: Bool {
        guard !isSaving, rating > 0 else {
            return false
        }

        if let resolvedAlbum {
            return !resolvedAlbum.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !resolvedAlbum.artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return !manualTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !manualArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func resolveSharedAlbum() async {
        guard !hasResolved else {
            return
        }

        hasResolved = true
        isResolving = true
        isLoadingTracks = true
        defer {
            isResolving = false
            isLoadingTracks = false
        }

        guard let payload = await SharePayloadExtractor.extractPayload(from: providers),
              let link = AppleMusicAlbumLinkParser.parse(payload) else {
            return
        }

        if let albumID = link.albumID,
           let result = await ShareMusicAlbumResolver.albumDetails(id: albumID) {
            apply(result)
            return
        }

        if let albumID = link.albumID,
           let result = await ShareITunesAlbumResolver.albumDetails(
               id: albumID,
               storefront: link.storefront
           ) {
            apply(result)
            return
        }

        manualTitle = link.titleHint ?? ""
    }

    func addSuggestedTag(_ tag: String) {
        let tags = ListTextNormalizer.parsedTags(from: tagsText)
        guard !tags.contains(where: { LocalTagSuggestionEngine.normalized($0) == LocalTagSuggestionEngine.normalized(tag) }) else {
            return
        }
        tagsText = (tags + [tag]).joined(separator: ", ")
        refreshTagSuggestions()
    }

    func toggle(_ track: ShareTrackCandidate) {
        switch trackMode {
        case .favorites:
            if favoriteTrackIDs.remove(track.id) == nil {
                favoriteTrackIDs.insert(track.id)
                skipTrackIDs.remove(track.id)
            }
        case .skips:
            if skipTrackIDs.remove(track.id) == nil {
                skipTrackIDs.insert(track.id)
                favoriteTrackIDs.remove(track.id)
            }
        }
    }

    func isSelected(_ track: ShareTrackCandidate) -> Bool {
        trackMode == .favorites ? favoriteTrackIDs.contains(track.id) : skipTrackIDs.contains(track.id)
    }

    func selectionSymbol(for track: ShareTrackCandidate) -> String {
        switch (trackMode, isSelected(track)) {
        case (.favorites, true): return "heart.fill"
        case (.favorites, false): return "heart"
        case (.skips, true): return "minus.circle.fill"
        case (.skips, false): return "minus.circle"
        }
    }

    func accessibilityLabel(for track: ShareTrackCandidate) -> String {
        "\(track.title), \(isSelected(track) ? "selected" : "not selected") as \(trackMode.title.lowercased())"
    }

    func save(in modelContext: ModelContext) {
        guard canSave else {
            return
        }

        isSaving = true
        errorMessage = nil

        do {
            let draft = ShareExtensionLogDraft(
                album: albumDraft,
                rating: StarRatingCalculator.clamped(rating),
                reviewText: reviewText,
                tagsText: tagsText,
                favoriteTracksText: selectedTrackText(ids: favoriteTrackIDs, manualText: favoriteTracksText),
                skipTracksText: selectedTrackText(ids: skipTrackIDs, manualText: skipTracksText),
                standoutMomentText: standoutMomentText
            )
            _ = try ShareExtensionLogSaver.save(draft, in: modelContext)
            finishAction()
        } catch {
            isSaving = false
            errorMessage = "Listend could not save this log. Please try again."
        }
    }

    func finish() {
        finishAction()
    }

    private var albumDraft: ShareExtensionAlbumDraft {
        if let resolvedAlbum {
            return .resolved(resolvedAlbum)
        }

        return .manual(
            title: manualTitle,
            artistName: manualArtist,
            releaseYear: Int(manualReleaseYear.trimmingCharacters(in: .whitespacesAndNewlines)),
            genreName: manualGenre
        )
    }

    func refreshTagSuggestions() {
        guard let album = resolvedAlbum else { return }
        suggestedTags = LocalTagSuggestionEngine.suggestions(
            albumTitle: album.title,
            artistName: album.artistName,
            genreName: album.genreName,
            releaseYear: album.releaseYear,
            reviewText: reviewText,
            existingTags: ListTextNormalizer.parsedTags(from: tagsText)
        )
    }

    private func selectedTrackText(ids: Set<String>, manualText: String) -> String {
        let selected = tracks.filter { ids.contains($0.id) }.map(\.title)
        let manual = ListTextNormalizer.parsedTrackNames(from: manualText)
        return (selected + manual).joined(separator: ", ")
    }

    private func apply(_ result: ShareResolvedAlbum) {
        resolvedAlbum = result.album
        tracks = result.tracks
        refreshTagSuggestions()
    }
}

private enum SharePayloadExtractor {
    static func extractPayload(from providers: [NSItemProvider]) async -> String? {
        if let url = await firstItem(in: providers, ofType: UTType.url) as? URL {
            return url.absoluteString
        }

        if let url = await firstItem(in: providers, ofType: UTType.url) as? NSURL {
            return url.absoluteString
        }

        if let text = await firstItem(in: providers, ofType: UTType.plainText) as? String {
            return text
        }

        return nil
    }

    private static func firstItem(in providers: [NSItemProvider], ofType type: UTType) async -> NSSecureCoding? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            if let item = try? await provider.loadItem(forTypeIdentifier: type.identifier, options: nil) {
                return item
            }
        }

        return nil
    }
}

private enum ShareTrackMode: String, CaseIterable, Identifiable {
    case favorites
    case skips

    var id: String { rawValue }
    var title: String { self == .favorites ? "Favorites" : "Skips" }
    var helperText: String {
        self == .favorites
            ? "Choose the tracks that stood out most."
            : "Switch tabs to mark weaker tracks."
    }
}

private struct ShareTrackCandidate: Identifiable {
    let id: String
    let title: String
    let trackNumber: Int?
    let discNumber: Int?
    let duration: TimeInterval?
    let returnedOrder: Int

    var displayNumber: String {
        if let trackNumber { return String(trackNumber) }
        return String(returnedOrder + 1)
    }

    var displayDuration: String? {
        guard let duration, duration.isFinite, duration >= 0 else { return nil }
        let seconds = Int(duration.rounded())
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct ShareResolvedAlbum {
    let album: AlbumSearchResult
    let tracks: [ShareTrackCandidate]
}

private enum ShareMusicAlbumResolver {
    static func albumDetails(id: String) async -> ShareResolvedAlbum? {
        #if canImport(MusicKit)
        do {
            let request = MusicCatalogResourceRequest<MusicKit.Album>(
                matching: \.id,
                equalTo: MusicItemID(id)
            )
            let response = try await request.response()
            guard let album = response.items.first else {
                return nil
            }

            let albumResult = AlbumSearchResult(
                id: album.id.rawValue,
                title: album.title,
                artistName: album.artistName,
                releaseYear: album.releaseDate.map { Calendar.current.component(.year, from: $0) },
                genreName: album.genreNames.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                artworkURL: album.artwork?.url(width: 300, height: 300)?.absoluteString
            )

            let tracks: [ShareTrackCandidate]
            do {
                let detailedAlbum = try await album.with([.tracks])
                tracks = (detailedAlbum.tracks ?? []).enumerated().compactMap { offset, track -> ShareTrackCandidate? in
                    guard case .song(let song) = track else { return nil }
                    return ShareTrackCandidate(
                        id: song.id.rawValue,
                        title: song.title,
                        trackNumber: song.trackNumber,
                        discNumber: song.discNumber,
                        duration: song.duration,
                        returnedOrder: offset
                    )
                }
                .sorted {
                    ($0.discNumber ?? 1, $0.trackNumber ?? Int.max, $0.returnedOrder)
                        < ($1.discNumber ?? 1, $1.trackNumber ?? Int.max, $1.returnedOrder)
                }
            } catch {
                tracks = []
            }

            return ShareResolvedAlbum(album: albumResult, tracks: tracks)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

}

private enum ShareITunesAlbumResolver {
    static func albumDetails(id: String, storefront: String?) async -> ShareResolvedAlbum? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "country", value: storefront ?? "us")
        ]

        guard let url = components?.url else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                return nil
            }

            let payload = try JSONDecoder().decode(ShareITunesLookupResponse.self, from: data)
            guard let collection = payload.results.first(where: { $0.wrapperType == "collection" }) else {
                return nil
            }

            let album = AlbumSearchResult(
                id: String(collection.collectionID ?? Int(id) ?? 0),
                title: collection.collectionName ?? "",
                artistName: collection.artistName ?? "",
                releaseYear: collection.releaseDate.flatMap { ISO8601DateFormatter().date(from: $0) }
                    .map { Calendar.current.component(.year, from: $0) },
                genreName: collection.primaryGenreName,
                artworkURL: upgradedArtworkURL(collection.artworkURL100),
            )

            guard !album.title.isEmpty, !album.artistName.isEmpty else { return nil }

            let tracks = payload.results.enumerated().compactMap { offset, item -> ShareTrackCandidate? in
                guard item.wrapperType == "track",
                      item.kind == "song",
                      let trackID = item.trackID,
                      let title = item.trackName else {
                    return nil
                }

                return ShareTrackCandidate(
                    id: String(trackID),
                    title: title,
                    trackNumber: item.trackNumber,
                    discNumber: item.discNumber,
                    duration: item.trackTimeMillis.map { TimeInterval($0) / 1_000 },
                    returnedOrder: offset
                )
            }
            .sorted {
                ($0.discNumber ?? 1, $0.trackNumber ?? Int.max, $0.returnedOrder)
                    < ($1.discNumber ?? 1, $1.trackNumber ?? Int.max, $1.returnedOrder)
            }

            return ShareResolvedAlbum(album: album, tracks: tracks)
        } catch {
            return nil
        }
    }

    private static func upgradedArtworkURL(_ value: String?) -> String? {
        value?
            .replacingOccurrences(of: "100x100bb", with: "600x600bb")
            .replacingOccurrences(of: "100x100-75", with: "600x600-75")
    }
}

private struct ShareITunesLookupResponse: Decodable {
    let results: [ShareITunesLookupItem]
}

private struct ShareITunesLookupItem: Decodable {
    let wrapperType: String?
    let kind: String?
    let collectionID: Int?
    let collectionName: String?
    let artistName: String?
    let releaseDate: String?
    let primaryGenreName: String?
    let artworkURL100: String?
    let trackID: Int?
    let trackName: String?
    let trackNumber: Int?
    let discNumber: Int?
    let trackTimeMillis: Int?

    enum CodingKeys: String, CodingKey {
        case wrapperType, kind, collectionName, artistName, releaseDate, primaryGenreName
        case collectionID = "collectionId"
        case artworkURL100 = "artworkUrl100"
        case trackID = "trackId"
        case trackName, trackNumber, discNumber, trackTimeMillis
    }
}

private struct ShareStarRatingControl: View {
    @Binding var rating: Double

    private let starCount = 5
    private let starSize: CGFloat = 28
    private let starSpacing: CGFloat = 6

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: starSpacing) {
                ForEach(1...starCount, id: \.self) { starIndex in
                    Image(systemName: symbolName(for: starIndex))
                        .font(.system(size: starSize, weight: .semibold))
                        .foregroundStyle(symbolName(for: starIndex) == "star" ? SharePalette.hairline : SharePalette.accent)
                        .frame(width: starSize, height: starSize)
                }
            }

            HStack(spacing: 0) {
                ForEach(1...(starCount * 2), id: \.self) { halfStep in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            rating = Double(halfStep) / 2.0
                        }
                }
            }
        }
        .frame(width: controlWidth, height: starSize)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    rating = StarRatingCalculator.rating(atX: value.location.x, width: controlWidth)
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(rating > 0 ? "\(StarRatingCalculator.clamped(rating), specifier: "%.1f") out of 5" : "No rating selected")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                rating = StarRatingCalculator.clamped(rating + 0.5)
            case .decrement:
                rating = rating <= 0.5 ? 0 : StarRatingCalculator.clamped(rating - 0.5)
            @unknown default:
                break
            }
        }
    }

    private var controlWidth: CGFloat {
        (CGFloat(starCount) * starSize) + (CGFloat(starCount - 1) * starSpacing)
    }

    private func symbolName(for starIndex: Int) -> String {
        let displayedRating = rating > 0 ? StarRatingCalculator.clamped(rating) : 0
        let starValue = Double(starIndex)

        if displayedRating >= starValue {
            return "star.fill"
        }

        if displayedRating >= starValue - 0.5 {
            return "star.leadinghalf.filled"
        }

        return "star"
    }
}


private struct ShareArtworkView: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.secondary.opacity(0.18))
            .overlay(
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            )
    }
}

private struct ShareLogSetupErrorView: View {
    let errorMessage: String
    let finish: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(SharePalette.accent)
                Text(errorMessage)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Log Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: finish)
                }
            }
        }
    }
}
