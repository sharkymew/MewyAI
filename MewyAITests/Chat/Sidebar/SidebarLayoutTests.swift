import XCTest
@testable import MewyAI

@MainActor
final class SidebarLayoutTests: XCTestCase {
    func testPhoneUsesOverlaySidebarWidth() {
        let layout = SidebarLayout.layout(
            for: CGSize(width: 390, height: 844),
            userInterfaceIdiom: .phone
        )

        XCTAssertFalse(layout.usesPersistentSidebar)
        XCTAssertEqual(layout.sidebarWidth, 280.8, accuracy: 0.001)
        XCTAssertEqual(layout.mainContentWidth, 390, accuracy: 0.001)
    }

    func testOverlaySidebarWidthIsCapped() {
        let layout = SidebarLayout.layout(
            for: CGSize(width: 800, height: 600),
            userInterfaceIdiom: .phone
        )

        XCTAssertFalse(layout.usesPersistentSidebar)
        XCTAssertEqual(layout.sidebarWidth, 320, accuracy: 0.001)
    }

    func testPadLandscapeUsesPersistentSidebarWidth() {
        let layout = SidebarLayout.layout(
            for: CGSize(width: 1180, height: 820),
            userInterfaceIdiom: .pad
        )

        XCTAssertTrue(layout.usesPersistentSidebar)
        XCTAssertEqual(layout.sidebarWidth, 330.4, accuracy: 0.001)
        XCTAssertEqual(layout.mainContentWidth, 849.6, accuracy: 0.001)
    }

    func testPadPersistentSidebarWidthIsClamped() {
        let compact = SidebarLayout.layout(
            for: CGSize(width: 600, height: 500),
            userInterfaceIdiom: .pad
        )
        let wide = SidebarLayout.layout(
            for: CGSize(width: 2000, height: 1200),
            userInterfaceIdiom: .pad
        )

        XCTAssertEqual(compact.sidebarWidth, 280, accuracy: 0.001)
        XCTAssertEqual(wide.sidebarWidth, 360, accuracy: 0.001)
    }

    func testPadPortraitUsesOverlaySidebar() {
        let layout = SidebarLayout.layout(
            for: CGSize(width: 820, height: 1180),
            userInterfaceIdiom: .pad
        )

        XCTAssertFalse(layout.usesPersistentSidebar)
        XCTAssertEqual(layout.sidebarWidth, 320, accuracy: 0.001)
        XCTAssertEqual(layout.mainContentWidth, 820, accuracy: 0.001)
    }

    func testMainContentOffsetOnlyAppliesWhenSidebarAffectsMainContent() {
        let overlayLayout = SidebarLayout(
            sidebarWidth: 300,
            mainContentWidth: 390,
            usesPersistentSidebar: false
        )
        let persistentLayout = SidebarLayout(
            sidebarWidth: 320,
            mainContentWidth: 860,
            usesPersistentSidebar: true
        )

        XCTAssertEqual(overlayLayout.mainContentOffsetX(isOverlayVisible: false), 0)
        XCTAssertEqual(overlayLayout.mainContentOffsetX(isOverlayVisible: true), 300)
        XCTAssertEqual(persistentLayout.mainContentOffsetX(isOverlayVisible: false), 320)
    }
}
