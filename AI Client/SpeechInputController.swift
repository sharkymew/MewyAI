import AVFAudio
import Combine
import Foundation
import Speech

@MainActor
final class SpeechInputController: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var didStopIntentionally = false

    func startRecording() async {
        guard !isRecording else { return }

        cancelRecognitionTask()
        transcript = ""
        errorMessage = nil
        didStopIntentionally = false

        guard await requestSpeechAuthorization(),
              await requestMicrophoneAuthorization() else {
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) else {
            errorMessage = "当前语言暂不支持语音识别。"
            return
        }

        guard recognizer.supportsOnDeviceRecognition else {
            errorMessage = "当前设备或语言不支持本机语音识别。"
            return
        }

        guard recognizer.isAvailable else {
            errorMessage = "本机语音识别暂不可用，请稍后再试。"
            return
        }

        do {
            try beginAudioRecognition(with: recognizer)
        } catch {
            cleanupAudioSession()
            errorMessage = "语音输入启动失败：\(error.localizedDescription)"
        }
    }

    func stopRecording() {
        guard isRecording || audioEngine.isRunning else { return }

        didStopIntentionally = true
        isRecording = false
        stopAudioCapture()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.finish()
        cleanupAudioSession()
    }

    func cancelRecording() {
        guard isRecording || audioEngine.isRunning || recognitionTask != nil else { return }

        didStopIntentionally = true
        isRecording = false
        stopAudioCapture()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        cancelRecognitionTask()
        cleanupAudioSession()
    }

    private func requestSpeechAuthorization() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        let resolvedStatus: SFSpeechRecognizerAuthorizationStatus

        if status == .notDetermined {
            resolvedStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { authorizationStatus in
                    continuation.resume(returning: authorizationStatus)
                }
            }
        } else {
            resolvedStatus = status
        }

        switch resolvedStatus {
        case .authorized:
            return true
        case .denied:
            errorMessage = "语音识别权限已关闭，请到系统设置中允许 MewyAI 使用语音识别。"
        case .restricted:
            errorMessage = "当前设备限制了语音识别权限。"
        case .notDetermined:
            errorMessage = "语音识别权限尚未授权。"
        @unknown default:
            errorMessage = "语音识别权限状态不可用。"
        }

        return false
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        let isGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        if !isGranted {
            errorMessage = "麦克风权限已关闭，请到系统设置中允许 MewyAI 使用麦克风。"
        }

        return isGranted
    }

    private func beginAudioRecognition(with recognizer: SFSpeechRecognizer) throws {
        speechRecognizer = recognizer
        speechRecognizer?.delegate = self

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try audioSession.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try audioSession.setActive(true)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let recognizedText = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorDescription = error?.localizedDescription

            Task { @MainActor [weak self] in
                self?.handleRecognitionUpdate(
                    recognizedText: recognizedText,
                    isFinal: isFinal,
                    errorDescription: errorDescription
                )
            }
        }
    }

    private func handleRecognitionUpdate(
        recognizedText: String?,
        isFinal: Bool,
        errorDescription: String?
    ) {
        if let recognizedText,
           !recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            transcript = recognizedText
        }

        if let errorDescription {
            if !didStopIntentionally {
                errorMessage = "语音识别失败：\(errorDescription)"
            }
            finishRecognitionTask()
            return
        }

        if isFinal {
            finishRecognitionTask()
        }
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func finishRecognitionTask() {
        isRecording = false
        stopAudioCapture()
        recognitionRequest = nil
        recognitionTask = nil
        cleanupAudioSession()
        didStopIntentionally = false
    }

    private func cancelRecognitionTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func cleanupAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(false)
    }
}

extension SpeechInputController: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(
        _ speechRecognizer: SFSpeechRecognizer,
        availabilityDidChange available: Bool
    ) {
        guard !available else { return }

        Task { @MainActor [weak self] in
            guard let self, self.isRecording else { return }
            self.cancelRecording()
            self.errorMessage = "本机语音识别暂不可用，请稍后再试。"
        }
    }
}
