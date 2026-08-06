import SwiftUI

struct SpeakerFilteringSettingsSection: View {
    @Bindable var settings: SettingsStore
    @Bindable var speakerReference: SpeakerReferenceController

    var body: some View {
        Section("Speaker filtering") {
            Toggle("Transcribe only my enrolled voice", isOn: $settings.speakerFilteringEnabled)
                .disabled(!speakerReference.hasReference)
                .accessibilityIdentifier("Transcribe only my enrolled voice")

            HStack {
                Button(buttonTitle) {
                    Task {
                        if speakerReference.isRecording {
                            await speakerReference.stop()
                        } else {
                            await speakerReference.start()
                        }
                    }
                }
                if speakerReference.hasReference {
                    Button("Remove", role: .destructive) {
                        settings.speakerFilteringEnabled = false
                        speakerReference.remove()
                    }
                }
                if speakerReference.isRecording {
                    Label("Speak naturally…", systemImage: "waveform")
                        .foregroundStyle(.red)
                }
            }

            if let message = speakerReference.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(
                        speakerReference.hasReference ? Color.secondary : Color.orange)
            }
            Text("Records an 8-second reference locally. When enabled, Talkie uses OpenAI’s gpt-4o-transcribe-diarize after you release the key and keeps only your speaker segments. This switches dictation to OpenAI batch mode; GPT Live cannot return speaker labels.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("The reference stays on this Mac and is sent to OpenAI only with dictations while this option is enabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var buttonTitle: String {
        if speakerReference.isRecording { return "Finish voice sample" }
        return speakerReference.hasReference ? "Replace voice sample" : "Record voice sample"
    }
}
