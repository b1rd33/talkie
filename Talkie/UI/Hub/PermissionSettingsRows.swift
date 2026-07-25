import AVFoundation
import SwiftUI

struct PermissionSettingsRows: View {
    @Bindable var permissions: PermissionManager

    var body: some View {
        permissionRow(title: "Microphone",
                      granted: permissions.microphoneStatus == .authorized) {
            if permissions.microphoneStatus == .notDetermined {
                permissions.requestMicrophoneAccess()
            } else {
                permissions.openSettings(for: .microphone)
            }
        }

        permissionRow(title: "Accessibility",
                      granted: permissions.accessibilityGranted) {
            permissions.openSettings(for: .accessibility)
        }

        Button("Check permissions again") { permissions.refresh() }
        Button("Run Setup Assistant…") { AppServices.shared.showOnboarding() }
    }

    private func permissionRow(title: String, granted: Bool,
                               repair: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Spacer()
            Text(granted ? "Granted" : "Needs attention")
                .foregroundStyle(.secondary)
            if !granted {
                Button(permissions.microphoneStatus == .notDetermined && title == "Microphone"
                       ? "Allow" : "Repair", action: repair)
            }
        }
    }
}
