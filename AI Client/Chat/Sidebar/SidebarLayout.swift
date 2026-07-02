import Foundation
import SwiftUI
import UIKit

struct SidebarWindowGeometry: Equatable {
    let screenSize: CGSize
    let windowSize: CGSize
}

@MainActor
struct SidebarLayout {
    let sidebarWidth: CGFloat
    let containerWidth: CGFloat
    let usesPersistentSidebar: Bool
    let sidebarToggleLeadingOffset: CGFloat

    private static let persistentWidthRatio: CGFloat = 0.28
    private static let persistentMinimumWidth: CGFloat = 280
    private static let persistentMaximumWidth: CGFloat = 360
    private static let overlayWidthRatio: CGFloat = 0.72
    private static let overlayMaximumWidth: CGFloat = 320
    private static let windowControlsClearance: CGFloat = 72
    private static let fullscreenSizeTolerance: CGFloat = 8

    static func layout(
        for size: CGSize,
        safeAreaInsets: EdgeInsets = EdgeInsets(),
        windowGeometry: SidebarWindowGeometry? = nil,
        userInterfaceIdiom: UIUserInterfaceIdiom? = nil
    ) -> SidebarLayout {
        let sceneGeometry = windowGeometry ?? inferredWindowGeometry(
            for: size,
            safeAreaInsets: safeAreaInsets
        )
        let userInterfaceIdiom = resolvedUserInterfaceIdiom(userInterfaceIdiom)
        let usesPersistentSidebar = userInterfaceIdiom == .pad
            && size.width > size.height
        let sidebarWidth: CGFloat

        if usesPersistentSidebar {
            sidebarWidth = min(
                max(size.width * persistentWidthRatio, persistentMinimumWidth),
                persistentMaximumWidth
            )
        } else {
            sidebarWidth = min(size.width * overlayWidthRatio, overlayMaximumWidth)
        }

        return SidebarLayout(
            sidebarWidth: sidebarWidth,
            containerWidth: size.width,
            usesPersistentSidebar: usesPersistentSidebar,
            sidebarToggleLeadingOffset: sidebarToggleLeadingOffset(
                for: size,
                safeAreaInsets: safeAreaInsets,
                screenSize: sceneGeometry.screenSize,
                windowSize: sceneGeometry.windowSize,
                userInterfaceIdiom: userInterfaceIdiom
            )
        )
    }

    static func sidebarToggleLeadingOffset(
        for size: CGSize,
        safeAreaInsets: EdgeInsets = EdgeInsets(),
        screenSize: CGSize? = nil,
        windowSize: CGSize? = nil,
        userInterfaceIdiom: UIUserInterfaceIdiom? = nil
    ) -> CGFloat {
        let fallbackGeometry = resolvedSceneGeometry()
        let sceneGeometry = SidebarWindowGeometry(
            screenSize: screenSize ?? fallbackGeometry.screenSize,
            windowSize: windowSize ?? fallbackGeometry.windowSize
        )
        let userInterfaceIdiom = resolvedUserInterfaceIdiom(userInterfaceIdiom)
        let isWindowedPadWindow = isWindowedPadWindow(
            size: size,
            safeAreaInsets: safeAreaInsets,
            screenSize: sceneGeometry.screenSize,
            windowSize: sceneGeometry.windowSize
        )

        guard userInterfaceIdiom == .pad,
              isWindowedPadWindow else {
            return 0
        }

        return max(safeAreaInsets.leading, windowControlsClearance)
    }

    private static func resolvedSceneGeometry() -> SidebarWindowGeometry {
        return currentWindowSceneGeometry()
            ?? SidebarWindowGeometry(screenSize: UIScreen.main.bounds.size, windowSize: UIScreen.main.bounds.size)
    }

    private static func inferredWindowGeometry(
        for size: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> SidebarWindowGeometry {
        if let currentGeometry = currentWindowSceneGeometry() {
            return currentGeometry
        }

        let screenSize = UIScreen.main.bounds.size
        let inferredWindowSize = CGSize(
            width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
        )

        return SidebarWindowGeometry(
            screenSize: screenSize,
            windowSize: validWindowSize(inferredWindowSize) ?? size
        )
    }

    private static func currentWindowSceneGeometry() -> SidebarWindowGeometry? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        let scene = scenes.first { scene in
            scene.activationState == .foregroundActive && !scene.windows.isEmpty
        }
            ?? scenes.first { scene in
                scene.activationState == .foregroundInactive && !scene.windows.isEmpty
            }
            ?? scenes.first { !$0.windows.isEmpty }

        guard let scene else { return nil }

        let window = scene.windows.first { $0.isKeyWindow }
            ?? scene.windows.first { !$0.isHidden }
            ?? scene.windows.first
        guard let windowSize = window.flatMap({ validWindowSize($0.bounds.size) }) else {
            return nil
        }

        return SidebarWindowGeometry(screenSize: scene.screen.bounds.size, windowSize: windowSize)
    }

    fileprivate static func validWindowSize(_ size: CGSize) -> CGSize? {
        guard size.width > 1, size.height > 1 else { return nil }
        return size
    }

    private static func resolvedUserInterfaceIdiom(
        _ userInterfaceIdiom: UIUserInterfaceIdiom?
    ) -> UIUserInterfaceIdiom {
        userInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom
    }

    private static func isFullscreenPadWindow(
        size: CGSize,
        safeAreaInsets: EdgeInsets,
        screenSize: CGSize,
        windowSize: CGSize?
    ) -> Bool {
        if let windowSize, sizesMatch(windowSize, screenSize) {
            return true
        }

        return sizesMatch(size, screenSize)
            || sizesMatch(
                CGSize(
                    width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
                    height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
                ),
                screenSize
            )
    }

    private static func isWindowedPadWindow(
        size: CGSize,
        safeAreaInsets: EdgeInsets,
        screenSize: CGSize,
        windowSize: CGSize?
    ) -> Bool {
        if isFullscreenPadWindow(
            size: size,
            safeAreaInsets: safeAreaInsets,
            screenSize: screenSize,
            windowSize: windowSize
        ) {
            return false
        }

        let windowSize = windowSize ?? CGSize(
            width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
        )

        let screenHorizontalLength = horizontalLength(for: screenSize, layoutSize: size)
        let windowHorizontalLength = horizontalLength(for: windowSize, layoutSize: size)
        let horizontalGap = screenHorizontalLength - windowHorizontalLength

        return horizontalGap > fullscreenSizeTolerance
    }

    private static func horizontalLength(
        for size: CGSize,
        layoutSize: CGSize
    ) -> CGFloat {
        let dimensions = [size.width, size.height].sorted()
        return layoutSize.width >= layoutSize.height ? dimensions[1] : dimensions[0]
    }

    private static func sizesMatch(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        let lhsDimensions = [lhs.width, lhs.height].sorted()
        let rhsDimensions = [rhs.width, rhs.height].sorted()

        return abs(lhsDimensions[0] - rhsDimensions[0]) <= fullscreenSizeTolerance
            && abs(lhsDimensions[1] - rhsDimensions[1]) <= fullscreenSizeTolerance
    }

    func mainContentWidth(isSidebarVisible: Bool) -> CGFloat {
        usesPersistentSidebar && isSidebarVisible ? max(containerWidth - sidebarWidth, 0) : containerWidth
    }

    func mainContentOffsetX(isOverlayVisible: Bool, isSidebarVisible: Bool) -> CGFloat {
        (usesPersistentSidebar && isSidebarVisible) || isOverlayVisible ? sidebarWidth : 0
    }
}

struct SidebarWindowGeometryReader: UIViewRepresentable {
    let onChange: (SidebarWindowGeometry?) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onGeometryChange = onChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onGeometryChange = onChange
        uiView.reportGeometryIfNeeded()
    }

    final class ProbeView: UIView {
        var onGeometryChange: ((SidebarWindowGeometry?) -> Void)?
        private var lastGeometry: SidebarWindowGeometry?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            reportGeometryIfNeeded()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            reportGeometryIfNeeded()
        }

        func reportGeometryIfNeeded() {
            let geometry = currentGeometry()
            guard geometry != lastGeometry else { return }
            lastGeometry = geometry

            DispatchQueue.main.async { [weak self] in
                self?.onGeometryChange?(geometry)
            }
        }

        private func currentGeometry() -> SidebarWindowGeometry? {
            guard let window else {
                return nil
            }

            let windowSize = window.bounds.size
            guard windowSize.width > 1, windowSize.height > 1 else { return nil }

            let screenSize = window.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
            return SidebarWindowGeometry(screenSize: screenSize, windowSize: windowSize)
        }
    }
}
