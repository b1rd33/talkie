import Foundation

// Talkie license generator.
// Compiled together with the app's Talkie/Licensing/LicenseKey.swift and
// LicenseSecret.swift (see build command in tools/keygen or the Phase 5 plan),
// so the HMAC secret and key format can never drift from the app.
//
// Usage: talkie-keygen <machineID> <days> [name]

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    die("""
    Usage: talkie-keygen <machineID> <days> [name]
      machineID  8 hex chars shown in Talkie's Settings → License tab
      days       license validity in days from today (36500 = perpetual)
      name       optional licensee name (printed only, not encoded in the key)
    """)
}

let machineID = arguments[1].uppercased()
guard machineID.count == 8, machineID.allSatisfy({ $0.isHexDigit }) else {
    die("Error: machineID must be 8 hex characters (got \"\(arguments[1])\")")
}
guard let days = Int(arguments[2]), days > 0 else {
    die("Error: days must be a positive integer (got \"\(arguments[2])\")")
}
let name = arguments.count > 3 ? arguments[3] : "—"

// The key encodes days since 2024-01-01 as UInt16.
let baseDate = DateComponents(calendar: .current, year: 2024, month: 1, day: 1).date!
let expiryDate = Calendar.current.date(byAdding: .day, value: days, to: Date())!
let expiryDays = Calendar.current.dateComponents([.day], from: baseDate, to: expiryDate).day!
guard expiryDays > 0, expiryDays <= 65_535 else {
    die("Error: expiry is outside the key format's UInt16 day range (1...65535 days after 2024-01-01)")
}

let key = LicenseKeyEncoder.encode(machineID: machineID, expiryDays: expiryDays)

print("Talkie License")
print("==============")
print("Licensee:  \(name)")
print("Machine:   \(machineID)")
print("Expires:   \(expiryDate.formatted(date: .abbreviated, time: .omitted)) (\(days) days)")
print("")
print("LICENSE KEY: \(key)")
