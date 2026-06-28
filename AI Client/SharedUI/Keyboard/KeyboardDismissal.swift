import SwiftUI
import UIKit

@MainActor
enum KeyboardDismissal {
    static func dismissNowAndDeferred() {
        dismissNow()

        DispatchQueue.main.async {
            dismissNow()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            dismissNow()
        }
    }

    private static func dismissNow() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )

        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .forEach { $0.endEditing(true) }
    }
}

struct KeyboardDismissTapLayer: UIViewRepresentable {
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        context.coordinator.onDismiss = onDismiss
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDismiss = onDismiss

        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: uiView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onDismiss: (() -> Void)?

        private weak var installedWindow: UIWindow?
        private weak var gestureRecognizer: UITapGestureRecognizer?

        func installIfNeeded(from view: UIView) {
            guard let window = view.window,
                  installedWindow !== window else {
                return
            }

            uninstall()

            let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            gestureRecognizer.cancelsTouchesInView = false
            gestureRecognizer.delegate = self
            window.addGestureRecognizer(gestureRecognizer)

            installedWindow = window
            self.gestureRecognizer = gestureRecognizer
        }

        func uninstall() {
            if let gestureRecognizer {
                gestureRecognizer.view?.removeGestureRecognizer(gestureRecognizer)
            }

            installedWindow = nil
            gestureRecognizer = nil
        }

        @objc private func handleTap() {
            onDismiss?()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let touchedView = touch.view else { return true }
            return !touchedView.hasInteractiveKeyboardControlAncestor
        }
    }
}

private extension UIView {
    var hasInteractiveKeyboardControlAncestor: Bool {
        var view: UIView? = self

        while let currentView = view {
            if currentView is UIControl
                || currentView is UITextField
                || currentView is UITextView
                || currentView is UIPickerView {
                return true
            }

            view = currentView.superview
        }

        return false
    }
}
