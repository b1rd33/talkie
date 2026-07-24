import Foundation

enum AppRuntimeMode: Equatable {
    case production
    case e2e
    case screenshotDemo
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
