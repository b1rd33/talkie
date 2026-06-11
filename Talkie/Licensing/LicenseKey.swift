import Foundation
import CryptoKit

/// License key data structure (ported from Fluidscribe).
/// Format: XXXXX-XXXXX-XXXXX-XXXXX (20 chars + 3 dashes)
/// Encodes: machineID (8 hex) + expiry days (2 bytes) + truncated HMAC signature.
struct LicenseKey {
    let name: String           // Licensee label (not encoded in the key)
    let machineID: String      // Hardware fingerprint (8 hex chars)
    let expirationDate: Date   // Perpetual keys carry a far-future date (~year 2123)

    var isExpired: Bool {
        Date() > expirationDate
    }

    var daysRemaining: Int {
        let remaining = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
        return max(0, remaining)
    }

    var expirationFormatted: String {
        expirationDate.formatted(date: .abbreviated, time: .omitted)
    }
}

/// License validation result (ported verbatim).
enum LicenseValidationResult {
    case valid
    case expired
    case invalidSignature
    case machineMismatch
    case invalidFormat
    case notFound

    var message: String {
        switch self {
        case .valid: return "License is valid"
        case .expired: return "License has expired"
        case .invalidSignature: return "Invalid license key"
        case .machineMismatch: return "License is for a different computer"
        case .invalidFormat: return "Invalid license format"
        case .notFound: return "No license found"
        }
    }
}

/// Short license key codec using HMAC-SHA256 (ported from Fluidscribe).
/// Raw layout (20 chars): 8 (machineID base32) + 4 (expiry base32) + 8 (truncated HMAC base32).
/// Expiry = days since 2024-01-01 as big-endian UInt16 (max 65535 ≈ year 2203).
/// The secret parameter exists for tests; production always uses LicenseSecret.value.
enum LicenseKeyEncoder {
    /// Base32 alphabet (no O/0/I/1 confusion)
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// Encode to short key: XXXXX-XXXXX-XXXXX-XXXXX
    static func encode(machineID: String, expiryDays: Int, secret: String = LicenseSecret.value) -> String {
        // Machine ID: 8 hex chars -> 4 bytes -> 7 base32 chars (pad to 8)
        let machineBytes = hexToBytes(machineID)
        let machineB32 = base32Encode(Data(machineBytes)).padding(toLength: 8, withPad: "A", startingAt: 0)

        // Expiry: days since 2024-01-01, 2 bytes -> 4 base32 chars
        let expiryBytes = withUnsafeBytes(of: UInt16(expiryDays).bigEndian) { Data($0) }
        let expiryB32 = base32Encode(expiryBytes).padding(toLength: 4, withPad: "A", startingAt: 0)

        // HMAC signature over machineID + expiryDays -> first 8 base32 chars
        let dataToSign = machineID + String(expiryDays)
        let sigB32 = String(computeHMAC(dataToSign, secret: secret).prefix(8))

        return formatKey(machineB32 + expiryB32 + sigB32)
    }

    /// Decode and verify. Returns nil for malformed keys and bad signatures.
    /// Machine matching is the caller's job (LicenseManager).
    static func decode(_ keyString: String, secret: String = LicenseSecret.value) -> (machineID: String, expiryDate: Date)? {
        let clean = keyString.replacingOccurrences(of: "-", with: "").uppercased()
        guard clean.count == 20 else { return nil }

        let machineB32 = String(clean.prefix(8))
        let expiryB32 = String(clean.dropFirst(8).prefix(4))
        let sigB32 = String(clean.suffix(8))

        guard let machineData = base32Decode(machineB32),
              machineData.count >= 4 else { return nil }
        let machineID = machineData.prefix(4).map { String(format: "%02X", $0) }.joined()

        guard let expiryData = base32Decode(expiryB32),
              expiryData.count >= 2 else { return nil }
        let expiryDays = Int(UInt16(bigEndian: expiryData.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }))

        let dataToSign = machineID + String(expiryDays)
        let expectedSig = String(computeHMAC(dataToSign, secret: secret).prefix(8))
        guard sigB32 == expectedSig else { return nil }

        let baseDate = DateComponents(calendar: .current, year: 2024, month: 1, day: 1).date!
        let expiryDate = Calendar.current.date(byAdding: .day, value: expiryDays, to: baseDate)!
        return (machineID, expiryDate)
    }

    /// Compute HMAC-SHA256 and return base32 encoded
    private static func computeHMAC(_ data: String, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(data.utf8), using: key)
        return base32Encode(Data(signature))
    }

    /// Format as XXXXX-XXXXX-XXXXX-XXXXX
    private static func formatKey(_ raw: String) -> String {
        var result = ""
        for (index, char) in raw.enumerated() {
            if index > 0 && index % 5 == 0 {
                result += "-"
            }
            result.append(char)
        }
        return result
    }

    /// Hex string to bytes
    private static func hexToBytes(_ hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                bytes.append(byte)
            }
            index = nextIndex
        }
        return bytes
    }

    /// Base32 encode
    private static func base32Encode(_ data: Data) -> String {
        var result = ""
        var buffer: UInt64 = 0
        var bitsInBuffer = 0

        for byte in data {
            buffer = (buffer << 8) | UInt64(byte)
            bitsInBuffer += 8

            while bitsInBuffer >= 5 {
                bitsInBuffer -= 5
                let index = Int((buffer >> bitsInBuffer) & 0x1F)
                result.append(alphabet[index])
            }
        }

        if bitsInBuffer > 0 {
            let index = Int((buffer << (5 - bitsInBuffer)) & 0x1F)
            result.append(alphabet[index])
        }

        return result
    }

    /// Base32 decode
    private static func base32Decode(_ string: String) -> Data? {
        var result = Data()
        var buffer: UInt64 = 0
        var bitsInBuffer = 0

        for char in string {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            buffer = (buffer << 5) | UInt64(index)
            bitsInBuffer += 5

            if bitsInBuffer >= 8 {
                bitsInBuffer -= 8
                result.append(UInt8((buffer >> bitsInBuffer) & 0xFF))
            }
        }

        return result
    }
}
