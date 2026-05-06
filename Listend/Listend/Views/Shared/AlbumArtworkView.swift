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
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Album artwork")
    }

    private var url: URL? {
        artworkURL.flatMap(URL.init(string:))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.secondary.opacity(0.14))

            Image(systemName: "record.circle")
                .font(.system(size: size * 0.42))
                .foregroundStyle(.secondary)
        }
    }
}
