//
//  SearchView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI

struct SearchView: View {
    var body: some View {
        ContentUnavailableView(
            "Search Coming Soon",
            systemImage: "magnifyingglass",
            description: Text("Mock album search starts in the next phase.")
        )
        .navigationTitle("Search")
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
}
