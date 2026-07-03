import AppKit
import Observation

/// AppKit entry point. SwiftUI's MenuBarExtra can't tell left from right click,
/// so we drive an NSStatusItem directly: left-click toggles stay-awake,
/// right-click (or ctrl-click) opens the menu.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        // Keep out of the Dock / app switcher even when the raw SPM binary is run
        // directly (the LSUIElement Info.plist handles the bundled .app case).
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }

    private let state = ClamshellState()
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        observeState()
    }

    /// Re-render the button whenever observed state changes (Observation has no
    /// persistent subscription, so re-arm tracking after each change).
    private func observeState() {
        withObservationTracking {
            updateButton()
        } onChange: {
            Task { @MainActor in Self.delegate?.observeState() }
        }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        // Locked laptop = lid stays awake; open laptop = normal sleep on lid close.
        let symbol = state.isOn ? "lock.laptopcomputer" : "laptopcomputer"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Lidless")
        button.appearsDisabled = state.busy
        button.toolTip = state.isOn
            ? "Staying awake on lid close — click to disable"
            : "Sleeps on lid close — click to stay awake"
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            state.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let toggleItem = NSMenuItem(
            title: "Stay awake on lid close",
            action: #selector(toggleClicked),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = state.isOn ? .on : .off
        toggleItem.isEnabled = !state.busy
        menu.addItem(toggleItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        // Attach the menu only for this click so the next left-click still
        // reaches our action instead of opening the menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleClicked() {
        state.toggle()
    }
}
