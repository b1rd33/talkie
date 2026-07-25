import AppKit
import AVFoundation
import ApplicationServices
import Foundation
import Observation

enum NotificationDestination: String, CaseIterable, Equatable {
    case microphone
    case accessibility
    case engines

    var action: String { "open.\(rawValue)" }

    init?(action: String) {
        guard action.hasPrefix("open.") else { return nil }
        self.init(rawValue: String(action.dropFirst("open.".count)))
    }

    var systemSettingsURL: URL? {
        switch self {
        case .microphone:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .engines:
            nil
        }
    }
}

struct PermissionHealth: Equatable {
    let microphoneGranted: Bool
    let accessibilityGranted: Bool

    var missing: [NotificationDestination] {
        var result: [NotificationDestination] = []
        if !microphoneGranted { result.append(.microphone) }
        if !accessibilityGranted { result.append(.accessibility) }
        return result
    }
}

@MainActor
protocol PermissionManaging: AnyObject {
    var microphoneStatus: AVAuthorizationStatus { get }
    var accessibilityGranted: Bool { get }
    func refresh()
    func requestMicrophoneAccess()
    func openSettings(for destination: NotificationDestination)
}

@MainActor
@Observable
final class PermissionManager: PermissionManaging {
    private(set) var microphoneStatus: AVAuthorizationStatus
    private(set) var accessibilityGranted: Bool

    @ObservationIgnored private let microphoneStatusProvider: () -> AVAuthorizationStatus
    @ObservationIgnored private let accessibilityStatusProvider: () -> Bool
    @ObservationIgnored private let requestMicrophone: (@escaping (Bool) -> Void) -> Void
    @ObservationIgnored private let openURL: (URL) -> Void

    init(microphoneStatus: @escaping () -> AVAuthorizationStatus = {
             AVCaptureDevice.authorizationStatus(for: .audio)
         },
         accessibilityStatus: @escaping () -> Bool = { AXIsProcessTrusted() },
         requestMicrophone: @escaping (@escaping (Bool) -> Void) -> Void = { completion in
             AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
         },
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        microphoneStatusProvider = microphoneStatus
        accessibilityStatusProvider = accessibilityStatus
        self.requestMicrophone = requestMicrophone
        self.openURL = openURL
        self.microphoneStatus = microphoneStatus()
        accessibilityGranted = accessibilityStatus()
    }

    var health: PermissionHealth {
        PermissionHealth(microphoneGranted: microphoneStatus == .authorized,
                         accessibilityGranted: accessibilityGranted)
    }

    func refresh() {
        microphoneStatus = microphoneStatusProvider()
        accessibilityGranted = accessibilityStatusProvider()
    }

    func requestMicrophoneAccess() {
        requestMicrophone { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func openSettings(for destination: NotificationDestination) {
        guard let url = destination.systemSettingsURL else { return }
        openURL(url)
    }
}
