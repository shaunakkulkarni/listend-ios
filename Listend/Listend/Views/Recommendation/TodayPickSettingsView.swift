//
//  TodayPickSettingsView.swift
//  Listend
//

import SwiftUI

struct TodayPickSettingsView: View {
    @AppStorage(TodayPickPreferenceKey.recommendationMode) private var recommendationModeRawValue = TodayPickRecommendationMode.default.rawValue

    var body: some View {
        List {
            Section {
                Picker("Recommendation style", selection: $recommendationModeRawValue) {
                    ForEach(TodayPickRecommendationMode.allCases) { mode in
                        Text(mode.userFacingTitle).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("todayPickRecommendationModePicker")

                Text(selectedMode.userFacingDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("todayPickRecommendationModeDescription")
            } header: {
                Text("Recommendation style")
            }

            Section {
                Text("Changes apply to your next pick. Your current pick won’t change.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("todayPickSettingsNextPickNote")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.listendPaper)
        .navigationTitle("Today’s Pick Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectedMode: TodayPickRecommendationMode {
        TodayPickRecommendationMode(rawValue: recommendationModeRawValue)
    }
}

#Preview {
    NavigationStack {
        TodayPickSettingsView()
    }
}
