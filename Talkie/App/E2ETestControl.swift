#if DEBUG
import Foundation

enum E2ECommand: String, CaseIterable {
    case press
    case release
    case toggleHandsFree
    case cancel
}

private enum E2EPrivateFileError: Error {
    case unsafeParentDirectory
    case unsafeFile
}

private enum E2EPrivateFile {
    static func create(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        try validateParentDirectory(of: url, fileManager: fileManager)
        try Data().write(to: url, options: .withoutOverwriting)
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path)
            try validate(at: url, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
    }

    private static func validateParentDirectory(
        of url: URL,
        fileManager: FileManager
    ) throws {
        let parent = url.deletingLastPathComponent()
        if (try? fileManager.destinationOfSymbolicLink(atPath: parent.path)) != nil {
            throw E2EPrivateFileError.unsafeParentDirectory
        }
        let attributes = try fileManager.attributesOfItem(atPath: parent.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
            throw E2EPrivateFileError.unsafeParentDirectory
        }
    }

    private static func validate(
        at url: URL,
        fileManager: FileManager
    ) throws {
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw E2EPrivateFileError.unsafeFile
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600 else {
            throw E2EPrivateFileError.unsafeFile
        }
    }
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

enum E2EBridgeNotifications {
    static let commandPayloadKey = "command"
    static let reportPayloadKey = "entry"

    static func commandName(sessionID: String) -> Notification.Name {
        Notification.Name("com.archiev.talkie.e2e.\(sessionID).command")
    }

    static func commandName(sessionID: String, command: E2ECommand) -> Notification.Name {
        Notification.Name("com.archiev.talkie.e2e.\(sessionID).command.\(command.rawValue)")
    }

    static func reportName(sessionID: String) -> Notification.Name {
        Notification.Name("com.archiev.talkie.e2e.\(sessionID).report")
    }

    static func readyName(sessionID: String) -> Notification.Name {
        Notification.Name("com.archiev.talkie.e2e.\(sessionID).ready")
    }

    static func readyRequestName(sessionID: String) -> Notification.Name {
        Notification.Name("com.archiev.talkie.e2e.\(sessionID).ready-request")
    }
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
        try E2EPrivateFile.create(at: configuration.reportURL)
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
        do {
            let data = try encoder.encode(entry)
            let handle = try FileHandle(forWritingTo: configuration.reportURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: Data([0x0A]))
            DistributedNotificationCenter.default().postNotificationName(
                E2EBridgeNotifications.reportName(sessionID: configuration.sessionID),
                object: nil,
                userInfo: [E2EBridgeNotifications.reportPayloadKey: data],
                deliverImmediately: true)
        } catch {
            assertionFailure("E2E report write failed")
        }
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
    private var observers: [NSObjectProtocol] = []
    private var commandTask: Task<Void, Never>?

    init(configuration: E2ELaunchConfiguration, runtime: E2ERuntime) {
        self.configuration = configuration
        self.runtime = runtime
    }

    func start() throws {
        guard observers.isEmpty else { return }
        try startCommandFileBridge()
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(
            forName: E2EBridgeNotifications.commandName(sessionID: configuration.sessionID),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[
                E2EBridgeNotifications.commandPayloadKey] as? String,
                  let command = E2ECommand(rawValue: raw) else { return }
            MainActor.assumeIsolated {
                self?.runtime.handle(command)
            }
        })
        for command in E2ECommand.allCases {
            observers.append(center.addObserver(
                forName: E2EBridgeNotifications.commandName(
                    sessionID: configuration.sessionID,
                    command: command),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.runtime.handle(command)
                }
            })
        }
        observers.append(center.addObserver(
            forName: E2EBridgeNotifications.readyRequestName(
                sessionID: configuration.sessionID),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.announceReady()
            }
        })
        announceReady()
    }

    private func announceReady() {
        DistributedNotificationCenter.default().postNotificationName(
            E2EBridgeNotifications.readyName(sessionID: configuration.sessionID),
            object: nil,
            userInfo: nil,
            deliverImmediately: true)
    }

    func stop() {
        commandTask?.cancel()
        commandTask = nil
        let center = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        guard configuration.ownsSessionDirectory else { return }
        try? FileManager.default.removeItem(
            at: configuration.reportURL.deletingLastPathComponent())
    }

    private func startCommandFileBridge() throws {
        let url = configuration.commandURL
        try E2EPrivateFile.create(at: url)
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

    deinit {
        commandTask?.cancel()
        let center = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
        }
        if configuration.ownsSessionDirectory {
            try? FileManager.default.removeItem(
                at: configuration.reportURL.deletingLastPathComponent())
        }
    }
}
#endif
