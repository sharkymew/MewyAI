import Foundation

struct SpeechInputMergeState: Equatable {
    private(set) var baseText = ""
    private(set) var lastTranscript = ""
    private(set) var lastMergedText = ""

    mutating func reset(baseText: String) {
        self.baseText = baseText
        lastTranscript = ""
        lastMergedText = baseText
    }

    mutating func mergedText(
        for transcript: String,
        currentText: String
    ) -> String? {
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            lastTranscript = ""
            lastMergedText = currentText
            return nil
        }

        if lastTranscript.isEmpty {
            if currentText != baseText {
                baseText = currentText
            }
        } else if currentText != lastMergedText {
            baseText = currentText
        }

        let mergedText = Self.mergedText(
            baseText: baseText,
            speechText: trimmedTranscript
        )
        lastTranscript = trimmedTranscript
        lastMergedText = mergedText
        return mergedText
    }

    static func mergedText(baseText: String, speechText: String) -> String {
        let trimmedSpeechText = speechText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSpeechText.isEmpty else { return baseText }
        guard !baseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return trimmedSpeechText
        }

        let needsSeparator = baseText.unicodeScalars.last.map {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        } ?? false
        return baseText + (needsSeparator ? " " : "") + trimmedSpeechText
    }
}
