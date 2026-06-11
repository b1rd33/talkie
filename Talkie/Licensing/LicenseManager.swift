import Foundation
import CryptoKit
import IOKit
import Observation

extension Notification.Name {
    /// Posted after a successful activation so UI and EntitlementStore can refresh.
    static let licenseActivated = Notification.Name("com.archiev.talkie.licenseActivated")
}

/// IOKit hardware fingerprint (ported from Fluidscribe's LicenseManager):
/// SHA256(serialNumber + "-" + hardwareUUID), first 4 bytes as 8 uppercase hex chars.
enum MachineIdentity {
    static var machineID: String {
        let serial = serialNumber() ?? "UNKNOWN"
        let uuid = hardwareUUID() ?? "UNKNOWN"
        let hash = SHA256.hash(data: Data("\(serial)-\(uuid)".utf8))
        return hash.prefix(4).map { String(format: "%02X", $0) }.joined()
    }

    private static func serialNumber() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert > 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        guard let serial = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformSerialNumberKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeUnretainedValue() as? String else { return nil }
        return serial.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hardwareUUID() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert > 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        return IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeUnretainedValue() as? String
    }
}

/// Validates, stores, and reloads the license (ported from Fluidscribe;
/// Talkie-ified: KeychainStore + injectable machineID, no singleton — AppServices owns it).
@MainActor
@Observable
final class LicenseManager {
    private(set) var isLicensed = false
    private(set) var currentLicense: LicenseKey?
    private(set) var validationResult: LicenseValidationResult = .notFound

    private let keychain: KeychainStore
    private let machineIDProvider: () -> String

    /// This machine's fingerprint — shown in the License tab so the user can
    /// send it to us; the keygen needs it to mint their key.
    var machineID: String { machineIDProvider() }

    init(keychain: KeychainStore = KeychainStore(service: "com.archiev.talkie.license"),
         machineIDProvider: @escaping () -> String = { MachineIdentity.machineID }) {
        self.keychain = keychain
        self.machineIDProvider = machineIDProvider
        loadLicense()
    }

    /// Activate a key (XXXXX-XXXXX-XXXXX-XXXXX). Valid keys are persisted to the Keychain.
    func activateLicense(keyString: String) -> LicenseValidationResult {
        guard let decoded = LicenseKeyEncoder.decode(keyString) else {
            validationResult = .invalidSignature
            return .invalidSignature
        }
        guard decoded.machineID == machineID else {
            validationResult = .machineMismatch
            return .machineMismatch
        }
        guard decoded.expiryDate > Date() else {
            validationResult = .expired
            return .expired
        }

        keychain.write(keyString, for: .licenseKey)
        currentLicense = LicenseKey(name: "Licensed", machineID: decoded.machineID,
                                    expirationDate: decoded.expiryDate)
        isLicensed = true
        validationResult = .valid
        NotificationCenter.default.post(name: .licenseActivated, object: nil)
        return .valid
    }

    /// Re-validate whatever is stored (used at launch).
    func checkLicense() { loadLicense() }

    func clearLicense() {
        keychain.delete(.licenseKey)
        isLicensed = false
        currentLicense = nil
        validationResult = .notFound
    }

    private func loadLicense() {
        guard let stored = keychain.read(.licenseKey) else {
            isLicensed = false
            currentLicense = nil
            validationResult = .notFound
            return
        }
        if activateLicense(keyString: stored) != .valid {
            clearLicense() // reference behavior: stale/foreign stored keys are purged
        }
    }
}
