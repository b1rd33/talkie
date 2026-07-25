import Darwin
import Foundation

struct HostIntegrationGate {
    static let tokenEnvironmentKey = "TALKIE_HOST_INTEGRATION_TOKEN"
    static let markerEnvironmentKey = "TALKIE_HOST_INTEGRATION_MARKER"
    static let maximumMarkerAge: TimeInterval = 10 * 60

    struct Marker {
        var token: String
        var ownerUserID: uid_t
        var modifiedAt: Date
        var isRegularFile: Bool
        var permissions: mode_t
    }

    static func allows(
        environment: [String: String],
        marker: Marker?,
        now: Date,
        currentUserID: uid_t
    ) -> Bool {
        guard
            let expectedToken = environment[tokenEnvironmentKey],
            expectedToken.count >= 32,
            let markerPath = environment[markerEnvironmentKey],
            markerPath.hasPrefix("/"),
            let marker,
            marker.isRegularFile,
            marker.ownerUserID == currentUserID,
            marker.permissions & 0o077 == 0,
            marker.token == expectedToken
        else {
            return false
        }

        let age = now.timeIntervalSince(marker.modifiedAt)
        return age >= 0 && age <= maximumMarkerAge
    }

    static func isEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        now: Date = Date(),
        currentUserID: uid_t = geteuid()
    ) -> Bool {
        guard
            let path = environment[markerEnvironmentKey],
            path.hasPrefix("/")
        else {
            return false
        }

        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

        var status = stat()
        guard
            fstat(descriptor, &status) == 0,
            status.st_size > 0,
            status.st_size <= 256
        else {
            return false
        }

        let data = handle.readDataToEndOfFile()
        guard let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return false
        }

        let marker = Marker(
            token: token,
            ownerUserID: status.st_uid,
            modifiedAt: Date(
                timeIntervalSince1970: TimeInterval(status.st_mtimespec.tv_sec)
                    + TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000),
            isRegularFile: status.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
            permissions: status.st_mode & 0o777)
        return allows(
            environment: environment,
            marker: marker,
            now: now,
            currentUserID: currentUserID)
    }
}
