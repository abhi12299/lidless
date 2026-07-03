import SwiftUI
import AppKit

@main
struct LidlessApp: App {
    @State private var state = ClamshellState()

    init() {
        // Keep out of the Dock / app switcher even when the raw SPM binary is run
        // directly (the LSUIElement Info.plist handles the bundled .app case).
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state)
        } label: {
            // Locked laptop = lid stays awake; open laptop = normal sleep on lid close.
            Image(systemName: state.isOn ? "lock.laptopcomputer" : "laptopcomputer")
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Menu contents. In `.menu` style only menu-renderable controls work
/// (Button, Text, Divider, Toggle, Menu) — no custom layout.
struct MenuContent: View {
    let state: ClamshellState

    var body: some View {
        Toggle("Stay awake on lid close", isOn: Binding(
            get: { state.isOn },
            set: { _ in state.toggle() }
        ))
        .disabled(state.busy)

        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
