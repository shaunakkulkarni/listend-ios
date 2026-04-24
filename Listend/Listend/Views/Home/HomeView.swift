//
//  HomeView.swift
//  Listend
//
//  Created by Shaunak Kulkarni on 4/23/26.
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \LogEntry.loggedAt, order: .reverse) private var logs: [LogEntry]

    var body: some View {
        List {
            if logs.isEmpty {
                ContentUnavailableView(
                    "No Logs Yet",
                    systemImage: "music.note.list",
                    description: Text("Recent album logs will appear here.")
                )
            } else {
                Section("Recent Logs") {
                    ForEach(logs) { log in
                        RecentLogRow(log: log)
                    }
                }
            }
        }
        .navigationTitle("Listend")
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .modelContainer(for: [Album.self, LogEntry.self], inMemory: true)
}
