import SwiftUI

struct SettingsWindowView: View {
    @Bindable var settingsStore: SettingsStore
    @Bindable var permissionsStore: PermissionsStore
    @Bindable var serverStore: ServerStore
    @Bindable var appStore: AppStore

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $settingsStore.selectedTab) { tab in
                Text(tab.title)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 148, max: 180)
        } detail: {
            Group {
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
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}