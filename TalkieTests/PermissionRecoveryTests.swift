import XCTest
@testable import Talkie

final class PermissionRecoveryTests: XCTestCase {
    func testNotificationDestinationsRoundTripThroughActionPayload() {
        for destination in NotificationDestination.allCases {
            XCTAssertEqual(NotificationDestination(action: destination.action), destination)
        }
    }

    func testPermissionDestinationsUseTargetedSystemSettingsLinks() {
        XCTAssertTrue(NotificationDestination.microphone.systemSettingsURL!.absoluteString
            .contains("Privacy_Microphone"))
        XCTAssertTrue(NotificationDestination.accessibility.systemSettingsURL!.absoluteString
            .contains("Privacy_Accessibility"))
    }

    func testEngineDestinationOpensTalkieSettingsInsteadOfSystemSettings() {
        XCTAssertNil(NotificationDestination.engines.systemSettingsURL)
    }

    func testPermissionHealthReportsEachMissingPermission() {
        XCTAssertEqual(PermissionHealth(microphoneGranted: false,
                                        accessibilityGranted: false).missing,
                       [.microphone, .accessibility])
        XCTAssertEqual(PermissionHealth(microphoneGranted: true,
                                        accessibilityGranted: true).missing,
                       [])
    }
}
