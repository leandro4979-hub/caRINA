import Foundation
import Network
import os

@MainActor
final class BridgeClient: ObservableObject {
    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        var label: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting"
            case .connected: return "Connected"
            case .failed(let message): return message
            }
        }
    }

    @Published private(set) var state: ConnectionState = .disconnected
    @Published private(set) var lastMessage = ""
    @Published private(set) var realtimeSidebandStatus = "Detached"

    private let logger = Logger(subsystem: "com.leandrofajardo.carina", category: "BridgeClient")
    private let session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    deinit {
        receiveTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
    }

    func connect(using configuration: BridgeConfiguration, bearerToken: String) async {
        disconnect()
        state = .connecting

        do {
            let healthURL = try configuration.httpBaseURL.appending(path: "health")
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 8
            if !bearerToken.isEmpty {
                request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            }
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let socketURL = try configuration.webSocketURL
            var socketRequest = URLRequest(url: socketURL)
            socketRequest.timeoutInterval = 8
            socketRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
            let socket = session.webSocketTask(with: socketRequest)
            webSocketTask = socket
            socket.resume()
            state = .connected
            logger.info("Connected to CARINA bridge")
            startReceiving(from: socket)
        } catch {
            logger.error("Bridge connection failed: \(error.localizedDescription, privacy: .private)")
            state = .failed(error.localizedDescription)
        }
    }

    func send(command: String) async {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let socket = webSocketTask, state == .connected else {
            state = .failed("Connect to the Mac bridge first.")
            return
        }

        do {
            let payload = try JSONEncoder().encode(CommandEnvelope(command: trimmed))
            guard let text = String(data: payload, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }
            try await socket.send(.string(text))
        } catch {
            logger.error("Command send failed: \(error.localizedDescription, privacy: .private)")
            state = .failed(error.localizedDescription)
        }
    }

    func attachRealtime(callID: String) async throws {
        guard callID.hasPrefix("rtc_"), callID.count <= 204 else {
            throw URLError(.badURL)
        }
        guard let socket = webSocketTask, state == .connected else {
            realtimeSidebandStatus = "Bridge offline"
            throw URLError(.notConnectedToInternet)
        }

        let payload = try JSONEncoder().encode(RealtimeAttachEnvelope(callID: callID))
        guard let text = String(data: payload, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        realtimeSidebandStatus = "Attaching"
        do {
            try await socket.send(.string(text))
        } catch {
            realtimeSidebandStatus = "Attach failed"
            logger.error("Realtime sideband attach failed: \(error.localizedDescription, privacy: .private)")
            throw error
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        state = .disconnected
        realtimeSidebandStatus = "Detached"
    }

    private func startReceiving(from socket: URLSessionWebSocketTask) {
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    let text: String
                    switch message {
                    case .string(let value):
                        text = value
                    case .data(let data):
                        text = String(decoding: data, as: UTF8.self)
                    @unknown default:
                        text = "Unsupported bridge message"
                    }
                    lastMessage = text
                    updateRealtimeStatus(from: text)
                } catch {
                    guard !Task.isCancelled else { return }
                    logger.error("WebSocket receive failed: \(error.localizedDescription, privacy: .private)")
                    state = .failed(error.localizedDescription)
                    realtimeSidebandStatus = "Disconnected"
                    return
                }
            }
        }
    }

    private func updateRealtimeStatus(from text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return }

        switch type {
        case "realtime_sideband":
            if let status = object["status"] as? String {
                realtimeSidebandStatus = status.capitalized
            }
        case "realtime_sideband_event":
            if realtimeSidebandStatus != "Connected" {
                realtimeSidebandStatus = "Connected"
            }
        default:
            break
        }
    }
}

private struct CommandEnvelope: Encodable {
    let type = "command"
    let command: String
}

private struct RealtimeAttachEnvelope: Encodable {
    let type = "realtime_attach"
    let callID: String

    enum CodingKeys: String, CodingKey {
        case type
        case callID = "call_id"
    }
}
