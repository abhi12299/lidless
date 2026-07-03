<div align="center">

# 🔒 Lidless

**Keep your MacBook running with the lid closed.** A one-click menu-bar toggle for clamshell stay-awake.

</div>

---

Built for **long-running AI agents**. Kick off an overnight coding agent, a batch of
LLM jobs, or a multi-hour eval, close the lid, and walk away — no external display,
no charger, no Mac dropping to sleep mid-run.

Lidless flips macOS's built-in `pmset -a disablesleep` flag from the menu bar. No kernel extension, no daemon, ~200 lines of SwiftUI.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/abhi12299/lidless/main/install.sh | bash
```

Builds from source and installs to `/Applications`, then asks whether to launch now
and start at login. Needs **macOS 14+** and the Xcode Command Line Tools
(`xcode-select --install` — the installer offers to run it).

## Usage

Click the menu-bar laptop icon and toggle **“Stay awake on lid close.”**

|           Icon           | State                            |
| :----------------------: | -------------------------------- |
|     `laptopcomputer`     | Normal — sleeps on lid close     |
| `lock.laptopcomputer` 🔒 | Awake — stays running lid-closed |

The first toggle shows one admin prompt to install a passwordless helper; every
toggle after is silent. **⌘Q** quits without changing the current setting.

## How it works

`pmset -a disablesleep` needs root, so on first use Lidless installs one narrowly
scoped sudoers rule (`/etc/sudoers.d/lidless`) allowing exactly two commands and
nothing else:

```
<you> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
```

It's validated with `visudo -cf` before install, then every toggle runs `sudo -n`
silently. Read it: [`PmsetService.swift`](Sources/Lidless/PmsetService.swift).

## Uninstall

```bash
rm -rf /Applications/Lidless.app
launchctl unload ~/Library/LaunchAgents/com.lidless.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.lidless.plist
sudo rm -f /etc/sudoers.d/lidless
```

## Build from source

```bash
git clone https://github.com/abhi12299/lidless.git && cd lidless
./build.sh              # → dist/Lidless.app
open dist/Lidless.app
```

## License

[MIT](LICENSE) © 2026
