//
//  AlbumPreviewControl.swift
//  Listend
//
//  Created by Codex on 5/5/26.
//

import AVFoundation
import SwiftUI

struct AlbumPreviewControl: View {
    @Environment(\.albumPreviewService) private var previewService

    let lookup: AlbumPreviewLookup

    @State private var state = AlbumPreviewControlState.idle
    @State private var preview: AlbumPreview?
    @State private var player: AVPlayer?
    @State private var loadTask: Task<Void, Never>?
    @State private var endObserver: NSObjectProtocol?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: handleTap) {
                Label(labelText, systemImage: systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(isDisabled)
            .accessibilityIdentifier("albumPreviewButton")
            .accessibilityValue(accessibilityValue)
        }
        .accessibilityIdentifier("albumPreviewState-\(accessibilityValue)")
        .onChange(of: lookup) { _, _ in
            resetForNewLookup()
        }
        .onDisappear {
            cancelLoad()
            stopPlayback()
        }
    }

    private var labelText: String {
        switch state {
        case .idle:
            return "Play preview"
        case .loading:
            return "Loading preview"
        case .available:
            if let preview {
                return "Play preview: \(preview.trackTitle)"
            }

            return "Play preview"
        case .playing:
            return "Pause preview"
        case .unavailable:
            return "Preview unavailable."
        case .failed:
            return "Preview unavailable."
        }
    }

    private var systemImage: String {
        switch state {
        case .idle:
            return "play.circle"
        case .loading:
            return "hourglass"
        case .available:
            return "play.circle"
        case .playing:
            return "pause.circle"
        case .unavailable, .failed:
            return "speaker.slash"
        }
    }

    private var isDisabled: Bool {
        switch state {
        case .idle, .available, .playing:
            return false
        case .loading, .unavailable, .failed:
            return true
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .available:
            return "available"
        case .playing:
            return "playing"
        case .unavailable:
            return "unavailable"
        case .failed:
            return "failed"
        }
    }

    @MainActor
    private func handleTap() {
        switch state {
        case .idle:
            loadTask?.cancel()
            loadTask = Task {
                await loadAndPlayPreview()
            }
        case .available:
            startPlayback()
        case .playing:
            pausePlayback()
        case .loading, .unavailable, .failed:
            break
        }
    }

    @MainActor
    private func loadAndPlayPreview() async {
        let requestedLookup = lookup
        stopPlayback()
        preview = nil
        state = .loading

        do {
            try Task.checkCancellation()
            let loadedPreview = try await previewService.preview(for: lookup)
            try Task.checkCancellation()
            guard requestedLookup == lookup else {
                return
            }

            if let loadedPreview {
                preview = loadedPreview
                state = .available
                startPlayback()
            } else {
                state = .unavailable
            }
        } catch is CancellationError {
            stopPlayback()
        } catch {
            state = .failed
        }
    }

    @MainActor
    private func startPlayback() {
        guard let preview else {
            state = .unavailable
            return
        }

        if player?.currentItem == nil {
            player = AVPlayer(url: preview.previewURL)
            registerPlaybackEndObserver()
        }

        player?.play()
        state = .playing
    }

    @MainActor
    private func pausePlayback() {
        player?.pause()
        state = .available
    }

    @MainActor
    private func stopPlayback() {
        player?.pause()
        removePlaybackEndObserver()
        player = nil

        if preview != nil, state == .playing {
            state = .available
        }
    }

    @MainActor
    private func resetForNewLookup() {
        cancelLoad()
        stopPlayback()
        preview = nil
        state = .idle
    }

    @MainActor
    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
    }

    @MainActor
    private func registerPlaybackEndObserver() {
        removePlaybackEndObserver()
        guard let currentItem = player?.currentItem else {
            return
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: currentItem,
            queue: .main
        ) { _ in
            Task { @MainActor in
                finishPlayback()
            }
        }
    }

    @MainActor
    private func removePlaybackEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    @MainActor
    private func finishPlayback() {
        removePlaybackEndObserver()
        player = nil

        if preview != nil {
            state = .available
        } else {
            state = .idle
        }
    }
}

private enum AlbumPreviewControlState {
    case idle
    case loading
    case available
    case playing
    case unavailable
    case failed
}
