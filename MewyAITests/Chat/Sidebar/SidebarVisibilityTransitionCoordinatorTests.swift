import XCTest
@testable import MewyAI

@MainActor
final class SidebarVisibilityTransitionCoordinatorTests: XCTestCase {
    func testPreparingPresentationKeepsMainFadeExclusion() {
        let coordinator = SidebarVisibilityTransitionCoordinator()

        coordinator.prepareForSidebarPresentation(delayNanoseconds: 1_000_000_000) {
            true
        }

        XCTAssertTrue(coordinator.showsMainToggleFadeExclusion)
        XCTAssertFalse(coordinator.showsSidebarToggleFadeExclusion)
    }

    func testPresentationCompletionKeepsMainFadeExclusion() async {
        let coordinator = SidebarVisibilityTransitionCoordinator()

        coordinator.prepareForSidebarPresentation(delayNanoseconds: 1) {
            true
        }

        try? await Task.sleep(nanoseconds: 1_000_000)
        XCTAssertTrue(coordinator.showsMainToggleFadeExclusion)
        XCTAssertFalse(coordinator.showsSidebarToggleFadeExclusion)
    }

    func testDismissalImmediatelyRestoresMainFadeExclusion() {
        let coordinator = SidebarVisibilityTransitionCoordinator()

        coordinator.prepareForSidebarPresentation(delayNanoseconds: 1) {
            true
        }
        coordinator.prepareForSidebarDismissal(delayNanoseconds: 1_000_000_000) {
            false
        }

        XCTAssertTrue(coordinator.showsMainToggleFadeExclusion)
        XCTAssertFalse(coordinator.showsSidebarToggleFadeExclusion)
    }

    func testSupersededPresentationDoesNotShowSidebarFadeExclusion() async {
        let coordinator = SidebarVisibilityTransitionCoordinator()

        coordinator.prepareForSidebarPresentation(delayNanoseconds: 1_000_000) {
            true
        }
        coordinator.prepareForSidebarDismissal(delayNanoseconds: 1) {
            false
        }

        try? await Task.sleep(nanoseconds: 2_000_000)
        XCTAssertFalse(coordinator.showsSidebarToggleFadeExclusion)
        XCTAssertTrue(coordinator.showsMainToggleFadeExclusion)
    }
}
