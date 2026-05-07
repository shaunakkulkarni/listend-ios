//
//  StarRatingControl.swift
//  Listend
//
//  Created by Codex on 5/6/26.
//

import SwiftUI

enum StarRatingCalculator {
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

struct StarRatingControl: View {
    @Binding private var rating: Double
    private let showsEmptyState: Bool

    private let starCount = 5
    private let starSize: CGFloat = 32
    private let starSpacing: CGFloat = 8

    init(rating: Binding<Double>, showsEmptyState: Bool = false) {
        _rating = rating
        self.showsEmptyState = showsEmptyState
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())

            HStack(spacing: starSpacing) {
                ForEach(1...starCount, id: \.self) { starIndex in
                    Image(systemName: symbolName(for: starIndex))
                        .font(.system(size: starSize, weight: .semibold))
                        .foregroundStyle(color(for: starIndex))
                        .frame(width: starSize, height: starSize)
                }
            }

            HStack(spacing: 0) {
                ForEach(1...(starCount * 2), id: \.self) { halfStep in
                    if exposesUITestingStepControls {
                        Button {
                            rating = Double(halfStep) / 2.0
                        } label: {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Set rating \(ratingLabel(for: Double(halfStep) / 2.0))")
                        .accessibilityIdentifier("starRatingStep-\(ratingLabel(for: Double(halfStep) / 2.0))")
                    } else {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                rating = Double(halfStep) / 2.0
                            }
                        }
                }
            }
        }
        .frame(width: controlWidth, height: starSize)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    updateRating(at: value.location.x, width: controlWidth)
                }
        )
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .local)
                .onEnded { value in
                    updateRating(at: value.location.x, width: controlWidth)
                }
        )
        .accessibilityElement(children: exposesUITestingStepControls ? .contain : .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            adjustRating(direction)
        }
        .accessibilityIdentifier("starRatingControl")
    }

    private var controlWidth: CGFloat {
        (CGFloat(starCount) * starSize) + (CGFloat(starCount - 1) * starSpacing)
    }

    private var displayedRating: Double {
        showsEmptyState ? 0 : StarRatingCalculator.clamped(rating)
    }

    private var exposesUITestingStepControls: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
    }

    private var accessibilityValue: String {
        if showsEmptyState {
            return "No rating selected"
        }

        return "\(ratingLabel(for: StarRatingCalculator.clamped(rating))) out of 5"
    }

    private func symbolName(for starIndex: Int) -> String {
        let starValue = Double(starIndex)

        if displayedRating >= starValue {
            return "star.fill"
        }

        if displayedRating >= starValue - 0.5 {
            return "star.leadinghalf.filled"
        }

        return "star"
    }

    private func color(for starIndex: Int) -> Color {
        symbolName(for: starIndex) == "star" ? Color.secondary.opacity(0.55) : Color.accentColor
    }

    private func ratingLabel(for value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func updateRating(at xPosition: CGFloat, width: CGFloat) {
        rating = StarRatingCalculator.rating(atX: xPosition, width: width)
    }

    private func adjustRating(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            rating = StarRatingCalculator.clamped((showsEmptyState ? 0 : rating) + 0.5)
        case .decrement:
            rating = StarRatingCalculator.clamped((showsEmptyState ? 0.5 : rating) - 0.5)
        @unknown default:
            break
        }
    }
}
