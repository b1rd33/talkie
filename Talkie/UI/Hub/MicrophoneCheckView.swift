import SwiftUI

/// User-started, five-second input check. No audio file or provider request.
struct MicrophoneCheckView: View {
    @Bindable var settings: SettingsStore
    @State private var recorder: AudioRecorder
    @State private var testing = false
    @State private var level: Float = 0
    @State private var result = "Choose your microphone, then test its input level."

    init(settings: SettingsStore) {
        self.settings = settings
        _recorder = State(initialValue: AudioRecorder(preferredDeviceUID: {
            settings.preferredAudioDeviceUID
        }))
    }

    var body: some View {
        Picker("Microphone", selection: $settings.preferredAudioDeviceUID) {
            Text("System default").tag(String?.none)
            ForEach(SystemAudioDeviceCatalog().inputDevices()) { device in
                Text(device.name).tag(Optional(device.uid))
            }
        }
        .disabled(testing)
        HStack {
            Button(testing ? "Stop test" : "Test microphone") { testing.toggle() }
                .disabled(AppServices.shared.recorder.isRecording
                          || AppServices.shared.speakerReference.isRecording)
            ProgressView(value: Double(level)).frame(width: 120)
                .accessibilityLabel("Microphone input level")
        }
        Text(result).font(.caption).foregroundStyle(.secondary)
        Text("The test listens for five seconds. Audio stays on this Mac and is discarded.")
            .font(.caption).foregroundStyle(.secondary)
        .task(id: testing) {
            guard testing else { recorder.discard(); level = 0; return }
            defer { recorder.discard(); level = 0; testing = false }
            do {
                try await recorder.start()
                try Task.checkCancellation()
                let input = recorder.activeInputName ?? "Selected microphone"
                result = "Listening on \(input)… speak now."
                var peak: Float = 0
                for _ in 0..<50 {
                    try await Task.sleep(for: .milliseconds(100))
                    level = recorder.latestLevel
                    peak = max(peak, level)
                }
                result = peak >= AudioHealthPolicy.standard.signalFloorRMS * 10
                    ? "Input detected on \(input)."
                    : "No signal from \(input). Check its mute switch, input volume, or choose another microphone."
            } catch is CancellationError {
                result = "Microphone test stopped."
            } catch {
                result = error.localizedDescription
            }
        }
        .onDisappear { testing = false; recorder.discard() }
    }
}
