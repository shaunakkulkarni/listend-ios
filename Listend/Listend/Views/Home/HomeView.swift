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
    @State private var isShowingNewLog = false

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
                        NavigationLink {
                            LogEntryDetailView(log: log)
                        } label: {
                            RecentLogRow(log: log)
                        }
                    }
                }
            }
        }
        .navigationTitle("Listend")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingNewLog = true
                } label: {
                    Label("Add Log", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingNewLog) {
            LogEntryEditorView()
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .modelContainer(for: [Album.self, LogEntry.self, TasteDimension.self, TasteEvidence.self], inMemory: true)
}
