import XCTest
@testable import Talkie

final class AudioDeviceSelectionTests: XCTestCase {
    func testPreferredStableUIDResolvesToDeviceID() {
        let devices = [AudioInputDevice(id: 7, uid: "built-in", name: "Mac"),
                       AudioInputDevice(id: 9, uid: "usb", name: "USB Mic")]
        XCTAssertEqual(AudioDeviceSelection.deviceID(preferredUID: "usb", devices: devices), 9)
    }

    func testMissingPreferredDeviceFallsBackToSystemDefault() {
        let devices = [AudioInputDevice(id: 7, uid: "built-in", name: "Mac")]
        XCTAssertNil(AudioDeviceSelection.deviceID(preferredUID: "gone", devices: devices))
        XCTAssertNil(AudioDeviceSelection.deviceID(preferredUID: nil, devices: devices))
    }
}
