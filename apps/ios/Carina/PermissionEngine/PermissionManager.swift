import AVFAudio
import Foundation
import Speech

@MainActor
final class PermissionManager: ObservableObject {
    enum Status: String {
        case unknown = "Not requested"
        case authorized = "Authorized"
        case denied = "Denied"
    }

    @Published private(set) var microphone: Status = .unknown
    @Published private(set) var speechRecognition: Status = .unknown

    func refresh() {
        microphone = switch AVAudioApplication.shared.recordPermission {
        case .granted: .authorized
        case .denied: .denied
        case .undetermined: .unknown
        @unknown default: .unknown
        }

        speechRecognition = switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .authorized
        case .denied, .restricted: .denied
        case .notDetermined: .unknown
        @unknown default: .unknown
        }
    }
}
