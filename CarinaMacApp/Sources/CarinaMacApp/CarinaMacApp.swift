import SwiftUI

@main
struct CarinaMacApp: App {
    var body: some Scene {
        WindowGroup("caRINA 0.4.0") {
            TabView {
                CarinaTerminalView()
                    .tabItem { Label("Terminal", systemImage: "apple.terminal") }
                LocalConversationView()
                    .tabItem { Label("Conversation", systemImage: "bubble.left.and.bubble.right") }
                LocalModelTestView()
                    .tabItem { Label("Local Test", systemImage: "stethoscope") }
            }
        }
        .defaultSize(width: 980, height: 680)
    }
}
