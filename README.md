# mole-hill

Molehill: a colorful macOS app that frees up disk space and bundles handy Mac tools. It's a GUI for the free [Mole](https://github.com/tw93/Mole) CLI (`brew install mole`), plus screens built on macOS command-line tools.

## Install

1. Download **Molehill.zip** from the [latest release](https://github.com/rayhan999/mole-hill/releases/latest). It runs on macOS 14 or later, on Apple Silicon and Intel Macs.
2. Double-click the zip and drag **Molehill** into your **Applications** folder.
3. **First launch:** the app isn't signed with a paid Apple developer account, so macOS says it can't verify it. Click **Done**, then open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Molehill. You only need to do this once.
4. Inside the app, follow the yellow banner to give Molehill **Full Disk Access**, so scans don't keep asking for permission.
5. If Mole isn't installed, the app offers to install it for you.

## Build from source

Needs only Xcode Command Line Tools (`xcode-select --install`). Apps you build yourself open without the warning.

```sh
./build.sh && open Molehill.app
./build.sh release   # Apple Silicon + Intel build, zipped as Molehill.zip
```
