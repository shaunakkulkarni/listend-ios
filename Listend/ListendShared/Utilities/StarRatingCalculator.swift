//
//  StarRatingCalculator.swift
//  Listend
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
