import Foundation

/// Thin wrappers around `pmset` and the privileged install of the sudoers rule
/// that lets us write `disablesleep` without a password prompt.
enum PmsetService {

    static let pmsetPath = "/usr/bin/pmset"
    static let sudoPath = "/usr/bin/sudo"
    static let sudoersRulePath = "/etc/sudoers.d/lidless"

    enum ToggleError: Error, LocalizedError {
        case needsInstall          // sudoers rule missing / `sudo -n` failed
        case installCancelled      // user dismissed the admin auth dialog
        case installFailed(String) // visudo/install reported an error
        case writeFailed(String)   // pmset returned non-zero even after install

        var errorDescription: String? {
            switch self {
            case .needsInstall: return "Helper not installed yet."
            case .installCancelled: return "Authorization was cancelled."
            case .installFailed(let m): return "Helper install failed: \(m)"
            case .writeFailed(let m): return "pmset failed: \(m)"
            }
        }
    }

    // MARK: - Read (no privileges)

    /// Returns true when clamshell stay-awake (SleepDisabled) is currently ON.
    static func isStayAwakeOn() -> Bool {
        let out = runCapturing(pmsetPath, ["-g"]).stdout
        // Line looks like: " SleepDisabled         1"
        for line in out.split(separator: "\n") where line.contains("SleepDisabled") {
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if let last = parts.last { return last == "1" }
        }
        return false
    }

    // MARK: - Write (privileged, silent after one-time install)

    /// Sets disablesleep to the desired value. Tries the silent `sudo -n` path first;
    /// if the sudoers rule is missing, installs it (one admin prompt) and retries.
    static func setStayAwake(_ on: Bool) throws {
        let value = on ? "1" : "0"
        if trySilentWrite(value) { return }

        // Silent path failed — (re)install the rule, then retry once.
        try installSudoersRule()
        guard trySilentWrite(value) else {
            throw ToggleError.writeFailed("write still failed after installing helper")
        }
    }

    /// `sudo -n pmset -a disablesleep <value>` — succeeds silently iff the rule exists.
    private static func trySilentWrite(_ value: String) -> Bool {
        let r = runCapturing(sudoPath, ["-n", pmsetPath, "-a", "disablesleep", value])
        return r.status == 0
    }

    /// True when the passwordless sudoers rule is already installed and valid.
    /// `sudo -n -l <cmd>` lists the command if allowed without a password (exit 0),
    /// otherwise exits non-zero (and never prompts, thanks to -n).
    static func isHelperInstalled() -> Bool {
        let r = runCapturing(sudoPath, ["-n", "-l", pmsetPath, "-a", "disablesleep", "0"])
        return r.status == 0
    }

    // MARK: - One-time privileged install via osascript

    /// Writes the rule + an installer script to a temp dir, then runs the installer
    /// once with administrator privileges (single Touch ID / password prompt).
    static func installSudoersRule() throws {
        let user = NSUserName()
        let rule = """
        \(user) ALL=(root) NOPASSWD: \(pmsetPath) -a disablesleep 0, \(pmsetPath) -a disablesleep 1
        """

        let tmp = FileManager.default.temporaryDirectory
        let ruleURL = tmp.appendingPathComponent("clampshell-toggler.sudoers")
        let scriptURL = tmp.appendingPathComponent("clampshell-install.sh")

        let installer = """
        #!/bin/sh
        set -e
        RULE="\(ruleURL.path)"
        DEST="\(sudoersRulePath)"
        # Validate syntax before installing — never write a broken sudoers file.
        /usr/sbin/visudo -cf "$RULE"
        /usr/bin/install -m 0440 -o root -g wheel "$RULE" "$DEST"
        """

        do {
            try rule.write(to: ruleURL, atomically: true, encoding: .utf8)
            try installer.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            throw ToggleError.installFailed(error.localizedDescription)
        }

        try runPrivilegedScript(scriptURL.path)
    }

    /// Removes the sudoers rule (also one admin prompt).
    static func uninstallSudoersRule() throws {
        let tmp = FileManager.default.temporaryDirectory
        let scriptURL = tmp.appendingPathComponent("clampshell-uninstall.sh")
        let installer = """
        #!/bin/sh
        /bin/rm -f "\(sudoersRulePath)"
        """
        do {
            try installer.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            throw ToggleError.installFailed(error.localizedDescription)
        }
        try runPrivilegedScript(scriptURL.path)
    }

    /// Runs `/bin/sh <path>` as root via AppleScript `with administrator privileges`.
    private static func runPrivilegedScript(_ path: String) throws {
        // Build: do shell script "/bin/sh '<path>'" with administrator privileges
        let appleScript = "do shell script \"/bin/sh '\(path)'\" with administrator privileges"
        let r = runCapturing("/usr/bin/osascript", ["-e", appleScript])
        if r.status != 0 {
            // osascript error -128 == user cancelled the auth dialog.
            if r.stderr.contains("-128") || r.stderr.contains("User canceled") {
                throw ToggleError.installCancelled
            }
            throw ToggleError.installFailed(r.stderr.isEmpty ? r.stdout : r.stderr)
        }
    }

    // MARK: - Process helper

    private struct Result { let status: Int32; let stdout: String; let stderr: String }

    private static func runCapturing(_ launchPath: String, _ args: [String]) -> Result {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let outPipe = Pipe(); let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return Result(
            status: proc.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
