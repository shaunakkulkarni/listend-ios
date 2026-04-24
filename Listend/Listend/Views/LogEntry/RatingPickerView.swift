//
//  RatingPickerView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI

struct RatingPickerView: View {
    @Binding var rating: Double?

    private let ratings = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0]

    var body: some View {
        Picker("Rating", selection: $rating) {
            Text("Select")
                .tag(Double?.none)

            ForEach(ratings, id: \.self) { rating in
                Text(rating.formatted(.number.precision(.fractionLength(1))))
                    .tag(Double?.some(rating))
            }
        }
    }
}
