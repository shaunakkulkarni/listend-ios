//
//  AlbumArtworkView.swift
//  Listend
//
//  Created by Codex on 5/5/26.
//

import SwiftUI

struct AlbumArtworkView: View {
    let artworkURL: String?
    let size: CGFloat
    var albumTitle: String? = nil

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                            .overlay {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityLabel(accessibilityLabel)
    }

    private var url: URL? {
        artworkURL.flatMap(URL.init(string:))
    }

    private var cornerRadius: CGFloat {
        min(size * 0.22, ListendRadius.artwork)
    }

    private var accessibilityLabel: String {
        guard let albumTitle, !albumTitle.isEmpty else {
            return "Album artwork"
        }

        return "Album artwork for \(albumTitle)"
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.listendAccentSoft)

            Image(systemName: "opticaldisc")
                .font(.system(size: size * 0.4))
                .foregroundStyle(Color.listendAccent.opacity(0.6))
        }
    }
}
