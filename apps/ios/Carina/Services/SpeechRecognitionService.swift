import AVFAudio
import Foundation
import Speech
import os

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
            logger.error("Speech start failed: \(error.localizedDescription, privacy: .public)")
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
