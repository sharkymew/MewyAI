//
//  AI_ClientApp.swift
//  AI Client
//
//  Created by SharkyMew on 2026/5/20.
//

import SwiftUI

@main
struct AI_ClientApp: App {
    init() {
        #if DEBUG
        StreamingMarkdownRenderSelfCheck.runIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
