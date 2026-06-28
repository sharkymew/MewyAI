import Foundation
import SwiftUI
import UIKit

struct SidebarLayout {
    let sidebarWidth: CGFloat
    let mainContentWidth: CGFloat
    let usesPersistentSidebar: Bool

    private static let persistentWidthRatio: CGFloat = 0.28
    private static let persistentMinimumWidth: CGFloat = 280
    private static let persistentMaximumWidth: CGFloat = 360
    private static let overlayWidthRatio: CGFloat = 0.72
    private static let overlayMaximumWidth: CGFloat = 320

    static func layout(
        for size: CGSize,
        userInterfaceIdiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom
    ) -> SidebarLayout {
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
            mainContentWidth: usesPersistentSidebar ? max(size.width - sidebarWidth, 0) : size.width,
            usesPersistentSidebar: usesPersistentSidebar
        )
    }

    func mainContentOffsetX(isOverlayVisible: Bool) -> CGFloat {
        usesPersistentSidebar || isOverlayVisible ? sidebarWidth : 0
    }
}
