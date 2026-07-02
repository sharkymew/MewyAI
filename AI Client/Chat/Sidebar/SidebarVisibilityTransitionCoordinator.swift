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
        showsMainToggleFadeExclusion = true
        showsSidebarToggleFadeExclusion = false
    }

    func prepareForSidebarDismissal(
        delayNanoseconds: UInt64,
        isSidebarVisible: @escaping @MainActor () -> Bool
    ) {
        cancelTransition()
        showsMainToggleFadeExclusion = true
        showsSidebarToggleFadeExclusion = false
    }

    private func cancelTransition() {
        transitionTask?.cancel()
        transitionTask = nil
    }
}
