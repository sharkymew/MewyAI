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
