import Foundation

enum AppRuntimeMode: Equatable {
    case production
    case e2e
    case invalidE2E
    case screenshotDemo
}

#if DEBUG
enum E2EBridgePathError: Error {
    case invalidSessionID
    case invalidSharedRoot
    case sessionAlreadyExists
    case unsafeSessionDirectory
    case sessionDirectoryMissing
    case invalidSessionDirectoryPermissions
}

struct E2EBridgePaths: Equatable {
    static let neutralSharedRootURL = URL(
        fileURLWithPath: "/private/tmp",
        isDirectory: true)

    let sessionID: String
    let sharedRootURL: URL
    let sessionDirectoryURL: URL
    let reportURL: URL
    let commandURL: URL

    static func createSharedSession(
        sessionID: String,
        fileManager: FileManager = .default
    ) throws -> E2EBridgePaths {
        let paths = try resolvedPaths(
            sessionID: sessionID,
            sharedRootPath: neutralSharedRootURL.path)
        if (try? fileManager.destinationOfSymbolicLink(
            atPath: paths.sessionDirectoryURL.path)) != nil {
            throw E2EBridgePathError.unsafeSessionDirectory
        }
        guard !fileManager.fileExists(atPath: paths.sessionDirectoryURL.path) else {
            throw E2EBridgePathError.sessionAlreadyExists
        }
        try fileManager.createDirectory(
            at: paths.sessionDirectoryURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700])
        try validateExistingSessionDirectory(paths, fileManager: fileManager)
        return paths
    }

    static func resolveExistingSharedSession(
        sessionID: String,
        sharedRootPath: String,
        fileManager: FileManager = .default
    ) throws -> E2EBridgePaths {
        let paths = try resolvedPaths(
            sessionID: sessionID,
            sharedRootPath: sharedRootPath)
        try validateExistingSessionDirectory(paths, fileManager: fileManager)
        return paths
    }

    private static func resolvedPaths(
        sessionID: String,
        sharedRootPath: String
    ) throws -> E2EBridgePaths {
        guard let uuid = UUID(uuidString: sessionID),
              uuid.uuidString.caseInsensitiveCompare(sessionID) == .orderedSame else {
            throw E2EBridgePathError.invalidSessionID
        }
        guard sharedRootPath == "/private/tmp" || sharedRootPath == "/tmp" else {
            throw E2EBridgePathError.invalidSharedRoot
        }
        let canonicalRoot = neutralSharedRootURL
        let canonicalSessionID = uuid.uuidString
        let sessionDirectory = canonicalRoot
            .appendingPathComponent(
                "talkie-ui-\(canonicalSessionID)",
                isDirectory: true)
        guard sessionDirectory.deletingLastPathComponent().path == canonicalRoot.path else {
            throw E2EBridgePathError.unsafeSessionDirectory
        }
        return E2EBridgePaths(
            sessionID: canonicalSessionID,
            sharedRootURL: canonicalRoot,
            sessionDirectoryURL: sessionDirectory,
            reportURL: sessionDirectory.appendingPathComponent("report.jsonl"),
            commandURL: sessionDirectory.appendingPathComponent("commands"))
    }

    private static func validateExistingSessionDirectory(
        _ paths: E2EBridgePaths,
        fileManager: FileManager
    ) throws {
        if (try? fileManager.destinationOfSymbolicLink(
            atPath: paths.sessionDirectoryURL.path)) != nil {
            throw E2EBridgePathError.unsafeSessionDirectory
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: paths.sessionDirectoryURL.path,
            isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw E2EBridgePathError.sessionDirectoryMissing
        }
        let attributes = try fileManager.attributesOfItem(
            atPath: paths.sessionDirectoryURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        guard permissions == 0o700 else {
            throw E2EBridgePathError.invalidSessionDirectoryPermissions
        }
    }
}
#endif

struct E2ELaunchConfiguration: Equatable {
    let sessionID: String
    let scenario: String
    let reportURL: URL
    let commandURL: URL
    let fixtureText: String?
    let ownsSessionDirectory: Bool

    init(
        sessionID: String,
        scenario: String,
        reportURL: URL,
        commandURL: URL? = nil,
        fixtureText: String?,
        ownsSessionDirectory: Bool = false
    ) {
        self.sessionID = sessionID
        self.scenario = scenario
        self.reportURL = reportURL
        self.commandURL = commandURL ?? reportURL.appendingPathExtension("commands")
        self.fixtureText = fixtureText
        self.ownsSessionDirectory = ownsSessionDirectory
    }
}

/// Process-level dependencies that must differ between a real user launch and a
/// deterministic test launch. Feature services are constructed from this value
/// instead of reaching directly into global defaults/keychain state.
struct AppEnvironment {
    let mode: AppRuntimeMode
    let defaults: UserDefaults
    let keychainService: String
    let historyInMemory: Bool
    let credentialOverrides: [KeychainStore.Key: String]
    let e2e: E2ELaunchConfiguration?

    static func launch(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
#if DEBUG
#if TALKIE_SCREENSHOT_DEMO
        return screenshotDemoEnvironment(sessionID: "compiled-fixture")
#endif
        if arguments.contains("--screenshot-demo") {
            let sessionID = value(after: "--screenshot-demo-session", in: arguments)
                ?? UUID().uuidString
            return screenshotDemoEnvironment(sessionID: sessionID)
        }
        if arguments.contains("--e2e") {
            let sessionID = value(after: "--e2e-session", in: arguments) ?? UUID().uuidString
            let scenario = value(after: "--e2e-scenario", in: arguments) ?? "unspecified"
            let resolvedSession: (paths: E2EBridgePaths, isAppOwned: Bool)?
            if let sharedRoot = value(after: "--e2e-shared-root", in: arguments) {
                resolvedSession = try? (
                    E2EBridgePaths.resolveExistingSharedSession(
                    sessionID: sessionID,
                    sharedRootPath: sharedRoot),
                    false)
            } else {
                resolvedSession = try? (
                    E2EBridgePaths.createSharedSession(sessionID: sessionID),
                    true)
            }
            guard let resolvedSession else {
                return invalidE2EEnvironment()
            }
            let paths = resolvedSession.paths
            let suite = "com.archiev.talkie.e2e.\(paths.sessionID)"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            let defaults = UserDefaults(suiteName: suite)!
            defaults.set(true, forKey: SetupStateStore.completedKey)
            defaults.set(SetupStateStore.currentStateVersion,
                         forKey: SetupStateStore.stateVersionKey)
            defaults.set("gpt-transcribe", forKey: "transcriptionModel")
            defaults.set("gpt-live-transcribe", forKey: "realtimeTranscriptionModel")
            defaults.set("medium", forKey: "realtimeTranscriptionDelay")
            defaults.set(["en"], forKey: "expectedInputLanguages")
            defaults.set(false, forKey: "streamBatchTranscription")
            return AppEnvironment(
                mode: .e2e,
                defaults: defaults,
                keychainService: suite,
                historyInMemory: true,
                credentialOverrides: [
                    .openAIKey: "e2e-openai-key",
                    .openRouterKey: "e2e-openrouter-key",
                ],
                e2e: E2ELaunchConfiguration(
                    sessionID: paths.sessionID,
                    scenario: scenario,
                    reportURL: paths.reportURL,
                    commandURL: paths.commandURL,
                    fixtureText: value(after: "--e2e-fixture-text", in: arguments),
                    ownsSessionDirectory: resolvedSession.isAppOwned))
        }
#endif
        return productionEnvironment()
    }

    private static func productionEnvironment() -> AppEnvironment {
        AppEnvironment(
            mode: .production,
            defaults: .standard,
            keychainService: "com.archiev.talkie",
            historyInMemory: false,
            credentialOverrides: [:],
            e2e: nil)
    }

#if DEBUG
    private static func invalidE2EEnvironment() -> AppEnvironment {
        let suite = "com.archiev.talkie.e2e.invalid"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return AppEnvironment(
            mode: .invalidE2E,
            defaults: UserDefaults(suiteName: suite)!,
            keychainService: suite,
            historyInMemory: true,
            credentialOverrides: [:],
            e2e: nil)
    }
#endif

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

#if DEBUG
    private static func screenshotDemoEnvironment(sessionID: String) -> AppEnvironment {
        let suite = "com.archiev.talkie.screenshot.\(sessionID)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: SetupStateStore.completedKey)
        defaults.set(SetupStateStore.currentStateVersion,
                     forKey: SetupStateStore.stateVersionKey)
        defaults.set(false, forKey: "simpleMode")
        let profile = DictationProfile.privateOffline
        defaults.set(profile.engineMode, forKey: "engineMode")
        defaults.set(profile.instantSkipCleanup, forKey: "instantSkipCleanup")
        defaults.set(profile.instantLiveType, forKey: "instantLiveType")
        defaults.set(profile.transcriptionProvider, forKey: "transcriptionProvider")
        defaults.set(profile.transcriptionModel, forKey: "transcriptionModel")
        defaults.set(profile.openrouterTranscriptionModel,
                     forKey: "openrouterTranscriptionModel")
        defaults.set(profile.cleanupLevel, forKey: "cleanupLevel")
        defaults.set(profile.cleanupProvider, forKey: "cleanupProvider")
        defaults.set(profile.cleanupModel, forKey: "cleanupModel")
        defaults.set(profile.customCleanupPrompt, forKey: "customCleanupPrompt")
        defaults.set("en", forKey: "pinnedLanguage")
        defaults.set(PillStyle.calmFlowRibbon.rawValue, forKey: "pillStyle")
        defaults.set("topCenter", forKey: "pillPosition")
        defaults.set(profile.id.uuidString, forKey: "selectedProfileID")
        return AppEnvironment(
            mode: .screenshotDemo,
            defaults: defaults,
            keychainService: suite,
            historyInMemory: true,
            credentialOverrides: [:],
            e2e: nil)
    }
#endif
}
