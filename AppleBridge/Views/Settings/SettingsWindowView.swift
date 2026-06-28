import AppKit
import SwiftUI

struct SettingsWindowView: View {
    @Bindable var settingsStore: SettingsStore
    @Bindable var permissionsStore: PermissionsStore
    @Bindable var serverStore: ServerStore
    @Bindable var appStore: AppStore

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $settingsStore.selectedTab) { tab in
                Label(tab.title, systemImage: SettingsDesign.symbol(for: tab))
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 148, max: 180)
        } detail: {
            NavigationStack {
                switch settingsStore.selectedTab {
                case .mcp:
                    MCPSettingsView(
                        settingsStore: settingsStore,
                        serverStore: serverStore
                    )
                case .permissions:
                    PermissionsSettingsView(
                        permissionsStore: permissionsStore,
                        settingsStore: settingsStore,
                        appStore: appStore
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(SettingsWindowKeyFocus())
    }
}

/// Ensures the Settings window becomes key when opened from the menu bar extra.
/// Without this, controls render with inactive gray accents until the user refocuses the window.
private struct SettingsWindowKeyFocus: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView(frame: .zero)
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            view.window?.makeKeyAndOrderFront(nil)
        }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}
