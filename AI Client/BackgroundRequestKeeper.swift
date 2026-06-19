import Foundation
import SwiftUI
import UIKit

@MainActor
final class BackgroundRequestKeeper {
    private var taskIdentifier: UIBackgroundTaskIdentifier = .invalid

    func update(
        activeRequestCount: Int,
        isSceneBackgrounded: Bool,
        expirationHandler: @escaping @MainActor () -> Void
    ) {
        guard activeRequestCount > 0, isSceneBackgrounded else {
            end()
            return
        }

        guard taskIdentifier == .invalid else { return }

        taskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "AIClient.ActiveRequests") { [weak self] in
            Task { @MainActor in
                expirationHandler()
                self?.end()
            }
        }
    }

    func end() {
        guard taskIdentifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskIdentifier)
        taskIdentifier = .invalid
    }
}
