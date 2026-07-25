import XCTest

@MainActor
final class E2EBridgeUITests: XCTestCase {
    func testPressReleaseProducesPrivacySafePassingReport() throws {
        let bridge = UITestNotificationBridge()
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--e2e", "--e2e-session", bridge.sessionID,
                               "--e2e-scenario", "press-release"]
        app.launch()
        XCTAssertTrue(bridge.waitUntilReady(timeout: 5))

        let recording = bridge.expectReport { entry in
            entry.state == "recording"
        }
        bridge.post(command: "press")
        wait(for: [recording], timeout: 5)

        let completed = bridge.expectReport { entry in
            entry.state == "idle" && entry.passed == true
        }
        bridge.post(command: "release")
        wait(for: [completed], timeout: 5)

        XCTAssertEqual(
            bridge.entries.map(\.state),
            ["recording", "transcribing", "inserting", "idle"])
        for payload in bridge.payloads {
            let raw = String(decoding: payload, as: UTF8.self)
            for forbidden in ["transcript", "clipboard", "apiKey", "selectedText", "context"] {
                XCTAssertFalse(raw.localizedCaseInsensitiveContains(forbidden))
            }
        }
    }

    func testHandsFreeAndCancelCommandsStayDeterministic() throws {
        let bridge = UITestNotificationBridge()
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["--e2e", "--e2e-session", bridge.sessionID,
                               "--e2e-scenario", "hands-free-cancel"]
        app.launch()
        XCTAssertTrue(bridge.waitUntilReady(timeout: 5))

        let recording = bridge.expectReport { entry in
            entry.state == "recording"
        }
        bridge.post(command: "toggleHandsFree")
        wait(for: [recording], timeout: 5)

        let cancelled = bridge.expectReport { entry in
            entry.state == "idle" && entry.reason == "cancelled"
        }
        bridge.post(command: "cancel")
        wait(for: [cancelled], timeout: 5)

        XCTAssertEqual(bridge.entries.map(\.state), ["recording", "idle"])
        XCTAssertEqual(bridge.entries.last?.deliveryRoute, "none")
        XCTAssertEqual(bridge.entries.last?.passed, true)
    }
}

@MainActor
private final class UITestNotificationBridge {
    private struct PendingReport {
        let id: UUID
        let expectation: XCTestExpectation
        let predicate: (UITestReportEntry) -> Bool
    }

    let sessionID = UUID().uuidString
    private(set) var entries: [UITestReportEntry] = []
    private(set) var payloads: [Data] = []

    private let center = DistributedNotificationCenter.default()
    private var observers: [NSObjectProtocol] = []
    private var pendingReports: [PendingReport] = []
    private var isReady = false

    init() {
        observers.append(center.addObserver(
            forName: UITestBridgeNotifications.readyName(sessionID: sessionID),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isReady = true
            }
        })
        observers.append(center.addObserver(
            forName: UITestBridgeNotifications.reportName(sessionID: sessionID),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let payload = notification.userInfo?[
                    UITestBridgeNotifications.reportPayloadKey] as? Data,
                  let entry = try? JSONDecoder().decode(
                    UITestReportEntry.self,
                    from: payload) else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.entries.append(entry)
                self.payloads.append(payload)
                let matching = self.pendingReports.filter { $0.predicate(entry) }
                let matchingIDs = Set(matching.map(\.id))
                self.pendingReports.removeAll { matchingIDs.contains($0.id) }
                matching.forEach { $0.expectation.fulfill() }
            }
        })
    }

    func waitUntilReady(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isReady, Date() < deadline {
            center.postNotificationName(
                UITestBridgeNotifications.readyRequestName(sessionID: sessionID),
                object: nil,
                userInfo: nil,
                deliverImmediately: true)
            RunLoop.current.run(until: min(
                deadline,
                Date().addingTimeInterval(0.1)))
        }
        return isReady
    }

    func expectReport(
        where predicate: @escaping (UITestReportEntry) -> Bool
    ) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "matching E2E report")
        if entries.contains(where: predicate) {
            expectation.fulfill()
        } else {
            pendingReports.append(PendingReport(
                id: UUID(),
                expectation: expectation,
                predicate: predicate))
        }
        return expectation
    }

    func post(command: String) {
        center.postNotificationName(
            UITestBridgeNotifications.commandName(
                sessionID: sessionID,
                command: command),
            object: nil,
            userInfo: nil,
            deliverImmediately: true)
    }

    deinit {
        for observer in observers {
            center.removeObserver(observer)
        }
    }
}

private struct UITestReportEntry: Codable, Equatable {
    let scenario: String
    let state: String
    let durationMS: Int
    let targetBundleID: String?
    let deliveryRoute: String?
    let passed: Bool?
    let reason: String?
}

private enum UITestBridgeNotifications {
    static let reportPayloadKey = "entry"

    static func commandName(sessionID: String, command: String) -> Notification.Name {
        Notification.Name("com.archiev.talkie.e2e.\(sessionID).command.\(command)")
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
