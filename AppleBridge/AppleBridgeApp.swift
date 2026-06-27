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
        }
        .menuBarExtraStyle(.window)
    }
}