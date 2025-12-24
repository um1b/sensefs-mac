//
//  ProgressAnimationTestView.swift
//  Preview and test view for progress bar animations
//

import SwiftUI

struct ProgressAnimationTestView: View {
    // Standalone animation state (not dependent on IndexView)
    enum TestProgressState {
        case hidden
        case indexing
        case atHundred
        case success
        case fadingOut
    }

    @State private var progressState: TestProgressState = .hidden
    @State private var indexingProgress: Double = 0.0
    @State private var currentlyIndexing: String = ""
    @State private var progressAnimationID = UUID()

    // Morphing animation dimensions
    @State private var morphWidth: CGFloat = 400  // Start wide
    @State private var morphHeight: CGFloat = 8   // Start thin
    @State private var isCircle:Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("Progress Animation Tester")
                .font(.title2)
                .fontWeight(.bold)
                .padding()

            Divider()

            // Preview area
            VStack {
                if progressState != .hidden {
                    progressBarOrSuccess
                } else {
                    Text("Click 'Start Indexing' to see animation")
                        .foregroundStyle(.secondary)
                        .frame(height: 70)
                }
            }
            .padding(.vertical, 20)

            Divider()

            // Controls
            VStack(spacing: 16) {
                Text("Current State: \(stateDescription)")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button("Start Indexing") {
                            startAnimation()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Skip to 100%") {
                            withAnimation(.none) {
                                progressState = .atHundred
                                indexingProgress = 1.0
                                currentlyIndexing = ""
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(progressState == .hidden)

                        Button("Show Success") {
                            withAnimation(.spring(response: 1.0, dampingFraction: 0.9)) {
                                progressState = .success
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(progressState == .hidden)
                    }

                    HStack(spacing: 12) {
                        Button("Fade Out") {
                            withAnimation(.easeOut(duration: 1.0)) {
                                progressState = .fadingOut
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(progressState != .success)

                        Button("Reset") {
                            progressState = .hidden
                            indexingProgress = 0.0
                            currentlyIndexing = ""
                            // morphWidth will be recaptured on next animation
                            morphHeight = 8
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                }
            }
            .padding()
        }
        .frame(width: 700, height: 400)
    }

    private var stateDescription: String {
        switch progressState {
        case .hidden: return "Hidden"
        case .indexing: return "Indexing (\(Int(indexingProgress * 100))%)"
        case .atHundred: return "At 100%"
        case .success: return "Success"
        case .fadingOut: return "Fading Out"
        }
    }

    private func startAnimation() {
        progressState = .indexing
        indexingProgress = 0.0
        currentlyIndexing = "test_file.txt"
        isCircle = false

        // Reset morph height to initial state
        // morphWidth will be captured from geometry when transitioning to atHundred
        morphHeight = 8

        // Simulate progress
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            if indexingProgress < 1.0 {
                withAnimation(.linear(duration: 0.05)) {
                    indexingProgress += 0.02
                }
            } else {
                timer.invalidate()

                // Wait for the animation to reach 100% smoothly
                // The linear animation takes 0.05s, so we wait a bit longer
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    progressState = .atHundred

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        // Fade out and offset upward
                        withAnimation(.easeOut(duration: 1.0)) {
                            progressState = .fadingOut
                        }

                        // Wait for fade to complete, then reset
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            progressState = .hidden
                            indexingProgress = 0.0
                            currentlyIndexing = ""
                        }
                    }
                }
            }
        }
    }

    private var progressBarOrSuccess: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width - 80

            VStack(spacing: 8) {
                // Main progress/success area
                ZStack {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)

                        morphingElement(width: availableWidth)

                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 32)
                .onChange(of: progressState) { oldValue, newValue in
                    // When transitioning to atHundred, capture the actual width
                    if newValue == .atHundred && oldValue == .indexing {
                        morphWidth = availableWidth
                    }
                }

                // Status text (only during indexing)
                if !currentlyIndexing.isEmpty && progressState == .indexing {
                    Text("Indexing: \(currentlyIndexing)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .frame(maxWidth: .infinity)
            .opacity(progressState == .fadingOut ? 0 : 1)
            .offset(y: progressState == .fadingOut ? -20 : 0)
        }
        .frame(height: 70)
    }

    @ViewBuilder
    private func morphingElement(width actualWidth: CGFloat) -> some View {
        switch progressState {
        case .hidden:
            EmptyView()

        case .indexing:
            // Standard progress bar
            HStack(spacing: 8) {
                ProgressView(value: indexingProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .frame(maxWidth: .infinity)
                    .animation(.linear(duration: 0.05), value: indexingProgress)

                Text("\(Int(indexingProgress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 40)
            }

        case .atHundred:
            // Blue line at 100%
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: morphHeight / 2)
                    .fill(Color.blue)
                    .frame(width: morphWidth, height: morphHeight)

                Text("100%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(width: 40)
            }

        case .success:
            EmptyView()

        case .fadingOut:
            // Blue line at 100% - fading out
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: morphHeight / 2)
                    .fill(Color.blue)
                    .frame(width: morphWidth, height: morphHeight)

                Text("100%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(width: 40)
            }
        }
    }
}

#Preview("Animation Test") {
    ProgressAnimationTestView()
}
