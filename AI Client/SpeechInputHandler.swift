import Foundation

@MainActor
enum SpeechInputHandler {
    static func toggleRecording(
        controller: SpeechInputController,
        mergeState: inout SpeechInputMergeState,
        currentText: String
    ) {
        if controller.isRecording {
            controller.stopRecording()
            return
        }

        mergeState.reset(baseText: currentText)

        Task {
            await controller.startRecording()
        }
    }

    static func stopRecordingIfNeeded(controller: SpeechInputController) {
        if controller.isRecording {
            controller.stopRecording()
        }
    }

    static func resetMergeState(
        _ mergeState: inout SpeechInputMergeState,
        baseText: String
    ) {
        mergeState.reset(baseText: baseText)
    }

    static func applyTranscript(
        _ transcript: String,
        mergeState: inout SpeechInputMergeState,
        inputDraft: ChatInputDraft
    ) {
        guard let mergedText = mergeState.mergedText(
            for: transcript,
            currentText: inputDraft.text
        ) else { return }
        inputDraft.setText(mergedText)
    }
}
