import Foundation
import UIKit
import os
@preconcurrency import UserNotifications

enum BackgroundNotificationLog {
    nonisolated static let logger = Logger(subsystem: "MewyAI", category: "BackgroundNotification")
}

final class AppNotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationPresentationDelegate()

    static func install(center: UNUserNotificationCenter = .current()) {
        center.delegate = shared
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard notification.request.identifier.hasPrefix("background-completion-") else {
            return []
        }

        return [.banner, .list, .sound]
    }
}

@MainActor
final class BackgroundCompletionNotifier {
    private let center: UNUserNotificationCenter
    private var authorizationTask: Task<Void, Never>?

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationIfNeeded() {
        guard authorizationTask == nil else { return }

        authorizationTask = Task { [weak self] in
            guard let self else { return }
            let settings = await center.notificationSettings()
            BackgroundNotificationLog.logger.notice("authorization status at send: \(settings.authorizationStatus.rawValue) (0=notDetermined 1=denied 2=authorized)")
            guard settings.authorizationStatus == .notDetermined else {
                authorizationTask = nil
                return
            }

            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            BackgroundNotificationLog.logger.notice("authorization prompt result: granted=\(granted)")
            authorizationTask = nil
        }
    }

    func deliverCompletionNotification(
        title: String,
        body: String,
        completion: @escaping @MainActor () -> Void
    ) {
        let content = UNMutableNotificationContent()
        content.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        content.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        content.sound = .default

        guard !content.title.isEmpty, !content.body.isEmpty else {
            completion()
            return
        }

        let request = UNNotificationRequest(
            identifier: "background-completion-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.getNotificationSettings { [center] settings in
            guard settings.authorizationStatus.allowsNotificationDelivery else {
                BackgroundNotificationLog.logger.error("skip: not authorized, status=\(settings.authorizationStatus.rawValue) (0=notDetermined 1=denied)")
                Self.completeOnMainActor(completion)
                return
            }

            center.add(request) { error in
                if let error {
                    BackgroundNotificationLog.logger.error("center.add failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    BackgroundNotificationLog.logger.notice("notification scheduled OK")
                }
                Self.completeOnMainActor(completion)
            }
        }
    }

    private nonisolated static func completeOnMainActor(_ completion: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            completion()
        }
    }
}

@MainActor
final class BackgroundCompletionNotificationCoordinator {
    private let notifier: BackgroundCompletionNotifier
    private var pendingNotificationIDs = Set<UUID>()

    init() {
        notifier = BackgroundCompletionNotifier()
    }

    var pendingNotificationCount: Int {
        pendingNotificationIDs.count
    }

    func requestAuthorizationIfNeeded() {
        notifier.requestAuthorizationIfNeeded()
    }

    func deliverCompletionNotificationIfNeeded(
        assistantMessageID: UUID,
        conversationID: UUID,
        privateConversationID: UUID?,
        contentText: String,
        title: String,
        onPendingCountChanged: @escaping @MainActor () -> Void
    ) {
        let applicationState = UIApplication.shared.applicationState
        guard conversationID != privateConversationID else {
            BackgroundNotificationLog.logger.notice("skip: private conversation")
            return
        }
        guard applicationState != .active else {
            BackgroundNotificationLog.logger.notice("skip: app is active at completion")
            return
        }
        guard let summary = AIService.fallbackBackgroundCompletionSummary(from: contentText) else {
            BackgroundNotificationLog.logger.notice("skip: summary is nil for contentText length \(contentText.count)")
            return
        }
        BackgroundNotificationLog.logger.notice("delivering, applicationState=\(applicationState.rawValue) (1=inactive 2=background)")

        pendingNotificationIDs.insert(assistantMessageID)
        onPendingCountChanged()

        notifier.deliverCompletionNotification(title: title, body: summary) { [weak self] in
            guard let self,
                  pendingNotificationIDs.remove(assistantMessageID) != nil else {
                return
            }
            onPendingCountChanged()
        }
    }
}

private extension UNAuthorizationStatus {
    var allowsNotificationDelivery: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}
