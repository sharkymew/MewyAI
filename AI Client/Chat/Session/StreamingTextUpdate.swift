import Foundation

struct StreamingTextUpdate: Equatable {
    let version: Int
    let chunks: [String]
    let resetsText: Bool
    let appendsProgressively: Bool

    init(
        version: Int,
        text: String,
        resetsText: Bool,
        appendsProgressively: Bool = false
    ) {
        self.version = version
        self.chunks = text.isEmpty ? [] : [text]
        self.resetsText = resetsText
        self.appendsProgressively = appendsProgressively
    }

    init(
        version: Int,
        chunks: [String],
        resetsText: Bool,
        appendsProgressively: Bool = false
    ) {
        self.version = version
        self.chunks = chunks.filter { !$0.isEmpty }
        self.resetsText = resetsText
        self.appendsProgressively = appendsProgressively
    }

    static let empty = StreamingTextUpdate(version: 0, text: "", resetsText: true)
}

final class StreamingTextUpdateChannel {
    private var observers: [UUID: (StreamingTextUpdate) -> Void] = [:]
    private(set) var latest = StreamingTextUpdate.empty
    private var version = 0

    func publish(
        chunks: [String],
        resetsText: Bool,
        appendsProgressively: Bool = false
    ) {
        let nonEmptyChunks = chunks.filter { !$0.isEmpty }
        guard resetsText || !nonEmptyChunks.isEmpty else { return }

        version += 1
        latest = StreamingTextUpdate(
            version: version,
            chunks: nonEmptyChunks,
            resetsText: resetsText,
            appendsProgressively: appendsProgressively
        )

        for observer in observers.values {
            observer(latest)
        }
    }

    func addObserver(_ observer: @escaping (StreamingTextUpdate) -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    func removeObserver(_ id: UUID) {
        observers[id] = nil
    }
}
