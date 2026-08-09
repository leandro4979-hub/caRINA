import SwiftUI

@main
struct CarinaMacApp: App {
    var body: some Scene {
        WindowGroup("caRINA") {
            TabView {
                LocalConversationView()
                    .tabItem { Label("Conversation", systemImage: "bubble.left.and.bubble.right") }
                LocalModelTestView()
                    .tabItem { Label("Local Test", systemImage: "stethoscope") }
            }
        }
        .defaultSize(width: 680, height: 560)
    }
}
