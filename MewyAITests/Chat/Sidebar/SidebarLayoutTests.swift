import SwiftUI
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
        XCTAssertEqual(layout.mainContentWidth(isSidebarVisible: false), 390, accuracy: 0.001)
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
        XCTAssertEqual(layout.mainContentWidth(isSidebarVisible: true), 849.6, accuracy: 0.001)
        XCTAssertEqual(layout.mainContentWidth(isSidebarVisible: false), 1180, accuracy: 0.001)
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
        XCTAssertEqual(layout.mainContentWidth(isSidebarVisible: false), 820, accuracy: 0.001)
    }

    func testMainContentOffsetOnlyAppliesWhenSidebarAffectsMainContent() {
        let overlayLayout = SidebarLayout(
            sidebarWidth: 300,
            containerWidth: 390,
            usesPersistentSidebar: false,
            sidebarToggleLeadingOffset: 0
        )
        let persistentLayout = SidebarLayout(
            sidebarWidth: 320,
            containerWidth: 1180,
            usesPersistentSidebar: true,
            sidebarToggleLeadingOffset: 0
        )

        XCTAssertEqual(overlayLayout.mainContentOffsetX(isOverlayVisible: false, isSidebarVisible: false), 0)
        XCTAssertEqual(overlayLayout.mainContentOffsetX(isOverlayVisible: true, isSidebarVisible: true), 300)
        XCTAssertEqual(persistentLayout.mainContentOffsetX(isOverlayVisible: false, isSidebarVisible: true), 320)
        XCTAssertEqual(persistentLayout.mainContentOffsetX(isOverlayVisible: false, isSidebarVisible: false), 0)
    }

    func testPhoneSidebarToggleNeverUsesLeadingSafeAreaInset() {
        let offset = SidebarLayout.sidebarToggleLeadingOffset(
            for: CGSize(width: 390, height: 844),
            safeAreaInsets: EdgeInsets(top: 0, leading: 80, bottom: 0, trailing: 0),
            screenSize: CGSize(width: 390, height: 844),
            windowSize: CGSize(width: 390, height: 844),
            userInterfaceIdiom: .phone
        )

        XCTAssertEqual(offset, 0, accuracy: 0.001)
    }

    func testPadFullscreenSidebarToggleKeepsOriginalPosition() {
        let offset = SidebarLayout.sidebarToggleLeadingOffset(
            for: CGSize(width: 1180, height: 820),
            safeAreaInsets: EdgeInsets(top: 24, leading: 72, bottom: 20, trailing: 0),
            screenSize: CGSize(width: 1180, height: 820),
            windowSize: CGSize(width: 1180, height: 820),
            userInterfaceIdiom: .pad
        )

        XCTAssertEqual(offset, 0, accuracy: 0.001)
    }

    func testPadFullscreenSidebarToggleAllowsSafeAreaExcludedWindowSize() {
        let offset = SidebarLayout.sidebarToggleLeadingOffset(
            for: CGSize(width: 1108, height: 776),
            safeAreaInsets: EdgeInsets(top: 24, leading: 72, bottom: 20, trailing: 0),
            screenSize: CGSize(width: 1180, height: 820),
            windowSize: CGSize(width: 1180, height: 820),
            userInterfaceIdiom: .pad
        )

        XCTAssertEqual(offset, 0, accuracy: 0.001)
    }

    func testPadFullscreenSidebarToggleUsesWindowSizeWhenLayoutSizeDiffers() {
        let offset = SidebarLayout.sidebarToggleLeadingOffset(
            for: CGSize(width: 1024, height: 720),
            safeAreaInsets: EdgeInsets(top: 24, leading: 72, bottom: 20, trailing: 0),
            screenSize: CGSize(width: 1180, height: 820),
            windowSize: CGSize(width: 1180, height: 820),
            userInterfaceIdiom: .pad
        )

        XCTAssertEqual(offset, 0, accuracy: 0.001)
    }

    func testPadFullscreenSidebarToggleKeepsPositionWhenOnlyHeightDiffers() {
        let offset = SidebarLayout.sidebarToggleLeadingOffset(
            for: CGSize(width: 1180, height: 744),
            safeAreaInsets: EdgeInsets(top: 24, leading: 72, bottom: 20, trailing: 0),
            screenSize: CGSize(width: 1180, height: 820),
            windowSize: CGSize(width: 1180, height: 744),
            userInterfaceIdiom: .pad
        )

        XCTAssertEqual(offset, 0, accuracy: 0.001)
    }

    func testPadWindowedSidebarToggleAvoidsWindowControls() {
        let offset = SidebarLayout.sidebarToggleLeadingOffset(
            for: CGSize(width: 820, height: 700),
            safeAreaInsets: EdgeInsets(top: 24, leading: 72, bottom: 20, trailing: 0),
            screenSize: CGSize(width: 1180, height: 820),
            windowSize: CGSize(width: 900, height: 700),
            userInterfaceIdiom: .pad
        )

        XCTAssertEqual(offset, 72, accuracy: 0.001)
    }

    func testPadNearFullscreenWindowedSidebarToggleAvoidsWindowControls() {
        let offset = SidebarLayout.sidebarToggleLeadingOffset(
            for: CGSize(width: 1136, height: 820),
            safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0),
            screenSize: CGSize(width: 1180, height: 820),
            windowSize: CGSize(width: 1136, height: 820),
            userInterfaceIdiom: .pad
        )

        XCTAssertEqual(offset, 72, accuracy: 0.001)
    }

    func testPadWindowedSidebarToggleAvoidsWindowControlsWithoutLeadingSafeAreaInset() {
        let offset = SidebarLayout.sidebarToggleLeadingOffset(
            for: CGSize(width: 820, height: 700),
            safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0),
            screenSize: CGSize(width: 1180, height: 820),
            windowSize: CGSize(width: 900, height: 700),
            userInterfaceIdiom: .pad
        )

        XCTAssertEqual(offset, 72, accuracy: 0.001)
    }

    func testPadWindowedSidebarToggleUsesWindowSizeWhenAvailable() {
        let offset = SidebarLayout.sidebarToggleLeadingOffset(
            for: CGSize(width: 820, height: 700),
            safeAreaInsets: EdgeInsets(top: 24, leading: 72, bottom: 20, trailing: 0),
            screenSize: CGSize(width: 1180, height: 820),
            windowSize: CGSize(width: 900, height: 700),
            userInterfaceIdiom: .pad
        )

        XCTAssertEqual(offset, 72, accuracy: 0.001)
    }

    func testPadWindowedSidebarToggleUsesWindowControlsClearanceForSmallLeadingSafeAreaInset() {
        let offset = SidebarLayout.sidebarToggleLeadingOffset(
            for: CGSize(width: 820, height: 700),
            safeAreaInsets: EdgeInsets(top: 24, leading: 24, bottom: 20, trailing: 0),
            screenSize: CGSize(width: 1180, height: 820),
            windowSize: CGSize(width: 900, height: 700),
            userInterfaceIdiom: .pad
        )

        XCTAssertEqual(offset, 72, accuracy: 0.001)
    }

    func testPadPortraitWindowedSidebarToggleAvoidsWindowControls() {
        let offset = SidebarLayout.sidebarToggleLeadingOffset(
            for: CGSize(width: 700, height: 900),
            safeAreaInsets: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0),
            screenSize: CGSize(width: 820, height: 1180),
            windowSize: CGSize(width: 700, height: 900),
            userInterfaceIdiom: .pad
        )

        XCTAssertEqual(offset, 72, accuracy: 0.001)
    }
}
