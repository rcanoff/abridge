import SwiftUI

struct ServerStatusIndicator: View {
    let state: ServerRunState

    var body: some View {
        Label {
            Text(state.displayName)
        } icon: {
            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolColor)
        }
        .accessibilityLabel(accessibilityText)
    }

    private var symbolName: String {
        switch state {
        case .running:
            "circle.fill"
        case .starting:
            "circle.dotted"
        case .stopped:
            "circle"
        case .error:
            "exclamationmark.circle.fill"
        }
    }

    private var symbolColor: Color {
        switch state {
        case .running:
            .green
        case .starting:
            .orange
        case .stopped:
            .secondary
        case .error:
            .red
        }
    }

    private var accessibilityText: String {
        switch state {
        case .running:
            "Server running"
        case .starting:
            "Server starting"
        case .stopped:
            "Server stopped"
        case let .error(message):
            "Server error: \(message)"
        }
    }
}

struct PermissionStatusIndicator: View {
    let status: RemindersPermissionStatus

    var body: some View {
        Label {
            Text(status.displayName)
        } icon: {
            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolColor)
        }
        .accessibilityLabel(accessibilityText)
    }

    private var symbolName: String {
        switch status {
        case .authorized:
            "checkmark.circle.fill"
        case .writeOnly:
            "pencil.circle.fill"
        case .notDetermined, .unknown:
            "questionmark.circle"
        case .denied, .restricted:
            "xmark.circle.fill"
        }
    }

    private var symbolColor: Color {
        switch status {
        case .authorized:
            .green
        case .writeOnly, .notDetermined, .unknown:
            .orange
        case .denied, .restricted:
            .red
        }
    }

    private var accessibilityText: String {
        "Reminders access: \(status.displayName)"
    }
}
