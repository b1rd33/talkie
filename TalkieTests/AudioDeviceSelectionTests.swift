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

    func testResolutionReportsPreferredDevice() {
        let devices = [AudioInputDevice(id: 7, uid: "built-in", name: "Mac"),
                       AudioInputDevice(id: 9, uid: "usb", name: "USB Mic")]
        XCTAssertEqual(
            AudioDeviceSelection.resolution(
                preferredUID: "usb", devices: devices, defaultDeviceID: 7),
            .preferred(devices[1]))
    }

    func testResolutionReportsSystemDefaultExplicitly() {
        let device = AudioInputDevice(id: 7, uid: "built-in", name: "Mac")
        XCTAssertEqual(
            AudioDeviceSelection.resolution(
                preferredUID: nil, devices: [device], defaultDeviceID: 7),
            .systemDefault(device))
    }

    func testResolutionReportsMissingPreferenceAndFallback() {
        let fallback = AudioInputDevice(id: 7, uid: "built-in", name: "Mac")
        XCTAssertEqual(
            AudioDeviceSelection.resolution(
                preferredUID: "disconnected-usb", devices: [fallback], defaultDeviceID: 7),
            .preferredMissing(requestedUID: "disconnected-usb", fallback: fallback))
    }

    func testResolutionDoesNotInventUnavailableDefault() {
        XCTAssertEqual(
            AudioDeviceSelection.resolution(
                preferredUID: nil, devices: [], defaultDeviceID: nil),
            .systemDefault(nil))
    }

    func testActiveDeviceRemovalIsDetectedByStableUID() {
        let active = AudioInputDevice(id: 9, uid: "usb", name: "USB Mic")
        XCTAssertFalse(AudioDeviceSelection.activeDeviceWasRemoved(uid: active.uid, devices: [active]))
        XCTAssertTrue(AudioDeviceSelection.activeDeviceWasRemoved(uid: active.uid, devices: []))
        XCTAssertFalse(AudioDeviceSelection.activeDeviceWasRemoved(uid: nil, devices: []))
    }
}
