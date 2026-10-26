<img src="Assets/Icon-preview.png" width="96" alt="Lofree Bluetooth Mapper icon">

# Lofree Touch Bluetooth Mapper

Get the Lofree Touch's side buttons working over Bluetooth on macOS, with custom actions or Mac Mouse Fix.

[Download v0.4.2](https://github.com/newsman1/lofree-touch-macos/releases/tag/v0.4.2) · [Setup help](docs/TROUBLESHOOTING.md) · [Report a bug](https://github.com/newsman1/lofree-touch-macos/issues)

**Experimental. Requires Apple Silicon and macOS 15 or later. Tested on Sequoia 15.8.1 with the Touch@LOFREE Bluetooth profile.**

## What it does

[Lofree's product page](https://www.lofree.co/products/lofree-touch-pbt-wireless-mouse) notes that Back/Forward is not supported over Bluetooth on Macs. This app reads the side-button signals directly from the mouse and translates them into actions macOS can use.

- Back/Forward, custom keyboard shortcuts, and separate click, double-click and hold actions.
- Optional bridge mode that lets Mac Mouse Fix handle the buttons.
- Saved assignments, launch at login and automatic reconnection.
- A small menu-bar icon with no Dock icon.

It installs no driver and changes no pointer, scrolling or trackpad settings.

## Install

1. Download **LofreeBluetoothMapper-v0.4.2-arm64.zip** from the [release page](https://github.com/newsman1/lofree-touch-macos/releases/tag/v0.4.2), extract it, and move the app to **Applications**.
2. Open it. This build is ad-hoc signed and **not notarized**, so macOS may block it. If you choose to trust it, use the per-app **Open Anyway** option in Privacy & Security. You can also inspect and build the source. Do not disable Gatekeeper or SIP.
3. Click **Grant permissions / retry** and approve this app under **Input Monitoring** and **Accessibility**. Quit and reopen if requested.
4. Connect the Lofree over Bluetooth, with the USB receiver unplugged. Choose **Built-in actions** and leave **Enable side buttons** on.
5. Test Back/Forward in your browser. Use **Swap** or **Learn Back / Learn Forward** if needed. Assignments are saved.

Close Settings to keep the app running in the menu bar. **Pause** preserves your settings; **Quit** stops the app. Check **Launch at login** if you want automatic startup after signing in.

## Use with Mac Mouse Fix

Run [Mac Mouse Fix](https://macmousefix.com/), select **Mac Mouse Fix bridge (experimental)** in this app, then assign the side buttons as buttons **4/5** in Mac Mouse Fix.

Bridge mode turns off this app's built-in actions. Recognition has been tested with Mac Mouse Fix 3.1.0, but other versions and hold/drag gestures may behave differently.

## Known limits

- Only the verified Touch@LOFREE Bluetooth report profile is supported. Different firmware/models, USB modes and multiple matching mice are not covered.
- Spaces presets send **Control–Left/Right**. They do not automatically follow customized macOS shortcuts. Fn-only shortcut recording is limited.
- Navigation presets assume US keyboard keycodes; layouts and app shortcuts can affect the result.
- Reverse scrolling, smooth scrolling and animated trackpad gestures are not implemented.
- Ad-hoc signed updates may need fresh permission approval. See [troubleshooting](docs/TROUBLESHOOTING.md) before changing settings repeatedly.

See [Usage](docs/USAGE.md) for action timing, compatibility, privacy and uninstall instructions.

## Build

Requires Apple Command Line Tools and Python 3, with no third-party packages.

```sh
sh build.sh
sh test.sh
```

See [Development](docs/DEVELOPMENT.md) for the report format and tests.

## Credits and license

Created with OpenAI Codex and tested on a physical Lofree Touch. [MIT license](LICENSE), copyright 2026 newsman1. [Artwork credits](Assets/ARTWORK.md).

An independent community project, not affiliated with Lofree or Mac Mouse Fix.
