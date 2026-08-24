import AVFoundation
import Foundation
import os
import WebRTC

final class RealtimeVoiceService: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case requestingSession
        case connecting
        case connected
        case failed(String)

        var label: String {
            switch self {
            case .idle: return "Ready"
            case .requestingPermission: return "Microphone permission"
            case .requestingSession: return "Securing session"
            case .connecting: return "Connecting"
            case .connected: return "Live"
            case .failed(let message): return message
            }
        }

        var isActive: Bool {
            switch self {
            case .requestingPermission, .requestingSession, .connecting, .connected: return true
            case .idle, .failed: return false
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var model = ""
    @Published private(set) var voice = ""
    @Published private(set) var callID: String?
    @Published private(set) var lastEvent = ""

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()

    private let logger = Logger(subsystem: "com.leandrofajardo.carina", category: "RealtimeVoice")
    private let urlSession: URLSession
    private let rtcAudioSession = RTCAudioSession.sharedInstance()
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var localAudioTrack: RTCAudioTrack?

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
        super.init()
    }

    deinit {
        dataChannel?.delegate = nil
        dataChannel?.close()
        peerConnection?.close()
    }

    func connect(using configuration: BridgeConfiguration, bearerToken: String) async {
        disconnect()
        publish(state: .requestingPermission)

        let microphoneGranted = await requestMicrophonePermission()
        guard microphoneGranted else {
            publish(state: .failed("Microphone access is required for Live Voice."))
            return
        }

        do {
            publish(state: .requestingSession)
            let secret = try await requestClientSecret(using: configuration, bearerToken: bearerToken)
            publish(model: secret.model, voice: secret.voice)

            try configureAudioSession()
            let connection = try makePeerConnection()
            peerConnection = connection

            let channelConfiguration = RTCDataChannelConfiguration()
            guard let channel = connection.dataChannel(forLabel: "oai-events", configuration: channelConfiguration) else {
                throw RealtimeVoiceError.dataChannelUnavailable
            }
            channel.delegate = self
            dataChannel = channel

            let audioConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            let source = Self.factory.audioSource(with: audioConstraints)
            let track = Self.factory.audioTrack(with: source, trackId: "carina-audio")
            localAudioTrack = track
            connection.add(track, streamIds: ["carina-realtime"])

            publish(state: .connecting)
            let offer = try await createOffer(on: connection)
            try await setLocalDescription(offer, on: connection)

            let answer = try await exchangeSDP(offer.sdp, ephemeralKey: secret.value)
            publish(callID: answer.callID)
            try await setRemoteDescription(
                RTCSessionDescription(type: .answer, sdp: answer.sdp),
                on: connection
            )
        } catch {
            logger.error("Realtime connection failed: \(error.localizedDescription, privacy: .private)")
            disconnect(keepingFailure: true)
            publish(state: .failed(error.localizedDescription))
        }
    }

    func disconnect() {
        disconnect(keepingFailure: false)
    }

    private func disconnect(keepingFailure: Bool) {
        localAudioTrack?.isEnabled = false
        localAudioTrack = nil
        dataChannel?.delegate = nil
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.close()
        peerConnection = nil
        deactivateAudioSession()
        publish(callID: nil)
        if !keepingFailure {
            publish(state: .idle)
            publish(lastEvent: "")
        }
    }

    private func makePeerConnection() throws -> RTCPeerConnection {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue]
        )
        guard let connection = Self.factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            throw RealtimeVoiceError.peerConnectionUnavailable
        }
        return connection
    }

    private func requestClientSecret(
        using configuration: BridgeConfiguration,
        bearerToken: String
    ) async throws -> ClientSecretResponse {
        let url = try configuration.httpBaseURL.appending(path: "v1/realtime/client-secret")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RealtimeVoiceError.invalidBridgeResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let bridgeError = try? JSONDecoder().decode(BridgeErrorResponse.self, from: data)
            throw RealtimeVoiceError.bridgeRejected(bridgeError?.error ?? "HTTP \(http.statusCode)")
        }
        let secret = try JSONDecoder().decode(ClientSecretResponse.self, from: data)
        guard secret.success, secret.value.count >= 20 else {
            throw RealtimeVoiceError.invalidBridgeResponse
        }
        return secret
    }

    private func exchangeSDP(_ sdp: String, ephemeralKey: String) async throws -> SDPAnswer {
        guard let url = URL(string: "https://api.openai.com/v1/realtime/calls") else {
            throw RealtimeVoiceError.invalidOpenAIURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(ephemeralKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(sdp.utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RealtimeVoiceError.invalidOpenAIResponse
        }
        guard (200..<300).contains(http.statusCode), let answer = String(data: data, encoding: .utf8), !answer.isEmpty else {
            throw RealtimeVoiceError.openAIRejected(http.statusCode)
        }
        let location = http.value(forHTTPHeaderField: "Location")
        let callID = location?.split(separator: "/").last.map(String.init)
        return SDPAnswer(sdp: answer, callID: callID)
    }

    private func createOffer(on connection: RTCPeerConnection) async throws -> RTCSessionDescription {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse,
            ],
            optionalConstraints: nil
        )
        return try await withCheckedThrowingContinuation { continuation in
            connection.offer(for: constraints) { description, error in
                if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: error ?? RealtimeVoiceError.offerFailed)
                }
            }
        }
    }

    private func setLocalDescription(
        _ description: RTCSessionDescription,
        on connection: RTCPeerConnection
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setLocalDescription(description) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private func setRemoteDescription(
        _ description: RTCSessionDescription,
        on connection: RTCPeerConnection
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.setRemoteDescription(description) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func configureAudioSession() throws {
        rtcAudioSession.lockForConfiguration()
        defer { rtcAudioSession.unlockForConfiguration() }
        try rtcAudioSession.setCategory(AVAudioSession.Category.playAndRecord)
        try rtcAudioSession.setMode(AVAudioSession.Mode.voiceChat)
        try rtcAudioSession.setActive(true)
    }

    private func deactivateAudioSession() {
        rtcAudioSession.lockForConfiguration()
        defer { rtcAudioSession.unlockForConfiguration() }
        try? rtcAudioSession.setActive(false)
    }

    private func record(event data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return }
        publish(lastEvent: type)
        if type == "error" {
            logger.error("Realtime server emitted an error event")
        }
    }

    private func publish(state newValue: State) {
        DispatchQueue.main.async { [weak self] in self?.state = newValue }
    }

    private func publish(model: String, voice: String) {
        DispatchQueue.main.async { [weak self] in
            self?.model = model
            self?.voice = voice
        }
    }

    private func publish(callID: String?) {
        DispatchQueue.main.async { [weak self] in self?.callID = callID }
    }

    private func publish(lastEvent: String) {
        DispatchQueue.main.async { [weak self] in self?.lastEvent = lastEvent }
    }
}

extension RealtimeVoiceService: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        publish(lastEvent: "data_channel.\(dataChannel.readyState.rawValue)")
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        record(event: buffer.data)
    }
}

extension RealtimeVoiceService: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .connected, .completed:
            publish(state: .connected)
        case .failed:
            publish(state: .failed("Realtime voice connection failed."))
        case .disconnected:
            publish(state: .failed("Realtime voice connection was interrupted."))
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
        self.dataChannel = dataChannel
    }
}

private struct ClientSecretResponse: Decodable {
    let success: Bool
    let value: String
    let model: String
    let voice: String
    let expiresAt: Double?

    enum CodingKeys: String, CodingKey {
        case success, value, model, voice
        case expiresAt = "expires_at"
    }
}

private struct BridgeErrorResponse: Decodable {
    let error: String
}

private struct SDPAnswer {
    let sdp: String
    let callID: String?
}

private enum RealtimeVoiceError: LocalizedError {
    case dataChannelUnavailable
    case peerConnectionUnavailable
    case invalidBridgeResponse
    case bridgeRejected(String)
    case invalidOpenAIURL
    case invalidOpenAIResponse
    case openAIRejected(Int)
    case offerFailed

    var errorDescription: String? {
        switch self {
        case .dataChannelUnavailable: return "CARINA could not open the Realtime event channel."
        case .peerConnectionUnavailable: return "CARINA could not create a WebRTC connection."
        case .invalidBridgeResponse: return "The CARINA bridge returned an invalid Realtime session."
        case .bridgeRejected(let message): return "CARINA bridge: \(message)"
        case .invalidOpenAIURL: return "The OpenAI Realtime endpoint is invalid."
        case .invalidOpenAIResponse: return "OpenAI returned an invalid WebRTC response."
        case .openAIRejected(let status): return "OpenAI Realtime returned HTTP \(status)."
        case .offerFailed: return "CARINA could not create a WebRTC offer."
        }
    }
}
