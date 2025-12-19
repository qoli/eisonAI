//
//  ContentView.swift
//  eisonAIView
//
//  Created by 黃佁媛 on 12/19/25.
//

import SwiftUI

#Preview {
    NavigationStackView()
}

struct NavigationStackView: View {
    @State var searchText: String = ""
    @State private var selection: Int = 0
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    Spacer()

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)

                        TextField("Search your library ...", text: $searchText)
                            .focused($isSearchFocused)
                            .submitLabel(.done)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .glassEffect()
                    .padding(.horizontal, isSearchFocused ? 16 : 60) // keyboard open: 16, closed: 60
                    .padding(.bottom, isSearchFocused ? 12 : 0) // keyboard open: 12, closed: 0
                    .animation(.easeInOut(duration: 0.25), value: isSearchFocused)
                }
                VStack {
                    ContentUnavailableView {
                        Label("No Material", systemImage: "tray.fill")
                    } description: {
                        Text("New Materials you receive will appear here.")
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .title) {
                    Picker("", selection: $selection) {
                        Image(systemName: "magnifyingglass").tag(0)
                        Image(systemName: "star").tag(1)
                        Image(systemName: "clock").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }
}
