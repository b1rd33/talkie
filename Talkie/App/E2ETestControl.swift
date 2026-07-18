#if DEBUG
import Foundation

enum E2ECommand: String, CaseIterable {
    case press
    case release
    case toggleHandsFree
    case cancel
}

struct E2EReportEntry: Codable, Equatable {
    let scenario: String
    let state: String
    let durationMS: Int
    let targetBundleID: String?
    let deliveryRoute: String?
    let passed: Bool?
    let reason: String?
}

/// Session-scoped JSONL diagnostics. The schema deliberately has no fields for
/// transcript text, surrounding text, credentials, selected text, or clipboard.
final class E2EReporter {
    private let configuration: E2ELaunchConfiguration
    private let encoder = JSONEncoder()
    private let lock = NSLock()
    private var lastTransitionAt = Date()

    init(configuration: E2ELaunchConfiguration) throws {
        self.configuration = configuration
        try FileManager.default.createDirectory(
            at: configuration.reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: configuration.reportURL.path,
                                       contents: nil)
    }

    func record(state: String, targetBundleID: String?, deliveryRoute: String? = nil,
                passed: Bool? = nil, reason: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        let entry = E2EReportEntry(
            scenario: configuration.scenario,
            state: state,
            durationMS: max(0, Int(now.timeIntervalSince(lastTransitionAt) * 1_000)),
            targetBundleID: targetBundleID,
            deliveryRoute: deliveryRoute,
            passed: passed,
            reason: reason)
        lastTransitionAt = now
        guard let data = try? encoder.encode(entry),
              let handle = try? FileHandle(forWritingTo: configuration.reportURL) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        handle.write(data)
        handle.write(Data([0x0A]))
    }

    func readEntries() throws -> [E2EReportEntry] {
        let data = try Data(contentsOf: configuration.reportURL)
        return try data.split(separator: 0x0A).map { line in
            try JSONDecoder().decode(E2EReportEntry.self, from: Data(line))
        }
    }
}

@MainActor
final class E2ERuntime {
    private enum State { case idle, recording }
    private let reporter: E2EReporter
    private let targetBundleID: () -> String?
    private var state: State = .idle
    private var handsFree = false
    private let inserter: TextInserting?
    private let fixtureText: String?

    init(reporter: E2EReporter, targetBundleID: @escaping () -> String?,
         inserter: TextInserting? = nil, fixtureText: String? = nil) {
        self.reporter = reporter
        self.targetBundleID = targetBundleID
        self.inserter = inserter
        self.fixtureText = fixtureText
    }

    func handle(_ command: E2ECommand) {
        switch command {
        case .press:
            guard state == .idle else { return }
            state = .recording
            reporter.record(state: "recording", targetBundleID: targetBundleID())
        case .release:
            guard state == .recording, !handsFree else { return }
            finish()
        case .toggleHandsFree:
            if state == .idle {
                handsFree = true
                state = .recording
                reporter.record(state: "recording", targetBundleID: targetBundleID())
            } else if handsFree {
                handsFree = false
                finish()
            }
        case .cancel:
            guard state == .recording else { return }
            handsFree = false
            state = .idle
            reporter.record(state: "idle", targetBundleID: targetBundleID(),
                            deliveryRoute: "none", passed: true, reason: "cancelled")
        }
    }

    private func finish() {
        reporter.record(state: "transcribing", targetBundleID: targetBundleID())
        reporter.record(state: "inserting", targetBundleID: targetBundleID())
        if let fixtureText, let inserter {
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await inserter.insert(fixtureText)
                    self.state = .idle
                    self.reporter.record(state: "idle", targetBundleID: self.targetBundleID(),
                                         deliveryRoute: "insert", passed: true, reason: nil)
                } catch {
                    self.state = .idle
                    self.reporter.record(state: "idle", targetBundleID: self.targetBundleID(),
                                         deliveryRoute: "none", passed: false,
                                         reason: "insertion-failed")
                }
            }
        } else {
            state = .idle
            reporter.record(state: "idle", targetBundleID: targetBundleID(),
                            deliveryRoute: "insert", passed: true, reason: nil)
        }
    }
}

@MainActor
final class E2ETestControlBridge {
    private let configuration: E2ELaunchConfiguration
    private let runtime: E2ERuntime
    private var observer: NSObjectProtocol?
    private var commandTask: Task<Void, Never>?

    init(configuration: E2ELaunchConfiguration, runtime: E2ERuntime) {
        self.configuration = configuration
        self.runtime = runtime
    }

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.notificationName(sessionID: configuration.sessionID),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?["command"] as? String,
                  let command = E2ECommand(rawValue: raw) else { return }
            Task { @MainActor in self?.runtime.handle(command) }
        }
        startCommandFileBridge()
    }

    private func startCommandFileBridge() {
        let url = configuration.reportURL.appendingPathExtension("commands")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        commandTask = Task { [weak self] in
            var consumed = 0
            while !Task.isCancelled {
                if let data = try? Data(contentsOf: url), data.count > consumed {
                    let newData = data.subdata(in: consumed..<data.count)
                    consumed = data.count
                    if let text = String(data: newData, encoding: .utf8) {
                        for line in text.split(whereSeparator: \.isNewline) {
                            if let command = E2ECommand(rawValue: String(line)) {
                                self?.runtime.handle(command)
                            }
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    static func notificationName(sessionID: String) -> Notification.Name {
        Notification.Name("com.archiev.talkie.e2e.\(sessionID).command")
    }

    deinit {
        commandTask?.cancel()
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }
}
#endif
