//
//  SettingsView.swift
//  Settings view for embedding service info
//

import SwiftUI

struct SettingsView: View {
    private let embeddingService = CoreMLEmbeddingService.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var serverStatus: String = "Ready"
    @State private var modelInfo: (dimension: Int, maxLength: Int, isLoaded: Bool)?
    @State private var isChecking = false
    @State private var serverError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            if isChecking {
                ProgressView("Loading model info...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    // Server Status
                    serverStatusCard

                    // Storage Limits
                    storageLimitsCard

                    // Indexing Options
                    indexingOptionsCard

                    Spacer()
                }
                .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .task {
            await checkServerStatus()
        }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.title2)
                .fontWeight(.bold)

            Spacer()

            Button(action: { Task { await checkServerStatus() } }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var storageLimitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "externaldrive.fill")
                    .foregroundStyle(.purple)
                    .font(.title3)

                Text("Storage Limits")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Max File Size")
                            .font(.caption)
                            .fontWeight(.medium)

                        Text("Files larger than this will be skipped during indexing")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(ByteCountFormatter.string(fromByteCount: Int64(settings.maxFileSizeBytes), countStyle: .file))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Max Database Size")
                            .font(.caption)
                            .fontWeight(.medium)

                        Text("Total size limit for all indexed content")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(ByteCountFormatter.string(fromByteCount: Int64(settings.maxDatabaseSizeBytes), countStyle: .file))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var serverStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: modelInfo?.isLoaded == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(modelInfo?.isLoaded == true ? .green : .orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CoreML Model Status")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if modelInfo != nil {
                        Text("multilingual-e5-small • FP16")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(serverError ?? serverStatus)
                            .font(.caption)
                            .foregroundStyle(serverError == nil ? .green : .orange)
                    }
                }

                Spacer()

                if modelInfo?.isLoaded == true {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption2)
                }
            }

            if let modelInfo = modelInfo {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Embedding Dimension:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(modelInfo.dimension)")
                            .font(.caption.monospaced())
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Max Sequence Length:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(modelInfo.maxLength) tokens")
                            .font(.caption.monospaced())
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Compute Units:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Neural Engine + GPU + CPU")
                            .font(.caption.monospaced())
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Model Size:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("225 MB (FP16)")
                            .font(.caption.monospaced())
                            .fontWeight(.medium)
                    }
                }
            }

            if serverError != nil {
                Divider()

                Text("Model not loaded. Check console for errors.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var indexingOptionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.blue)
                    .font(.title3)

                Text("Indexing Options")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $settings.skipCodeFiles) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Skip Code Files")
                            .font(.caption)
                            .fontWeight(.medium)

                        Text("Excludes programming language files (.swift, .py, .js, etc.) from indexing to reduce token usage")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Toggle(isOn: $settings.skipImages) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Skip Images")
                            .font(.caption)
                            .fontWeight(.medium)

                        Text("Excludes image files (.jpg, .png, .heic, etc.) from OCR indexing to reduce processing time")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                if settings.skipCodeFiles || settings.skipImages {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)

                        Text("Excluded files won't appear in indexing or search results")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func checkServerStatus() async {
        isChecking = true
        serverError = nil

        // Get model info directly (CoreML is local, no server connection needed)
        let info = await embeddingService.getModelInfo()

        await MainActor.run {
            modelInfo = info

            if info.isLoaded {
                serverStatus = "CoreML model loaded successfully"
            } else {
                serverError = "Model failed to load"
            }
            isChecking = false
        }
    }
}

#Preview {
    SettingsView()
        .frame(width: 600, height: 500)
}
