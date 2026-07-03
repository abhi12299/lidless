<div align="center">

# 🔒 Lidless

**Keep your MacBook awake with the lid closed — no external display, no charger, no fuss.**

A tiny macOS menu-bar app that flips clamshell sleep on and off with one click.

[Install](#install) · [How it works](#how-it-works) · [Usage](#usage) · [Uninstall](#uninstall) · [Build from source](#build-from-source)

</div>

---

## What is this?

By default, macOS puts your Mac to sleep the moment you close the lid unless it's
plugged into power **and** an external display. Lidless removes that restriction:
close the lid and your Mac keeps running — downloads finish, builds keep going,
your SSH sessions stay alive, music keeps playing to your AirPods.

It does this by toggling macOS's built-in `pmset -a disablesleep` flag. There's no
kernel extension, no background daemon polling your hardware, no third-party sleep
hacks — just the switch Apple already ships, exposed in your menu bar.

- **Menu-bar only.** No Dock icon, no window. A laptop icon that locks 🔒 when active.
- **One password, once.** The first toggle installs a passwordless helper via a single
  admin prompt. Every toggle after that is silent.
- **Honest about state.** Reads the real system flag every few seconds, so it's right
  even if something else changed it.
- **Tiny & native.** ~200 lines of SwiftUI. No dependencies.

> ⚠️ With the lid closed and no display, your Mac has no fans-visible airflow of a
> propped screen. Keep it somewhere ventilated for long, heavy workloads.

---

## Install

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/abhi12299/lidless/main/install.sh | bash
```

The installer will:

1. Check you're on **macOS 14 (Sonoma) or later** with the Swift toolchain.
2. Clone the repo, build a signed `Lidless.app`, and install it to `/Applications`.
3. Ask whether to **launch it now** and whether to **start it at login**.

It never asks for your password up front — only the app's first toggle does, once.

> **Requirements:** macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).
> The installer offers to install them for you if they're missing.

### Prefer to read before you pipe to `bash`?

Smart. Have a look first:

```bash
curl -fsSL https://raw.githubusercontent.com/abhi12299/lidless/main/install.sh -o install.sh
less install.sh
bash install.sh
```

---

## Usage

Click the **laptop icon** in your menu bar:

| Icon | Meaning |
| :--: | ------- |
| `laptopcomputer` | Normal — Mac sleeps when you close the lid. |
| `lock.laptopcomputer` 🔒 | Active — Mac stays awake with the lid closed. |

Flip **“Stay awake on lid close”** on, close the lid, walk away. Toggle it off when
you're done. **Quit** (⌘Q) exits the app but leaves the current setting as-is.

The **first** time you toggle, macOS shows one admin prompt so Lidless can install a
small passwordless rule (see below). After that, toggling is instant and silent.

---

## How it works

Lidless is a thin, auditable wrapper around one system command:

```
pmset -a disablesleep 1   # stay awake on lid close
pmset -a disablesleep 0   # back to normal
```

`pmset` needs root, and we don't want a password prompt on every click. So on the
first toggle, Lidless installs a **narrowly scoped** sudoers rule:

```
<you> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

That's the *entire* privilege it grants — those two exact commands, nothing else. It's
written to `/etc/sudoers.d/lidless`, validated with `visudo -cf` before install so a
broken file can never lock you out, and installed via one `osascript … with
administrator privileges` prompt (Touch ID or password). Every subsequent toggle runs
`sudo -n pmset …`, which succeeds silently because of that rule.

Read the whole thing — it's short:
[`PmsetService.swift`](Sources/Lidless/PmsetService.swift).

---

## Uninstall

```bash
# 1. Quit the app (menu bar → Quit), then remove it:
rm -rf /Applications/Lidless.app

# 2. Remove the launch-at-login agent, if you enabled it:
launchctl unload ~/Library/LaunchAgents/com.saxecap.Lidless.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.saxecap.Lidless.plist

# 3. Remove the passwordless helper rule:
sudo rm -f /etc/sudoers.d/lidless
```

That's everything Lidless ever touches.

---

## Build from source

No Xcode GUI required — just the Command Line Tools.

```bash
git clone https://github.com/abhi12299/lidless.git
cd lidless
./build.sh                      # → dist/Lidless.app (ad-hoc signed)
open dist/Lidless.app           # run it
cp -R dist/Lidless.app /Applications/   # or install it
```

### Project layout

```
Sources/Lidless/
  LidlessApp.swift      SwiftUI MenuBarExtra + menu contents
  ClamshellState.swift  Observable model; polls state, drives the toggle
  PmsetService.swift    pmset wrappers + the privileged sudoers install
Resources/Info.plist    LSUIElement (menu-bar-only) app metadata
build.sh                swift build → assemble & codesign the .app bundle
install-sudoers.sh      Manual fallback for the passwordless rule
install.sh              The curl | bash installer
```

Built with SwiftUI's `MenuBarExtra` (macOS 14+) and the `@Observable` macro. Zero
external dependencies.

---

## FAQ

**Does this drain my battery?** It keeps the Mac *running*, so yes — a closed lid on
Lidless uses power like an open one. Toggle it off when you don't need it.

**Is it safe to run heavy workloads lid-closed?** It works, but a closed MacBook has
less airflow. For sustained CPU/GPU load, keep it ventilated.

**Will it survive a reboot?** The `disablesleep` flag resets on reboot; Lidless reads
the real state on launch, so the menu bar always shows the truth. Re-toggle after a
restart if you want it back on.

**Why does it need my password once?** To install the two-command sudoers rule. After
that, never again — see [How it works](#how-it-works).

---

## License

[MIT](LICENSE) © 2026
