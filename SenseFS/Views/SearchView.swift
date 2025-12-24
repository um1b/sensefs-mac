//
//  SearchView.swift
//  Search tab view
//

import SwiftUI

struct SearchView: View {
    private let indexingService = IndexingService.shared
    @State private var searchQuery = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @State private var stats: (count: Int, totalSize: Int) = (0, 0)
    @FocusState private var isSearchFocused: Bool
    @State private var searchTask: Task<Void, Never>?
    @State private var totalMatchCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar
                .padding()

            Divider()

            // Content area
            if searchResults.isEmpty && searchQuery.isEmpty {
                emptyState
            } else if searchResults.isEmpty && !searchQuery.isEmpty {
                noResultsView
            } else {
                resultsListView
            }
        }
        .task {
            await loadStats()
        }
        .onAppear {
            isSearchFocused = true
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.title3)

            TextField("Search...", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isSearchFocused)
                .onChange(of: searchQuery) { _, _ in
                    performSearch()
                }
                .onSubmit {
                    // Immediate search on Enter key
                    searchTask?.cancel()
                    Task {
                        await MainActor.run { isSearching = true }
                        let (results, total) = await indexingService.search(query: searchQuery, limit: 20)
                        await MainActor.run {
                            searchResults = results
                            totalMatchCount = total
                            isSearching = false
                        }
                    }
                }

            if isSearching {
                ProgressView()
                    .controlSize(.small)
            } else if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                    searchTask?.cancel()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }

            // Result count with total
            if !searchResults.isEmpty {
                VStack(spacing: 2) {
                    Text("\(searchResults.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    if totalMatchCount > searchResults.count {
                        Text("of \(totalMatchCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(stats.count > 0 ? "Start searching..." : "No files indexed")
                .font(.title3)
                .foregroundStyle(.secondary)

            if stats.count > 0 {
                Text("\(stats.count) chunks ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var noResultsView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No results")
                .font(.title3)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Results List

    private var resultsListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(searchResults) { result in
                    ResultRowView(result: result)
                        .onTapGesture {
                            NSWorkspace.shared.open(result.filePath)
                        }
                }
            }
            .padding()
        }
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchQuery.isEmpty else {
            searchResults = []
            searchTask?.cancel()
            return
        }

        // Cancel any existing search task
        searchTask?.cancel()

        // Debounce search by 300ms
        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            } catch {
                // Task was cancelled, exit early
                return
            }

            // Check if task was cancelled during sleep
            guard !Task.isCancelled else { return }

            await MainActor.run { isSearching = true }

            let (results, total) = await indexingService.search(query: searchQuery, limit: 20)

            // Check again before updating UI
            guard !Task.isCancelled else {
                await MainActor.run { isSearching = false }
                return
            }

            await MainActor.run {
                searchResults = results
                totalMatchCount = total
                isSearching = false
            }
        }
    }

    private func loadStats() async {
        stats = await indexingService.getStats()
    }
}

struct ResultRowView: View {
    let result: SearchResult
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // File icon
            Image(systemName: fileIcon)
                .foregroundStyle(.blue)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(result.displayFileName)
                    .font(.body)
                    .fontWeight(.medium)

                Text(result.filePath.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !result.content.isEmpty {
                    Text(result.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }

            Spacer()

            // Score (max score)
            Text(String(format: "%.2f", result.maxScore))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(scoreColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(scoreColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

            // Open indicator
            if isHovered {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.blue)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(12)
        .background(isHovered ? Color.accentColor.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private var fileIcon: String {
        let ext = result.filePath.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "text.badge.checkmark"
        case "js", "ts": return "doc.text"
        case "txt", "md": return "doc.plaintext"
        case "json", "xml": return "doc.badge.gearshape"
        default: return "doc"
        }
    }

    private var scoreColor: Color {
        switch result.maxScore {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .secondary
        }
    }
}

#Preview {
    SearchView()
        .frame(width: 800, height: 600)
}
