//
//  IndexView.swift
//  View to manage indexed files (grouped by folder)
//

import SwiftUI
import UniformTypeIdentifiers

struct IndexedFile: Identifiable {
    let id: UUID
    let filePath: URL
    let fileName: String
    let language: String
    let chunkCount: Int
    let fileSize: Int

    var languageFlag: String {
        switch language {
        case "ja": return "🇯🇵"
        case "en": return "🇬🇧"
        case "es": return "🇪🇸"
        case "fr": return "🇫🇷"
        case "de": return "🇩🇪"
        case "zh-Hans": return "🇨🇳"
        case "zh-Hant": return "🇹🇼"
        case "ko": return "🇰🇷"
        case "it": return "🇮🇹"
        case "pt": return "🇵🇹"
        case "nl": return "🇳🇱"
        case "ru": return "🇷🇺"
        default: return "🌐"
        }
    }
}

struct FolderGroup: Identifiable {
    let id = UUID()
    let folderPath: URL
    let folderName: String
    let files: [IndexedFile]

    var totalChunks: Int { files.reduce(0) { $0 + $1.chunkCount } }
    var totalSize: Int { files.reduce(0) { $0 + $1.fileSize } }
}

struct IndexView: View {
    private let indexingService = IndexingService.shared
    @State private var indexedFiles: [IndexedFile] = []
    @State private var folderGroups: [FolderGroup] = []
    @State private var isIndexing = false
    @State private var indexingProgress: Double = 0.0
    @State private var currentlyIndexing: String = ""
    @State private var indexingTask: Task<Void, Never>?

    @State private var showProgress = false
    @State private var stats: (count: Int, totalSize: Int) = (0, 0)
    @State private var statusMessage = "Ready"

    // ETA tracking
    @State private var indexingStartTime: Date?
    @State private var estimatedTimeRemaining: String = ""
    @State private var isDropTargeted = false
    @State private var expandedFolders: Set<String> = []
    @State private var indexingErrors: [IndexingError] = []
    @State private var showErrorSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with actions
            header

            Divider()

            // Progress bar
            if showProgress {
                progressBar
            }

            // Content
            if folderGroups.isEmpty {
                emptyState
            } else {
                folderList
            }
        }
        .background(isDropTargeted ? Color.accentColor.opacity(0.1) : Color.clear)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .task {
            await loadIndexedFiles()
        }
        .onDisappear {
            // Clean up task when view disappears
            indexingTask?.cancel()
            indexingTask = nil
        }
        .sheet(isPresented: $showErrorSheet) {
            ErrorSheetView(errors: indexingErrors, onDismiss: {
                showErrorSheet = false
                Task {
                    await indexingService.clearErrors()
                    indexingErrors = []
                }
            })
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Index")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Stats
                if !folderGroups.isEmpty {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(stats.count) chunks")
                            .font(.caption)
                            .monospacedDigit()
                        Text("\(folderGroups.count) folders • \(uniqueFileCount) files")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                // Index folder button
                if !isIndexing {
                    Button(action: { selectFolder() }) {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                // Reindex button
                if !folderGroups.isEmpty && !isIndexing {
                    Button(action: { reindexAll() }) {
                        Label("Reindex All", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                // Cancel button (when indexing)
                if isIndexing {
                    Button(role: .destructive, action: { cancelIndexing() }) {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                Spacer()

                // Clear button
                if !folderGroups.isEmpty && !isIndexing {
                    Button(role: .destructive, action: { clearIndex() }) {
                        Label("Clear All", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                // Refresh button
                Button(action: { Task { await loadIndexedFiles() } }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isIndexing)

                // Error indicator button
                if !indexingErrors.isEmpty {
                    Button(action: { showErrorSheet = true }) {
                        Label("\(indexingErrors.count)", systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .foregroundStyle(.orange)
                }
            }
        }
        .padding()
    }

    private var progressBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ProgressView(value: indexingProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .frame(maxWidth: .infinity)

                Text("\(Int(indexingProgress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 40)

                if !estimatedTimeRemaining.isEmpty {
                    Text(estimatedTimeRemaining)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            // Status text with file count
            if !currentlyIndexing.isEmpty {
                HStack {
                    Text("Indexing: \(currentlyIndexing)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if indexingProgress > 0 {
                        Text("\(Int(indexingProgress * 100))% complete")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity)
    }

    private var folderList: some View {
        ScrollView {
            LazyVStack(spacing: 8, pinnedViews: []) {
                ForEach(folderGroups) { folder in
                    FolderRowView(
                        folder: folder,
                        isExpanded: expandedFolders.contains(folder.folderPath.path),
                        onToggle: {
                            if expandedFolders.contains(folder.folderPath.path) {
                                expandedFolders.remove(folder.folderPath.path)
                            } else {
                                expandedFolders.insert(folder.folderPath.path)
                            }
                        }
                    )
                }
            }
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Files Indexed")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Click 'Add Folder' or drag & drop a folder here")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Button(action: { selectFolder() }) {
                Label("Add Folder", systemImage: "folder.badge.plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var uniqueFileCount: Int {
        indexedFiles.count
    }

    // MARK: - Actions

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder to index"

        if panel.runModal() == .OK, let url = panel.url {
            indexingTask = Task {
                await indexFolder(url)

                // Clean up task reference on completion
                await MainActor.run {
                    indexingTask = nil
                }
            }
        }
    }

    private func indexFolder(_ url: URL) async {
        // Clear previous errors
        await indexingService.clearErrors()

        // Start indexing
        await MainActor.run {
            isIndexing = true
            showProgress = true
            indexingProgress = 0.0
            currentlyIndexing = url.lastPathComponent
            statusMessage = "Indexing \(url.lastPathComponent)..."
            indexingErrors = []
            indexingStartTime = Date()
            estimatedTimeRemaining = ""
        }

        // Use IndexingService with progress callback
        let indexedCount = await indexingService.indexDirectory(url) { current, total, fileName in
            Task { @MainActor in
                indexingProgress = Double(current) / Double(total)
                currentlyIndexing = fileName

                // Calculate ETA
                if let startTime = self.indexingStartTime, current > 0 {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let rate = Double(current) / elapsed
                    let remaining = Double(total - current)
                    let eta = remaining / rate

                    if eta > 60 {
                        self.estimatedTimeRemaining = String(format: "~%.0fm left", eta / 60)
                    } else if eta > 0 {
                        self.estimatedTimeRemaining = String(format: "~%.0fs left", eta)
                    }
                }
            }
        }

        // Get any errors that occurred
        let errors = await indexingService.getErrors()
        await MainActor.run {
            indexingErrors = errors
        }

        // Complete
        await MainActor.run {
            indexingProgress = 1.0
            currentlyIndexing = ""
            estimatedTimeRemaining = ""
        }

        // Reload the index
        await loadIndexedFiles()
        
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        await MainActor.run {
            showProgress = false
            isIndexing = false
            indexingProgress = 0.0
            if indexingErrors.isEmpty {
                statusMessage = "✅ Indexed \(indexedCount) files"
            } else {
                statusMessage = "⚠️ Indexed \(indexedCount) files (\(indexingErrors.count) errors)"
            }
        }

        // Reset status after 3 seconds
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await MainActor.run {
            statusMessage = "Ready"
        }
    }

    private func reindexAll() {
        indexingTask = Task {
            await MainActor.run {
                isIndexing = true
                showProgress = true
                indexingProgress = 0.0
                statusMessage = "Checking for changes..."
            }

            // Clean up orphaned files (deleted from disk)
            let orphanedCount = await indexingService.cleanupOrphanedFiles()

            // Collect unique folder paths from indexed files
            let folders = Set(indexedFiles.map { $0.filePath.deletingLastPathComponent() })
            var totalIndexed = 0

            // Reindex each folder (incremental - only changed files will be reindexed)
            for (index, folder) in folders.enumerated() {
                // Check for cancellation
                if Task.isCancelled {
                    print("⚠️ Reindexing cancelled by user")
                    return
                }

                await MainActor.run {
                    currentlyIndexing = folder.lastPathComponent
                    indexingProgress = Double(index) / Double(folders.count)
                }

                let count = await indexingService.indexDirectory(folder)
                totalIndexed += count
            }

            // Complete progress
            await MainActor.run {
                indexingProgress = 1.0
                currentlyIndexing = ""
            }

            // Reload the index
            await loadIndexedFiles()

            await MainActor.run {
                showProgress = false
                isIndexing = false
                indexingProgress = 0.0
                if orphanedCount > 0 {
                    statusMessage = "✅ Reindexing complete: \(totalIndexed) files (\(orphanedCount) orphaned removed)"
                } else {
                    statusMessage = "✅ Reindexing complete: \(totalIndexed) files"
                }
            }

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                statusMessage = "Ready"
            }

            // Clean up task reference on completion
            await MainActor.run {
                indexingTask = nil
            }
        }
    }

    private func cancelIndexing() {
        indexingTask?.cancel()
        indexingTask = nil

        showProgress = false
        isIndexing = false
        indexingProgress = 0.0
        currentlyIndexing = ""
        estimatedTimeRemaining = ""
        statusMessage = "❌ Indexing cancelled"

        // Reload the index to show what was actually indexed before cancellation
        Task {
            await loadIndexedFiles()

            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                statusMessage = "Ready"
            }
        }
    }

    private func clearIndex() {
        Task {
            await indexingService.clear()
            await loadIndexedFiles()
            statusMessage = "Index cleared"

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                statusMessage = "Ready"
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (urlData, error) in
            guard let urlData = urlData as? Data,
                  let url = URL(dataRepresentation: urlData, relativeTo: nil) else {
                return
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return
            }

            Task {
                await indexFolder(url)
            }
        }

        return true
    }

    private func loadIndexedFiles() async {
        let files = await indexingService.getIndexedFiles()
        stats = await indexingService.getStats()

        indexedFiles = files.map { entry in
            IndexedFile(
                id: entry.id,
                filePath: entry.filePath,
                fileName: entry.fileName,
                language: entry.language,
                chunkCount: entry.chunkCount,
                fileSize: entry.fileSize
            )
        }

        // Group by folder
        var folderDict: [String: [IndexedFile]] = [:]
        for file in indexedFiles {
            let folderPath = file.filePath.deletingLastPathComponent()
            folderDict[folderPath.path, default: []].append(file)
        }

        folderGroups = folderDict.map { (path, files) in
            let url = URL(fileURLWithPath: path)
            return FolderGroup(
                folderPath: url,
                folderName: url.lastPathComponent,
                files: files.sorted { $0.fileName < $1.fileName }
            )
        }.sorted { $0.folderName < $1.folderName }

        await MainActor.run {
            statusMessage = folderGroups.isEmpty ? "Ready" : "\(folderGroups.count) folders indexed"
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct FolderRowView: View {
    let folder: FolderGroup
    let isExpanded: Bool
    let onToggle: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Folder header
            HStack(spacing: 12) {
                Image(systemName: isExpanded ? "folder.fill" : "folder")
                    .foregroundStyle(.blue)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.folderName)
                        .font(.body)
                        .fontWeight(.semibold)

                    HStack(spacing: 8) {
                        Text(folder.folderPath.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text("•")
                            .foregroundStyle(.secondary)

                        Text("\(folder.files.count) files • \(folder.totalChunks) chunks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(12)
            .background(isHovered ? Color.accentColor.opacity(0.05) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isHovered ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggle()
                }
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }

            // Expanded file list
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(folder.files) { file in
                        FileRowView(file: file)
                            .padding(.leading, 40)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

struct FileRowView: View {
    let file: IndexedFile
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // File Icon
            Image(systemName: fileIcon)
                .foregroundStyle(.secondary)
                .font(.caption)

            // File Info
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.caption)
                    .fontWeight(.medium)

                Text("\(file.chunkCount) chunks • \(formatBytes(file.fileSize))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Open indicator on hover
            if isHovered {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(8)
        .background(isHovered ? Color.accentColor.opacity(0.03) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            NSWorkspace.shared.open(file.filePath)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var fileIcon: String {
        let ext = file.filePath.pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "text.badge.checkmark"
        case "js", "ts": return "doc.text"
        case "txt", "md": return "doc.plaintext"
        case "json", "xml": return "doc.badge.gearshape"
        default: return "doc"
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Error Sheet View

struct ErrorSheetView: View {
    let errors: [IndexingError]
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)

                Text("Indexing Errors")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Error list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(errors) { error in
                        ErrorRowView(error: error)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                Text("\(errors.count) file(s) failed to index")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Dismiss") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 600, height: 400)
    }
}

struct ErrorRowView: View {
    let error: IndexingError

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.badge.exclamationmark")
                    .foregroundStyle(.orange)

                Text(error.fileName)
                    .font(.body)
                    .fontWeight(.medium)

                Spacer()
            }

            Text(error.filePath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(error.errorMessage)
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.top, 2)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
