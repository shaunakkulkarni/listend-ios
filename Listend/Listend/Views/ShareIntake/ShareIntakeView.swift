//
//  ShareIntakeView.swift
//  Listend
//

import SwiftUI
import SwiftData
import UIKit

struct ShareIntakeView: View {
    private enum IntakePhase: Equatable {
        case input
        case resolving
        case resolved(AlbumSearchResult)
        case needsManualSearch
    }

    private let catalogService: AlbumCatalogServiceProtocol
    private let intakeService: AppleMusicShareIntakeService
    private let autoResolveOnAppear: Bool

    @Environment(\.dismiss) private var dismiss

    @State private var linkText: String
    @State private var phase: IntakePhase = .input
    @State private var fallbackQuery = ""
    @State private var fallbackResults: [AlbumSearchResult] = []
    @State private var isSearchingFallback = false
    @State private var fallbackErrorMessage: String?
    @State private var hasAutoResolved = false

    init(
        catalogService: AlbumCatalogServiceProtocol = MockAlbumCatalogService(),
        prefilledText: String = "",
        autoResolveOnAppear: Bool = false
    ) {
        self.catalogService = catalogService
        self.intakeService = AppleMusicShareIntakeService(catalogService: catalogService)
        self.autoResolveOnAppear = autoResolveOnAppear
        _linkText = State(initialValue: prefilledText)
    }

    var body: some View {
        NavigationStack {
            List {
                linkInputSection

                switch phase {
                case .input:
                    EmptyView()
                case .resolving:
                    resolvingSection
                case .resolved(let album):
                    resolvedSection(album: album)
                case .needsManualSearch:
                    fallbackSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.listendPaper)
            .navigationTitle("Import from Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("shareIntakeDoneButton")
                }
            }
            .task(id: fallbackQuery) {
                await runDebouncedFallbackSearch()
            }
            .onAppear(perform: autoResolveIfNeeded)
        }
    }

    /// Kicks off resolution automatically when opened from the share sheet.
    /// Runs at most once per sheet presentation via `hasAutoResolved`, so returning
    /// from a pushed album detail does not re-trigger it.
    private func autoResolveIfNeeded() {
        guard autoResolveOnAppear, !hasAutoResolved else {
            return
        }

        hasAutoResolved = true

        guard !trimmedLinkText.isEmpty else {
            return
        }

        importLink()
    }

    private var linkInputSection: some View {
        Section {
            TextField("Paste an Apple Music album link", text: $linkText, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("shareIntakeLinkField")

            HStack {
                Button {
                    if let pasted = UIPasteboard.general.string {
                        linkText = pasted
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("shareIntakePasteButton")

                Spacer()

                Button {
                    importLink()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedLinkText.isEmpty || phase == .resolving)
                .accessibilityIdentifier("shareIntakeImportButton")
            }
        } footer: {
            Text("Works with Apple Music album links, like music.apple.com/us/album/…")
        }
    }

    private var resolvingSection: some View {
        Section {
            HStack {
                Spacer()
                ProgressView("Looking up album")
                    .accessibilityIdentifier("shareIntakeResolvingIndicator")
                Spacer()
            }
        }
    }

    private func resolvedSection(album: AlbumSearchResult) -> some View {
        Section("Match Found") {
            NavigationLink {
                AlbumDetailView(album: album)
            } label: {
                ShareIntakeAlbumRow(album: album)
            }
            .accessibilityIdentifier("shareIntakeResolvedResult")
        }
    }

    private var fallbackSection: some View {
        Section {
            TextField("Album or artist", text: $fallbackQuery)
                .accessibilityIdentifier("shareIntakeFallbackSearchField")

            if isSearchingFallback {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let fallbackErrorMessage {
                Text(fallbackErrorMessage)
                    .foregroundStyle(.secondary)
            } else if fallbackResults.isEmpty && !trimmedFallbackQuery.isEmpty {
                Text("No albums found. Try another album or artist.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(fallbackResults) { album in
                    NavigationLink {
                        AlbumDetailView(album: album)
                    } label: {
                        ShareIntakeAlbumRow(album: album)
                    }
                    .accessibilityIdentifier("shareIntakeFallbackResult-\(album.catalogID)")
                }
            }
        } header: {
            Text("Search Instead")
        } footer: {
            Text("We couldn't match that link, but you can find the album by searching.")
        }
    }

    private var trimmedLinkText: String {
        linkText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedFallbackQuery: String {
        fallbackQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func importLink() {
        let input = trimmedLinkText

        guard !input.isEmpty else {
            return
        }

        phase = .resolving

        Task {
            let result = await intakeService.resolve(input)

            switch result {
            case .resolved(let album):
                phase = .resolved(album)
            case .needsManualSearch(let suggestedQuery):
                fallbackResults = []
                fallbackErrorMessage = nil
                fallbackQuery = suggestedQuery
                phase = .needsManualSearch
            }
        }
    }

    private func runDebouncedFallbackSearch() async {
        guard phase == .needsManualSearch else {
            return
        }

        let query = trimmedFallbackQuery

        guard !query.isEmpty else {
            fallbackResults = []
            isSearchingFallback = false
            fallbackErrorMessage = nil
            return
        }

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else {
            return
        }

        isSearchingFallback = true
        fallbackErrorMessage = nil

        do {
            let results = try await catalogService.searchAlbums(query: query)
            guard query == trimmedFallbackQuery else {
                return
            }

            fallbackResults = results
            isSearchingFallback = false
        } catch is CancellationError {
            if query == trimmedFallbackQuery {
                isSearchingFallback = false
            }
        } catch {
            guard query == trimmedFallbackQuery else {
                return
            }

            fallbackResults = []
            isSearchingFallback = false
            fallbackErrorMessage = "Could not search albums right now. Try again in a moment."
        }
    }
}

private struct ShareIntakeAlbumRow: View {
    let album: AlbumSearchResult

    var body: some View {
        HStack(spacing: 12) {
            AlbumArtworkView(artworkURL: album.artworkURL, size: 56, albumTitle: album.title)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(album.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if let releaseYear = album.releaseYear {
                        Text(String(releaseYear))
                    }

                    if let genreName = album.genreName {
                        Text(genreName)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ShareIntakeView()
        .modelContainer(for: ListendModelSchema.modelTypes, inMemory: true)
        .environment(SoundPrintProfileRefreshCoordinator())
}
