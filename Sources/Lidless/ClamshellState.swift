import Foundation
import Observation

/// Observable model backing the menu bar UI. Reads pmset state, drives the toggle,
/// and surfaces install / error status to the menu.
@MainActor
@Observable
final class ClamshellState {
    /// Whether clamshell stay-awake (SleepDisabled) is currently ON.
    var isOn: Bool = false
    /// True while a toggle/install is in flight — disables the button.
    var busy: Bool = false
    /// True once the passwordless helper (sudoers rule) is installed.
    var helperInstalled: Bool = false
    /// Last user-facing error, if any.
    var lastError: String?

    @ObservationIgnored private var timer: Timer?

    init() {
        refresh()
        // MenuBarExtra(.menu) has no "menu opened" hook, so poll to stay in sync
        // with external changes (e.g. the CLI script or a reboot resetting state).
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Cheap, privilege-free state read.
    func refresh() {
        isOn = PmsetService.isStayAwakeOn()
        helperInstalled = PmsetService.isHelperInstalled()
    }

    /// Flip stay-awake. First time, this triggers one admin prompt to install the
    /// sudoers rule; afterwards it runs silently via `sudo -n`.
    func toggle() {
        guard !busy else { return }
        busy = true
        lastError = nil
        let target = !isOn
        Task {
            do {
                // Run off the main actor: the osascript auth dialog (install path)
                // blocks its calling thread, and we don't want to freeze the UI.
                try await Task.detached(priority: .userInitiated) {
                    try PmsetService.setStayAwake(target)
                }.value
            } catch PmsetService.ToggleError.installCancelled {
                // User dismissed the auth dialog — clean no-op, not an error.
            } catch {
                lastError = error.localizedDescription
            }
            refresh()
            busy = false
        }
    }

    /// Remove the passwordless helper (one admin prompt).
    func uninstallHelper() {
        guard !busy else { return }
        busy = true
        lastError = nil
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try PmsetService.uninstallSudoersRule()
                }.value
            } catch PmsetService.ToggleError.installCancelled {
            } catch {
                lastError = error.localizedDescription
            }
            refresh()
            busy = false
        }
    }
}
