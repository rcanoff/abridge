import AppKit
import SwiftUI

@main
struct AppleBridgeApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        MenuBarExtra("Apple Bridge", systemImage: "bell") {
            MenuBarPopoverView(store: store)
                .onAppear {
                    store.refreshStatus()
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )) { _ in
                    store.refreshStatus()
                }
        }
        .menuBarExtraStyle(.window)
    }
}