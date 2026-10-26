# Usage

## Button assignments

Each logical side button has separate click, double-click and hold assignments. By default, clicks navigate Back/Forward and the other gestures do nothing.

- Clicks run on release. With a double-click action assigned, an isolated single click waits 0.3 seconds.
- Double-clicks run their assigned action instead of two single-click actions.
- Holds run once after 0.5 seconds, without also clicking on release.
- An unassigned hold lasting two seconds or longer does not become a click.

Choose from navigation, tab switching, Copy/Paste, Undo/Redo, Mission Control, app windows, Spaces, Launchpad, Show Desktop, Spotlight, screenshot selection and custom shortcuts.

Learning saves the order of the two decoded side signals. It cannot repair a device-open or permission failure. One successful Learn Back or Learn Forward also determines the complementary assignment.

After reconnecting, release both side buttons and move/click the mouse normally once if the first side press is ignored. The decoder waits for a neutral report to avoid acting on a button held during connection.

## Shortcuts and focus

Back/Forward target Safari, Finder, Chrome, Edge, Brave and Firefox. App shortcuts target the foreground process; system actions and custom shortcuts use the global event stream. Presets use physical US keyboard keycodes, so different layouts or customized shortcuts can change their behavior.

The Spaces presets use Control–Left/Right and do not discover customized system shortcuts. Show Desktop sends F11. Launchpad opens the stock Sequoia Launchpad app.

To record a custom shortcut, select that action and click Record shortcut in Settings. Esc cancels. Recording captures only keys sent to this window, stores keycode plus Command/Option/Control/Shift, and does not monitor typing globally. Fn-only modifiers are not preserved in this release.

Modifier-held side presses/releases are skipped in Built-in mode. Focus changes, configuration changes, pause, sleep and disconnection cancel pending gestures.

## Mac Mouse Fix bridge

Bridge mode emits synthetic mouse buttons 4 and 5 and disables built-in actions. Mac Mouse Fix may treat them as unidentified input rather than as the physical Lofree. Compatibility depends on its version/configuration; full hold-and-drag behavior is not established.

Synthetic button downs are released on cancellation, focus change, pause, mode change, sleep, disconnection and normal Quit. A five-second timeout also releases them, so longer bridge holds are unsupported. A process crash cannot guarantee cleanup.

## Compatibility

The verified device identifies as Touch@LOFREE over Bluetooth Low Energy, VID 9354 / PID 33382, with the descriptor pinned in `Source/SideDecoder.swift`. Other models, firmware and USB connection modes are not covered by this profile. The app will not guess between multiple matching mice.

Testing has been on an Apple Silicon Mac running Sequoia 15.8.1. The build targets macOS 15 or later; wider compatibility is not established.

## Daily operation

Closing Settings leaves the app running in the menu bar. Pause is remembered across launches and preserves action choices. Resume reconnects with those saved choices.

Launch at login is requested on the first run from Applications, subject to macOS approval. Later user disablement is respected. Sleep closes the device connection and wake starts connection retries. Quitting leaves the app closed until it is reopened or launched at the next login; it does not relaunch itself after a deliberate Quit.

Restore defaults resets action choices, mode and button order, while retaining enabled/paused state and login settings.

## Privacy

The app has no network access, analytics or automatic updates. It installs no driver or privileged helper, sends no HID output/feature reports, seizes no device, suppresses no original input, and changes no pointer/scroll/trackpad settings.

The selected device's input report contains motion and wheel data, but the decoder ignores those bytes. Output consists of assigned synthetic shortcuts or bridge button events, using an event source with zero local-input suppression interval.

Preferences are stored locally under `local.lofree.bluetoothmapper`, including enabled state, mode, button order, assignments, chosen shortcuts and onboarding/login bookkeeping. No typing history or raw report history is saved. The bounded diagnostic log stays in memory; Copy diagnostics explicitly writes it to the clipboard. Remove personal paths before sharing it.

## Uninstall

1. Disable Launch at login in the app or remove it in System Settings → General → Login Items.
2. Quit the app.
3. Remove its Input Monitoring and Accessibility entries in Privacy & Security.
4. Delete the app.

Optionally, after quitting, run `defaults delete local.lofree.bluetoothmapper` to remove its saved preferences. No pointer, trackpad or keyboard settings need restoration.

For permission and shortcut problems, see [Troubleshooting](TROUBLESHOOTING.md).
