import Foundation

enum AppRuntimeMode: Equatable {
    case production
    case e2e
}

struct E2ELaunchConfiguration: Equatable {
    let sessionID: String
    let scenario: String
    let reportURL: URL
    let fixtureText: String?
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
        if arguments.contains("--e2e") {
            let sessionID = value(after: "--e2e-session", in: arguments) ?? UUID().uuidString
            let scenario = value(after: "--e2e-scenario", in: arguments) ?? "unspecified"
            let reportPath = value(after: "--e2e-report", in: arguments)
                ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("talkie-e2e-\(sessionID).jsonl").path
            let suite = "com.archiev.talkie.e2e.\(sessionID)"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            let defaults = UserDefaults(suiteName: suite)!
            defaults.set(true, forKey: SetupStateStore.completedKey)
            defaults.set(SetupStateStore.currentStateVersion,
                         forKey: SetupStateStore.stateVersionKey)
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
                    sessionID: sessionID,
                    scenario: scenario,
                    reportURL: URL(fileURLWithPath: reportPath),
                    fixtureText: value(after: "--e2e-fixture-text", in: arguments)))
        }
#endif
        return AppEnvironment(
            mode: .production,
            defaults: .standard,
            keychainService: "com.archiev.talkie",
            historyInMemory: false,
            credentialOverrides: [:],
            e2e: nil)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
