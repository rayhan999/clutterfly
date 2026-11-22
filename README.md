<div align="center">

<img src="icon.png" width="160" alt="Molehill icon">

# Molehill

**Clean up your Mac and run 30+ handy Mac tools from one colorful app.**

Molehill puts a friendly face on the excellent [Mole](https://github.com/tw93/Mole) cleaner and the Mac's own power tools that usually hide in Terminal.

[![Download](https://img.shields.io/github/v/release/rayhan999/mole-hill?label=download&color=ff7a59)](https://github.com/rayhan999/mole-hill/releases/latest)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-7b5cfa)
![Apple Silicon + Intel](https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-universal-5b8cff)
![Swift](https://img.shields.io/badge/SwiftUI-native-f05138)
[![Stars](https://img.shields.io/github/stars/rayhan999/mole-hill?style=social)](https://github.com/rayhan999/mole-hill/stargazers)

[**⬇️ Download**](https://github.com/rayhan999/mole-hill/releases/latest) · [Features](#-features) · [Prerequisites](#-prerequisites) · [Install](#-install) · [Safety](#%EF%B8%8F-safe-by-design) · [Build](#-build-from-source) · [FAQ](#-faq)

</div>

---

## ✨ Why Molehill?

Your Mac fills up with caches, logs, old installers, dev junk and forgotten giant files. Tools to clean that up exist, but the good free ones live in Terminal, and the friendly ones cost money.

Molehill gives you both:

- 🧹 **See before you delete.** Every clean shows a preview first: what it found, where, and how big.
- 🎨 **Made for humans.** Plain words, big buttons, colorful screens, no commands to remember.
- 🧰 **One app, many jobs.** Cleaning, disk explorer, app uninstaller, running apps, startup items, ports, battery, network speed, security check and more.
- 🪶 **Tiny and native.** About 2 MB, pure SwiftUI, no Electron, no tracking, no account.
- 🔓 **Free and open source.** Read every line it runs.

## 🚀 Features

Everything sits in a sidebar, grouped by what you want to do.

### 🧹 Clean
| | |
|---|---|
| **Deep Clean** | System and app caches, logs, browser junk and more, with a dry-run preview before anything is removed. |
| **Developer Caches** | npm, pnpm, Yarn, Bun, Homebrew, pip, Xcode DerivedData, Simulators, Gradle, Cargo, Go, CocoaPods. Sizes shown, cleaned with each tool's own command. |
| **Docker** | See what images, containers, volumes and build cache take, then prune with one click. |
| **Project Junk** | Finds `node_modules`, build folders and other leftovers in old projects. |
| **Old Installers** | `.dmg`, `.pkg` and `.zip` installers you forgot about. |
| **Large Files** | Files over 100 MB, 500 MB, 1 GB or 5 GB found instantly with Spotlight, plus Downloads older than 90 days. |
| **Time Machine Snapshots** | List and remove local snapshots that quietly hold space. |

### 🔭 Explore
| | |
|---|---|
| **Live Status** | Health score, CPU, memory, disk, network and top processes, updating every 2 seconds. |
| **Disk Explorer** | Drill into folders by size and move the big ones to the Trash. |
| **External Drives** | Explore, clean junk off and eject USB and external disks. |
| **History** | A chart of space freed over time, plus low-disk alerts from the menu bar. |

### 📦 Apps
| | |
|---|---|
| **Running Apps** | Every app *and* background process, sorted by CPU or memory, with Quit and Force Quit. |
| **Startup Items** | Everything that launches by itself, with on/off switches. |
| **Updates** | macOS updates and outdated Homebrew packages, with Upgrade All. |
| **Uninstall Apps** | Removes an app *and* the files it leaves behind. |
| **Slim Apps** | Finds apps carrying Intel code you no longer need. |

### 🌐 Network · 🔋 Power · 🛡️ System · 🛠️ Tools
| | |
|---|---|
| **Speed Test** | Download, upload, latency and responsiveness using Apple's own `networkQuality`. |
| **Network Info / Ports in Use** | Your IP, router and DNS; which apps are online; which apps listen on which ports, with Stop buttons. |
| **Battery** | Health, cycle count, capacity, temperature and charger wattage. |
| **Sleep Blockers / Caffeinate** | See who keeps your Mac awake, or keep it awake yourself with a timer. |
| **Security Check** | FileVault, Firewall, Gatekeeper and SIP at a glance (read-only). |
| **Disk First Aid** | Check your startup disk without Disk Utility. |
| **Quick Fixes** | Restart the Dock, Finder, menu bar or Wi-Fi; flush DNS; rebuild Spotlight. |
| **Tweaks** | Show hidden files, Dock auto-hide, screenshot folder and format, stop `.DS_Store` on USB drives, and more. |
| **Shortcuts** | Run your Shortcuts from big colorful buttons. |
| **Optimize, Protected Items, Touch ID for sudo, Update Mole** | Mole's maintenance tools, without Terminal. |

Plus a **menu bar item** with free space, a Keep Awake switch and quick scans.

## 📋 Prerequisites

### Required

| What | Why | How to get it |
|---|---|---|
| **macOS 14 Sonoma or later** | Molehill uses modern SwiftUI. | Apple menu → System Settings → General → Software Update |
| **Apple Silicon or Intel Mac** | The download is a universal app and runs natively on both. | — |
| **[Homebrew](https://brew.sh)** | Used to install and update Mole. | Molehill can open Terminal and install it for you, or run the command from [brew.sh](https://brew.sh). |
| **[Mole](https://github.com/tw93/Mole)** | Powers the Clean, Explore, Uninstall and Optimize tools. | Molehill offers a one-click install on first launch, or run `brew install mole`. |

### Recommended

| What | Why |
|---|---|
| **Full Disk Access** for Molehill | Without it, macOS asks for permission on every scan and some folders can't be read. Turn it on once in **System Settings → Privacy & Security → Full Disk Access**. The yellow banner in the app takes you there. |
| **An admin account** | Flush DNS, Rebuild Spotlight, deleting Time Machine snapshots and other system-wide jobs need your password. They open Terminal so you can type it yourself. |

### Optional (only for some screens)

| Screen | Needs |
|---|---|
| **Docker** | [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running |
| **Developer Caches** | Only shows caches for tools you have (npm, Yarn, Xcode, Cargo and so on) |
| **Updates → Homebrew packages** | Homebrew (already needed for Mole) |
| **Shortcuts** | Shortcuts you've made in the Shortcuts app |
| **Battery** | A MacBook (desktop Macs have no battery to show) |

### To build from source

| What | How to get it |
|---|---|
| **Xcode Command Line Tools** (the full Xcode app isn't needed) | `xcode-select --install` |
| **Git** | Included with the Command Line Tools |

## 📥 Install

1. Download **Molehill.zip** from the [latest release](https://github.com/rayhan999/mole-hill/releases/latest).
2. Unzip it and drag **Molehill** into **Applications**.
3. **First launch:** Molehill isn't signed with a paid Apple developer account, so macOS says it can't verify it. Click **Done**, open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. You only do this once.
4. Follow the yellow banner in the app to give Molehill **Full Disk Access**, so it can scan everything without asking each time.
5. No Mole yet? Molehill offers to install it for you (`brew install mole`).

## 🛡️ Safe by design

- **Preview first.** Cleans run as a dry run before anything is deleted, and deletions ask for confirmation.
- **Trash, not gone.** Files you remove from the explorer and Large Files go to the Trash, so you can put them back.
- **Your apps' data is off-limits.** Molehill won't trash files inside app data folders, and warns you about iCloud and OneDrive files.
- **Only your own processes.** System processes can't be quit from Running Apps.
- **Passwords stay with you.** Anything that needs admin rights opens Terminal so *you* type your password. Molehill never sees it.
- **Protected Items.** Pick folders that cleaning must never touch.
- **Mole's safety checks stay on.** Molehill never bypasses them.

## 🔨 Build from source

All you need is Apple's free command-line tools (`xcode-select --install`), no Xcode project.

```sh
git clone https://github.com/rayhan999/mole-hill.git
cd mole-hill
./build.sh            # builds Molehill.app and installs it into /Applications
./build.sh release    # universal build (Apple Silicon + Intel) zipped as Molehill.zip
```

Apps you build yourself open without the "can't verify" warning. Run `./Molehill.app/Contents/MacOS/Molehill --selftest` to check every parser against live data from your Mac.

## ❓ FAQ

**macOS says Molehill "can't be verified" or "is damaged". Is it safe?**
The warning appears because the app isn't signed with a paid Apple developer account, not because anything is wrong with it. Use **Open Anyway** as described in [Install](#-install). If you'd rather check the code yourself, [build it from source](#-build-from-source); apps you build on your own Mac open without the warning.

**Full Disk Access keeps turning off.**
macOS ties that permission to the exact app copy. After installing a new version, turn it on again for Molehill.

**Do I need Mole for everything?**
No. Running Apps, Startup Items, Ports, Large Files, Speed Test, Network Info, Battery, Sleep Blockers, Caffeinate, Security Check, Disk First Aid, Quick Fixes, Tweaks and Shortcuts use tools built into macOS. The cleaning, explorer, uninstall and optimize screens need Mole.

**Why does uninstalling an app finish in Terminal?**
Mole asks for a final "yes" in Terminal before it removes an app. Molehill keeps that safety step rather than skipping it.

**Does Molehill collect any data?**
No. It has no analytics, no account and no network calls of its own. The only network activity is what you start yourself, like Speed Test or Updates.

## 🙏 Credits

Cleaning, optimizing and uninstalling are powered by [**Mole**](https://github.com/tw93/Mole) by [@tw93](https://github.com/tw93). Go give it a star too. Molehill is an independent project and isn't affiliated with Mole.

---

<div align="center">

**If Molehill freed up some space for you, a ⭐ helps other Mac users find it.**

Ideas and bug reports are welcome in [Issues](https://github.com/rayhan999/mole-hill/issues).

</div>
