import AppKit
import Foundation

/// Checks GitHub for a newer released version (the raw VERSION file on main)
/// and hands updating off to the install script running in Terminal — the
/// installer already stops a running copy and replaces the app in place.
enum UpdateChecker {
    static let versionURL = URL(string: "https://raw.githubusercontent.com/abhi12299/lidless/main/VERSION")!
    static let installCommand = "curl -fsSL https://raw.githubusercontent.com/abhi12299/lidless/main/install.sh | bash"

    enum UpdateError: LocalizedError {
        case badResponse
        case malformedVersion(String)
        case updaterLaunchFailed

        var errorDescription: String? {
            switch self {
            case .badResponse:
                return "Couldn't reach GitHub to check the latest version."
            case .malformedVersion(let raw):
                return "GitHub returned an unrecognized version: “\(raw)”."
            case .updaterLaunchFailed:
                return "Couldn't open the updater in Terminal."
            }
        }
    }

    /// Fetch the latest released version string (e.g. "1.2.0") from GitHub.
    static func fetchLatestVersion() async throws -> String {
        var request = URLRequest(url: versionURL)
        // raw.githubusercontent.com caches aggressively; always revalidate.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else {
            throw UpdateError.badResponse
        }
        let version = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !numericParts(of: version).isEmpty else {
            throw UpdateError.malformedVersion(version)
        }
        return version
    }

    /// Semver-style compare: numeric dot-separated fields, missing fields are
    /// zero ("1.0" == "1.0.0"), an optional leading "v" is ignored.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = numericParts(of: remote), l = numericParts(of: local)
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func numericParts(of version: String) -> [Int] {
        var v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        let fields = v.split(separator: ".")
        let parts = fields.compactMap { Int($0) }
        // Reject strings that aren't purely numeric dot-fields (e.g. "abc").
        return parts.count == fields.count ? parts : []
    }

    /// Run the installer in a visible Terminal window via a temp .command file
    /// (no automation/TCC permission needed). The installer pkills this app,
    /// rebuilds, reinstalls, and relaunches — the script survives us because
    /// Terminal owns it.
    static func launchUpdater() throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("lidless-update.command")
        let contents = """
        #!/bin/bash
        echo "Updating Lidless — this stops the app, rebuilds, and reinstalls it."
        \(installCommand)
        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        guard NSWorkspace.shared.open(script) else {
            throw UpdateError.updaterLaunchFailed
        }
    }
}
