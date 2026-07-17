import SwiftUI

@main
struct CarinaApp: App {
    @StateObject private var settings = BridgeSettings()
    @StateObject private var bridge = BridgeClient()
    @StateObject private var speech = SpeechRecognitionService()
    @StateObject private var permissions = PermissionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(bridge)
                .environmentObject(speech)
                .environmentObject(permissions)
        }
    }
}
