//
//  ContentView.swift
//  Main app interface with TabView
//

import SwiftUI

enum AppTab: Int, Hashable {
    case search = 0
    case index = 1
    case licenses = 2
    case settings = 3
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .search

    var body: some View {
        if #available(macOS 15.0, *) {
            modernTabView
        } else {
            legacyTabView
        }
    }

    @available(macOS 15.0, *)
    private var modernTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Search", systemImage: "magnifyingglass", value: .search) {
                SearchView()
            }

            Tab("Index", systemImage: "list.bullet.rectangle", value: .index) {
                IndexView()
            }

            Tab("Licenses", systemImage: "doc.text", value: .licenses) {
                LicensesView()
            }

            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .frame(minWidth: 800, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            selectedTab = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .viewIndex)) { _ in
            selectedTab = .index
        }
    }

    private var legacyTabView: some View {
        TabView(selection: Binding(
            get: { selectedTab.rawValue },
            set: { selectedTab = AppTab(rawValue: $0) ?? .search }
        )) {
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(0)

            IndexView()
                .tabItem {
                    Label("Index", systemImage: "list.bullet.rectangle")
                }
                .tag(1)

            LicensesView()
                .tabItem {
                    Label("Licenses", systemImage: "doc.text")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(3)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            selectedTab = .search
        }
        .onReceive(NotificationCenter.default.publisher(for: .viewIndex)) { _ in
            selectedTab = .index
        }
    }
}


