//
//  AI_ClientApp.swift
//  AI Client
//
//  Created by SharkyMew on 2026/5/20.
//

import SwiftUI
import WebKit

@main
struct AI_ClientApp: App {
    init() {
        WebKitStorageCleanup.removeLegacyPersistentDataIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private enum WebKitStorageCleanup {
    private static let didRemoveLegacyDataKey = "didRemoveLegacyWebKitData"

    static func removeLegacyPersistentDataIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didRemoveLegacyDataKey) else { return }

        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {
            defaults.set(true, forKey: didRemoveLegacyDataKey)
        }
    }
}
