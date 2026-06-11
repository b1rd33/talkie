import SwiftUI

struct LicenseSettingsTab: View {
    let entitlements: EntitlementStore

    @State private var keyInput: String = ""
    @State private var feedback: String?
    @State private var feedbackIsError = false

    var body: some View {
        Form {
            Section("Status") {
                switch entitlements.current {
                case .licensed:
                    LabeledContent("License", value: "Licensed — thank you!")
                    if let expiry = entitlements.licenseExpirationText {
                        LabeledContent("Valid until", value: expiry)
                    }
                case .trial(let daysLeft):
                    LabeledContent("License", value: "Trial — \(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
                case .expired:
                    LabeledContent("License",
                                   value: entitlements.trialHasStarted ? "Trial expired" : "No license")
                }
                LabeledContent("Machine ID") {
                    HStack(spacing: 8) {
                        Text(entitlements.machineID).monospaced()
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entitlements.machineID, forType: .string)
                        }
                    }
                }
            }
            Section("Activate") {
                TextField("XXXXX-XXXXX-XXXXX-XXXXX", text: $keyInput)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                Button("Activate") {
                    let result = entitlements.activate(
                        keyInput.trimmingCharacters(in: .whitespacesAndNewlines))
                    feedbackIsError = result != .valid
                    feedback = result.message
                    if result == .valid { keyInput = "" }
                }
                .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let feedback {
                    Text(feedback)
                        .font(.callout)
                        .foregroundStyle(feedbackIsError ? Color.red : Color.green)
                }
            }
        }
        .formStyle(.grouped)
        // Status/countdown must reflect the clock NOW, not whenever the store
        // last refreshed — `current` is cached (see EntitlementStore).
        .onAppear { entitlements.refresh() }
    }
}
