import Foundation

/// Shared HMAC secret for license keys AND the trial seal.
///
/// The keygen CLI (tools/keygen) compiles this exact file together with
/// LicenseKey.swift, so the generator and the app can never disagree.
///
/// Stored XOR-obfuscated (key 0x5A) so the plaintext doesn't show up in
/// `strings Talkie.app`. This only deters casual key sharing — any offline
/// licensing scheme is crackable by a motivated reverse engineer; accepted
/// trade-off per spec §9 (offline validation, no server).
///
/// Regenerate after changing the plaintext:
///   python3 -c "s='<new secret>'; print(', '.join('0x%02X' % (b ^ 0x5A) for b in s.encode()))"
enum LicenseSecret {
    // "Talkie-2026-Perpetual-License-HMAC#9F4" ^ 0x5A
    private static let obfuscated: [UInt8] = [
        0x0E, 0x3B, 0x36, 0x31, 0x33, 0x3F, 0x77, 0x68, 0x6A, 0x68,
        0x6C, 0x77, 0x0A, 0x3F, 0x28, 0x2A, 0x3F, 0x2E, 0x2F, 0x3B,
        0x36, 0x77, 0x16, 0x33, 0x39, 0x3F, 0x34, 0x29, 0x3F, 0x77,
        0x12, 0x17, 0x1B, 0x19, 0x79, 0x63, 0x1C, 0x6E,
    ]

    static var value: String {
        String(bytes: obfuscated.map { $0 ^ 0x5A }, encoding: .utf8)!
    }
}
