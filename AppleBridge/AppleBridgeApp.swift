import AppKit
import SwiftUI

@main
struct AppleBridgeApp: App {
    @State private var store = AppStore()
    @State private var serverStore = ServerStore()

    var body: some Scene {
        MenuBarExtra("Apple Bridge", systemImage: "bell") {
            MenuBarPopoverView(store: store, serverStore: serverStore)
                .onAppear {
                    store.refreshStatus()
                    Task {
                        await serverStore.refreshBearerToken()
                        await serverStore.refreshStatus()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: NSApplication.didBecomeActiveNotification
                )) { _ in
                    store.refreshStatus()
                    Task {
                        await serverStore.refreshBearerToken()
                        await serverStore.refreshStatus()
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}