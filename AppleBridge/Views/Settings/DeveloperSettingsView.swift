import SwiftUI

struct DeveloperSettingsView: View {
    @Bindable var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Use Keychain for API key", isOn: keychainBinding)
            } header: {
                Text("API Key Storage")
            } footer: {
                if settingsStore.appSettings.useKeychainForAPIKey {
                    Text("Recommended. The bearer token is stored in the macOS Keychain.")
                } else {
                    Text(
                        "The API key is stored in a local file on this Mac. This is less secure and intended for development and automation only — not for everyday use."
                    )
                    .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Developer")
    }

    private var keychainBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.appSettings.useKeychainForAPIKey },
            set: { newValue in
                Task { await settingsStore.applyKeychainStorageChange(newValue) }
            }
        )
    }
}