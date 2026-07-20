import AVFAudio
import Foundation
import Speech
import os

enum PresenceTarget: String, Codable, Equatable, Sendable {
    case assistant
    case background
    case command
}

struct PresenceDecision: Codable, Equatable, Sendable {
    let target: PresenceTarget
    let confidence: Double
    let actionableText: String

    enum CodingKeys: String, CodingKey {
        case target
        case confidence
        case actionableText = "actionable_text"
    }
}

protocol PresenceClassifying: Sendable {
    func classify(transcript: String) -> PresenceDecision
}

struct PresenceClassifier: PresenceClassifying {
    private static let assistantOpeners = [
        "can you ", "could you ", "would you ", "will you ", "please ",
        "help me ", "i need ", "i want ", "let's ", "what ", "when ",
        "where ", "who ", "why ", "how ", "is ", "are ", "do ", "does ",
    ]
    private static let backgroundPhrases = [
        "talking to the cat", "the cat", "rink", "come here", "go over there",
        "tell him", "tell her", "ask him", "ask her", "mom", "dad", "babe",
        "baby", "the kids", "everyone",
    ]
    private static let commandOpeners = [
        "evil run ", "drop the script", "run status check", "run system status",
        "execute ", "launch ", "open shortcut ", "run shortcut ", "stop service ",
        "start service ", "restart service ", "system.", "shortcut.",
    ]
    private static let wakeExpression = try! NSRegularExpression(
        pattern: #"^(?:hey\s+)?(?:carina|karina)\b[\s,:-]*"#,
        options: [.caseInsensitive]
    )
    private static let fillerExpression = try! NSRegularExpression(
        pattern: #"^(?:(?:um+|uh+|erm+|hmm+|like|you know|okay|ok|well|so)\b[\s,.-]*)+"#,
        options: [.caseInsensitive]
    )

    func classify(transcript: String) -> PresenceDecision {
        let normalized = Self.normalizeWhitespace(transcript)
        guard !normalized.isEmpty else {
            return PresenceDecision(target: .background, confidence: 1, actionableText: "")
        }

        let withoutFillers = Self.replacingPrefix(in: normalized, using: Self.fillerExpression)
        let wakeStripped = Self.replacingPrefix(in: withoutFillers, using: Self.wakeExpression)
        let hadWakePhrase = wakeStripped != withoutFillers
        let actionable = wakeStripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actionable.isEmpty else {
            return PresenceDecision(target: .background, confidence: 0.96, actionableText: "")
        }

        let folded = actionable.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if Self.commandOpeners.contains(where: folded.hasPrefix) {
            return PresenceDecision(target: .command, confidence: hadWakePhrase ? 0.99 : 0.94, actionableText: actionable)
        }
        if hadWakePhrase {
            return PresenceDecision(target: .assistant, confidence: 0.99, actionableText: actionable)
        }
        if Self.backgroundPhrases.contains(where: folded.contains),
           !Self.assistantOpeners.contains(where: folded.hasPrefix) {
            return PresenceDecision(target: .background, confidence: 0.9, actionableText: actionable)
        }
        if transcript.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
            || Self.assistantOpeners.contains(where: folded.hasPrefix) {
            return PresenceDecision(target: .assistant, confidence: 0.88, actionableText: actionable)
        }
        if actionable.split(separator: " ").count < 4 {
            return PresenceDecision(target: .background, confidence: 0.68, actionableText: actionable)
        }
        return PresenceDecision(target: .assistant, confidence: 0.62, actionableText: actionable)
    }

    private static func normalizeWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func replacingPrefix(in text: String, using expression: NSRegularExpression) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}

enum VoiceSessionState: String, Equatable, Sendable {
    case idle
    case listening
    case transcribing
    case thinking
    case speaking
    case interrupted
    case failed

    static func resolve(
        isListening: Bool,
        transcript: String,
        isThinking: Bool,
        isSpeaking: Bool,
        wasInterrupted: Bool,
        hasError: Bool
    ) -> VoiceSessionState {
        if hasError { return .failed }
        if wasInterrupted { return .interrupted }
        if isSpeaking { return .speaking }
        if isThinking { return .thinking }
        if isListening { return transcript.isEmpty ? .listening : .transcribing }
        return .idle
    }

    var label: String {
        switch self {
        case .idle: "Ready when you are"
        case .listening: "Listening"
        case .transcribing: "Hearing you"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case .interrupted: "Stopped"
        case .failed: "Needs attention"
        }
    }
}

@MainActor
protocol VoiceSynthesisProvider: AnyObject {
    var isSpeaking: Bool { get }
    var wasInterrupted: Bool { get }
    var errorMessage: String? { get }
    func speak(_ text: String)
    func stop()
    func clearInterruption()
}

@MainActor
final class NativeVoiceSynthesisService: NSObject, ObservableObject, VoiceSynthesisProvider, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var wasInterrupted = false
    @Published private(set) var errorMessage: String?

    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "com.leandrofajardo.carina", category: "VoiceSynthesis")

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        stop(resetInterruption: true)

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .spokenAudio,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Voice audio session failed: \(error.localizedDescription, privacy: .private)")
            return
        }

        let utterance = AVSpeechUtterance(string: String(clean.prefix(16_000)))
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        utterance.pitchMultiplier = 0.98
        errorMessage = nil
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        stop(resetInterruption: false)
    }

    func clearInterruption() {
        wasInterrupted = false
    }

    private func stop(resetInterruption: Bool) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            wasInterrupted = !resetInterruption
        } else if resetInterruption {
            wasInterrupted = false
        }
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false
            self.wasInterrupted = false
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

@MainActor
final class SpeechRecognitionService: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    enum SpeechError: LocalizedError {
        case recognizerUnavailable
        case microphoneDenied
        case speechDenied

        var errorDescription: String? {
            switch self {
            case .recognizerUnavailable: return "Speech recognition is unavailable."
            case .microphoneDenied: return "Microphone access is required."
            case .speechDenied: return "Speech Recognition access is required."
            }
        }
    }

    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var errorMessage: String?

    private let logger = Logger(subsystem: "com.leandrofajardo.carina", category: "Speech")
    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    override init() {
        super.init()
        recognizer?.delegate = self
    }

    func requestPermissions() async throws {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            throw SpeechError.speechDenied
        }

        let microphoneAllowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard microphoneAllowed else {
            throw SpeechError.microphoneDenied
        }
    }

    func start() async {
        guard !isListening else { return }

        do {
            try await requestPermissions()
            try beginRecognition()
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Speech start failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        isListening = false
    }

    private func beginRecognition() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        request = recognitionRequest

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stop()
                    }
                }
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.stop()
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        transcript = ""
        errorMessage = nil
        isListening = true
    }
}
