/// Current app version. Keep in sync with the VERSION file at the repo root —
/// build.sh fails the build if they drift. The update checker compares this
/// against VERSION on GitHub main.
enum AppVersion {
    static let current = "1.0.0"
}
