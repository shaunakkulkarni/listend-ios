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

    init(providers: [NSItemProvider], finish: @escaping @MainActor () -> Void) {
        _viewModel = StateObject(wrappedValue: ShareLogViewModel(providers: providers, finish: finish))
    }

    var body: some View {
        NavigationStack {
            Form {
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
            .navigationTitle("Log Album")
            .navigationBarTitleDisplayMode(.inline)
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
            }
            .task {
                await viewModel.resolveSharedAlbum()
            }
        }
    }

    @ViewBuilder
    private var albumSection: some View {
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
                .padding(.vertical, 4)
            }
        } else {
            Section("Album") {
                TextField("Title", text: $viewModel.manualTitle)
                    .textInputAutocapitalization(.words)
                TextField("Artist", text: $viewModel.manualArtist)
                    .textInputAutocapitalization(.words)
                TextField("Year", text: $viewModel.manualReleaseYear)
                    .keyboardType(.numberPad)
                TextField("Genre", text: $viewModel.manualGenre)
                    .textInputAutocapitalization(.words)
            }
        }
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
                TextEditor(text: $viewModel.reviewText)
                    .frame(minHeight: 110)
            }

            TextField("Tags", text: $viewModel.tagsText)
                .textInputAutocapitalization(.never)
            TextField("Favorite tracks", text: $viewModel.favoriteTracksText)
                .textInputAutocapitalization(.words)
            TextField("Skips or weaker tracks", text: $viewModel.skipTracksText)
                .textInputAutocapitalization(.words)
            TextField("Standout moment", text: $viewModel.standoutMomentText, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
        }
    }
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
    @Published var isResolving = true
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let providers: [NSItemProvider]
    private let finishAction: @MainActor () -> Void
    private var hasResolved = false

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
        defer { isResolving = false }

        guard let payload = await SharePayloadExtractor.extractPayload(from: providers),
              let link = AppleMusicAlbumLinkParser.parse(payload) else {
            return
        }

        if let albumID = link.albumID,
           let album = await ShareMusicAlbumResolver.albumDetails(id: albumID) {
            resolvedAlbum = album
            return
        }

        manualTitle = link.titleHint ?? ""
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
                favoriteTracksText: favoriteTracksText,
                skipTracksText: skipTracksText,
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

private enum ShareMusicAlbumResolver {
    static func albumDetails(id: String) async -> AlbumSearchResult? {
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

            return AlbumSearchResult(
                id: album.id.rawValue,
                title: album.title,
                artistName: album.artistName,
                releaseYear: album.releaseDate.map { Calendar.current.component(.year, from: $0) },
                genreName: album.genreNames.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                artworkURL: album.artwork?.url(width: 300, height: 300)?.absoluteString
            )
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}

private struct ShareStarRatingControl: View {
    @Binding var rating: Double

    private let starCount = 5
    private let starSize: CGFloat = 32
    private let starSpacing: CGFloat = 8

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: starSpacing) {
                ForEach(1...starCount, id: \.self) { starIndex in
                    Image(systemName: symbolName(for: starIndex))
                        .font(.system(size: starSize, weight: .semibold))
                        .foregroundStyle(symbolName(for: starIndex) == "star" ? Color.secondary : Color.yellow)
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

private enum StarRatingCalculator {
    nonisolated static func rating(atX xPosition: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else {
            return 0.5
        }

        let boundedX = min(max(xPosition, 0), width)
        let rawRating = ceil((Double(boundedX / width) * 10.0)) / 2.0
        return min(max(rawRating, 0.5), 5.0)
    }

    nonisolated static func clamped(_ rating: Double) -> Double {
        min(max((rating * 2.0).rounded() / 2.0, 0.5), 5.0)
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
        .frame(width: 72, height: 72)
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
                    .foregroundStyle(.orange)
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
