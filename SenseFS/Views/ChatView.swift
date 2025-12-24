//
//  ChatView.swift
//  RAG-powered chat interface
//

import SwiftUI

struct ChatView: View {
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isResponding: Bool = false
    @State private var currentStreamingResponse: String = ""
    @State private var isFoundationModelsAvailable: Bool = false
    @State private var showingContextSheet: Bool = false
    @State private var selectedMessageContext: [SearchResult]?

    private let ragService = RAGService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Messages area
            if messages.isEmpty {
                emptyStateView
            } else {
                messagesScrollView
            }

            Divider()

            // Input area
            inputView
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            // Check availability on view appear
            isFoundationModelsAvailable = await ragService.getAvailability()
        }
        .sheet(isPresented: $showingContextSheet) {
            if let context = selectedMessageContext {
                ContextSheetView(searchResults: context)
            }
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Chat")
                    .font(.headline)
                    .fontWeight(.semibold)

                HStack(spacing: 6) {
                    Circle()
                        .fill(isFoundationModelsAvailable ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)

                    Text(isFoundationModelsAvailable
                         ? "Apple Intelligence Active"
                         : "Basic Mode (Apple Intelligence unavailable)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: clearChat) {
                Label("Clear Chat", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear conversation history")
            .disabled(messages.isEmpty)
        }
        .padding()
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "message.bubble.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                Text("Start a Conversation")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Ask questions about your indexed documents")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Try asking:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    examplePrompt("What are the main topics in my documents?")
                    examplePrompt("Summarize the key points from the project files")
                    examplePrompt("Find information about [specific topic]")
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func examplePrompt(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(.blue)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Messages Scroll View

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(
                            message: message,
                            onShowContext: {
                                selectedMessageContext = message.retrievedContext
                                showingContextSheet = true
                            }
                        )
                        .id(message.id)
                    }

                    // Loading or streaming response preview
                    if isResponding {
                        if currentStreamingResponse.isEmpty {
                            // Show loading animation while waiting
                            LoadingMessageBubble()
                                .id("loading")
                        } else {
                            // Show streaming response
                            MessageBubble(
                                message: ChatMessage(
                                    content: currentStreamingResponse,
                                    isUser: false
                                ),
                                isStreaming: true
                            )
                            .id("streaming")
                        }
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                // Auto-scroll to bottom when new message arrives
                if let lastMessage = messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: currentStreamingResponse) {
                // Auto-scroll during streaming
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
            .onChange(of: isResponding) {
                // Auto-scroll when loading starts
                if isResponding {
                    withAnimation {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Input View

    private var inputView: some View {
        HStack(spacing: 12) {
            TextField("Ask a question...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .disabled(isResponding)
                .onSubmit {
                    sendMessage()
                }

            Button(action: sendMessage) {
                Image(systemName: isResponding ? "stop.circle.fill" : "paperplane.fill")
                    .font(.title3)
                    .foregroundStyle(isResponding ? .red : .blue)
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding)
            .help(isResponding ? "Stop generation" : "Send message")
        }
        .padding()
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let userMessage = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""

        // Add user message
        messages.append(ChatMessage(content: userMessage, isUser: true))

        // Generate response
        isResponding = true
        currentStreamingResponse = ""

        Task {
            let context = await ragService.generateStreamingResponse(for: userMessage) { token in
                Task { @MainActor in
                    currentStreamingResponse += token
                }
            }

            // Add assistant message
            await MainActor.run {
                messages.append(ChatMessage(
                    content: currentStreamingResponse,
                    isUser: false,
                    retrievedContext: context.isEmpty ? nil : context
                ))
                currentStreamingResponse = ""
                isResponding = false
            }
        }
    }

    private func clearChat() {
        messages.removeAll()
        Task {
            await ragService.resetSession()
        }
    }
}

// MARK: - Loading Message Bubble

struct LoadingMessageBubble: View {
    @State private var animationPhase: CGFloat = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(.blue)

                    HStack(spacing: 6) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Color.blue.opacity(0.6))
                                .frame(width: 8, height: 8)
                                .scaleEffect(
                                    animationPhase == CGFloat(index) ? 1.3 : 1.0
                                )
                                .animation(
                                    .easeInOut(duration: 0.6)
                                        .repeatForever(autoreverses: true)
                                        .delay(Double(index) * 0.2),
                                    value: animationPhase
                                )
                        }
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }

                Text("Thinking...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .onAppear {
            animationPhase = 0
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    var isStreaming: Bool = false
    var onShowContext: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.isUser {
                Spacer()
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                // Message content
                HStack(alignment: .top, spacing: 8) {
                    if !message.isUser {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        if message.isUser {
                            // User messages: plain text
                            Text(message.content)
                                .font(.body)
                                .textSelection(.enabled)
                        } else {
                            // AI messages: render markdown
                            Text(LocalizedStringKey(message.content))
                                .font(.body)
                                .textSelection(.enabled)
                                .tint(.blue) // Color for links
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                    .background(message.isUser
                               ? Color.blue.opacity(0.1)
                               : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                    .overlay {
                        if isStreaming {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        }
                    }
                }

                // Metadata
                HStack(spacing: 8) {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if !message.isUser, let context = message.retrievedContext, !context.isEmpty {
                        Button(action: { onShowContext?() }) {
                            Label("\(context.count) sources", systemImage: "doc.text.magnifyingglass")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    if isStreaming {
                        HStack(spacing: 2) {
                            ForEach(0..<3) { index in
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 4, height: 4)
                                    .opacity(0.3)
                                    .animation(
                                        .easeInOut(duration: 0.6)
                                            .repeatForever()
                                            .delay(Double(index) * 0.2),
                                        value: isStreaming
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, message.isUser ? 12 : 0)
            }

            if !message.isUser {
                Spacer()
            }
        }
    }
}

// MARK: - Context Sheet

struct ContextSheetView: View {
    let searchResults: [SearchResult]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Retrieved Sources")
                    .font(.headline)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Results
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, result in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.blue)

                                Text(result.fileName)
                                    .font(.headline)

                                Spacer()

                                Text(String(format: "%.1f%%", result.score * 100))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(6)
                            }

                            Text(result.filePath.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Text(result.content)
                                .font(.body)
                                .lineLimit(5)
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                        }
                        .padding()
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 500)
    }
}

#Preview {
    ChatView()
        .frame(width: 800, height: 600)
}
