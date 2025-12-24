import SwiftUI

@main
struct SenseFSApp: App {
    @State private var selectedTab = 0

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandGroup(after: .newItem) {
                Button("Focus Search") {
                    NotificationCenter.default.post(name: .focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("View Index") {
                    NotificationCenter.default.post(name: .viewIndex, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Divider()
            }
        }
    }
}

extension Notification.Name {
    static let focusSearch = Notification.Name("focusSearch")
    static let viewIndex = Notification.Name("viewIndex")
}
