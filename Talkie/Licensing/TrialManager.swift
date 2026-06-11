import Foundation
import CryptoKit

/// 14-day no-key trial (spec §9). Stateless reader over the Keychain seal:
/// "machineID|yyyy-MM-dd|hmac-hex". The seal is HMAC-signed with the shared
/// license secret and keyed to this machine, so editing it, copying it to
/// another Mac, or deleting-and-reseal-later all behave safely. Clock
/// rollback (now before the sealed start) counts as expired.
struct TrialManager {
    static let trialLength = 14 // days

    private let keychain: KeychainStore
    private let machineID: () -> String
    private let now: () -> Date
    private let secret: String

    init(keychain: KeychainStore,
         machineID: @escaping () -> String = { MachineIdentity.machineID },
         now: @escaping () -> Date = Date.init,
         secret: String = LicenseSecret.value) {
        self.keychain = keychain
        self.machineID = machineID
        self.now = now
        self.secret = secret
    }

    /// Has the user ever started the trial on this machine (valid seal present)?
    var hasStarted: Bool { sealedStartDate() != nil }

    var isActive: Bool { hasStarted && daysRemaining > 0 }

    var daysRemaining: Int {
        guard let start = sealedStartDate() else { return 0 }
        let current = now()
        guard current >= start else { return 0 } // clock rolled back ⇒ expired
        let elapsed = Self.utcCalendar.dateComponents([.day], from: start, to: current).day ?? Int.max
        return max(0, Self.trialLength - elapsed)
    }

    /// Writes the seal. No-op if a valid seal already exists (a trial can't restart).
    /// Called only when the user clicks "Start 14-day trial" in onboarding — never automatically.
    func startTrial() {
        guard sealedStartDate() == nil else { return }
        let day = Self.dayFormatter.string(from: now())
        let signature = Self.hmacHex("\(machineID())|\(day)", secret: secret)
        keychain.write("\(machineID())|\(day)|\(signature)", for: .trialSeal)
    }

    /// Start date iff the seal exists, parses, verifies, and is for this machine.
    private func sealedStartDate() -> Date? {
        #if DEBUG
        // Debug-only override for forcing trial states during development.
        // (Release-build expiry testing uses the system clock — see Phase 6's
        // testing matrix.) Run the binary directly (`open` drops env vars):
        //   TALKIE_TRIAL_START=2026-01-01 .../Talkie.app/Contents/MacOS/Talkie
        if let forced = ProcessInfo.processInfo.environment["TALKIE_TRIAL_START"],
           let date = Self.dayFormatter.date(from: forced) {
            return date
        }
        #endif
        guard let sealed = keychain.read(.trialSeal) else { return nil }
        let parts = sealed.split(separator: "|").map(String.init)
        guard parts.count == 3 else { return nil }
        let (sealMachine, day, signature) = (parts[0], parts[1], parts[2])
        guard sealMachine == machineID() else { return nil } // seal from another Mac
        guard Self.hmacHex("\(sealMachine)|\(day)", secret: secret) == signature else { return nil } // tampered
        return Self.dayFormatter.date(from: day)
    }

    static func hmacHex(_ message: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    /// Day-granularity, UTC-pinned: deterministic across timezones and DST.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}
