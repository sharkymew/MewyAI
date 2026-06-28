import Foundation
import Combine

@MainActor
final class SidebarVisibilityTransitionCoordinator: ObservableObject {
    @Published var showsMainToggleFadeExclusion = true
    @Published var showsSidebarToggleFadeExclusion = false

    private var transitionTask: Task<Void, Never>?

    func prepareForSidebarPresentation(
        delayNanoseconds: UInt64,
        isSidebarVisible: @escaping @MainActor () -> Bool
    ) {
        cancelTransition()
        showsMainToggleFadeExclusion = false
        showsSidebarToggleFadeExclusion = false

        transitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self, !Task.isCancelled, isSidebarVisible() else { return }
            showsSidebarToggleFadeExclusion = true
            transitionTask = nil
        }
    }

    func prepareForSidebarDismissal(
        delayNanoseconds: UInt64,
        isSidebarVisible: @escaping @MainActor () -> Bool
    ) {
        cancelTransition()
        showsSidebarToggleFadeExclusion = false

        transitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard let self, !Task.isCancelled, !isSidebarVisible() else { return }
            showsMainToggleFadeExclusion = true
            transitionTask = nil
        }
    }

    private func cancelTransition() {
        transitionTask?.cancel()
        transitionTask = nil
    }
}
