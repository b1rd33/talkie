import Foundation
import Observation

struct SpeakerFilterConfiguration: Sendable, Equatable {
    static let enrolledSpeakerName = "talkie_user"

    let speakerName: String
    let referenceURL: URL
}

enum SpeakerReferenceError: Error, LocalizedError, Equatable {
    case tooShort
    case tooLong
    case unavailable

    var errorDescription: String? {
        switch self {
        case .tooShort:
            "Keep speaking for at least 2 seconds, then try again."
        case .tooLong:
            "Voice samples must be no longer than 10 seconds."
        case .unavailable:
            "The enrolled voice sample is unavailable. Record it again in Settings."
        }
    }
}

/// Stores the user's optional speaker reference locally. The sample is sent to
/// OpenAI only when the user enables speaker filtering for a dictation.
final class SpeakerReferenceStore: @unchecked Sendable {
    let referenceURL: URL
    private let fileManager: FileManager

    init(
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let root = baseDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("Talkie", isDirectory: true)
        referenceURL = root
            .appendingPathComponent("VoiceReference", isDirectory: true)
            .appendingPathComponent("my-voice.m4a")
    }

    var hasReference: Bool {
        fileManager.fileExists(atPath: referenceURL.path)
    }

    func configuration() throws -> SpeakerFilterConfiguration {
        guard hasReference else { throw SpeakerReferenceError.unavailable }
        return SpeakerFilterConfiguration(
            speakerName: Self.configurationName,
            referenceURL: referenceURL)
    }

    func save(_ audio: RecordedAudio) throws {
        guard audio.duration >= 2 else { throw SpeakerReferenceError.tooShort }
        guard audio.duration <= 10 else { throw SpeakerReferenceError.tooLong }
        let directory = referenceURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let data = try Data(contentsOf: audio.fileURL)
        try data.write(to: referenceURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: referenceURL.path)
    }

    func remove() throws {
        guard hasReference else { return }
        try fileManager.removeItem(at: referenceURL)
    }

    private static let configurationName = SpeakerFilterConfiguration.enrolledSpeakerName
}

@MainActor
@Observable
final class SpeakerReferenceController {
    private let recorder: AudioRecording
    let store: SpeakerReferenceStore
    private var automaticStopTask: Task<Void, Never>?

    private(set) var isRecording = false
    private(set) var hasReference: Bool
    private(set) var statusMessage: String?

    init(
        recorder: AudioRecording? = nil,
        store: SpeakerReferenceStore = SpeakerReferenceStore()
    ) {
        self.recorder = recorder ?? AudioRecorder()
        self.store = store
        hasReference = store.hasReference
    }

    func start() async {
        guard !isRecording else { return }
        statusMessage = nil
        do {
            try await recorder.start()
            isRecording = true
            automaticStopTask?.cancel()
            automaticStopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                await self?.stop()
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func stop() async {
        guard isRecording else { return }
        automaticStopTask?.cancel()
        automaticStopTask = nil
        isRecording = false
        do {
            let audio = try await recorder.stop()
            defer { try? FileManager.default.removeItem(at: audio.fileURL) }
            try store.save(audio)
            hasReference = true
            statusMessage = "Voice sample ready."
        } catch {
            recorder.discard()
            statusMessage = error.localizedDescription
        }
    }

    func remove() {
        automaticStopTask?.cancel()
        recorder.discard()
        isRecording = false
        do {
            try store.remove()
            hasReference = false
            statusMessage = "Voice sample removed."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
