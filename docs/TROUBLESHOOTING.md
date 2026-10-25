# Troubleshooting

## Start with the status and input counters

Open Settings, move the Lofree and press/release a side button. **Copy diagnostics** reports device discovery, the open result, input/side-edge/action counts, permissions and current mode. A “posted” action means an event was submitted, not that macOS or the target app acknowledged it.

| Symptom | What to check |
| --- | --- |
| Waiting for compatible mouse | Bluetooth connection, correct model/profile, only one matching mouse; inspect discovery details. |
| Mouse access blocked / `0xE00002E2` | macOS denied opening the device (`kIOReturnNotPermitted`); investigate this installed build's Input Monitoring approval. |
| Mouse open, zero reports | Move/click the mouse, release held buttons, check competing remappers and input access. |
| Reports arrive, side edges absent | Check the raw profile/hardware; don't assume an advertised descriptor element is an actual received side signal. |
| Side edges arrive, Accessibility false | Input works but output is blocked; approve the currently installed app and restart it. |
| Posted Back/Forward, no navigation | Use a supported browser/Finder with actual history and content focus; check layout and app shortcuts. |
| Posted Spaces action, no switching | Test Control–Left/Right physically; check enabled Mission Control shortcuts and available Spaces. |
| Double navigation | Stop competing mappings; use either built-in actions or bridge mode. |

## Enabled permissions but access is denied after an update

An enabled entry can belong to an older locally signed build. Keep one app copy in Applications and quit it before renewing approval.

1. Quit the mapper completely.
2. In Privacy & Security → Input Monitoring and Accessibility, remove only this app's old entries.
3. Add the current Applications copy and approve it. Use **Grant permissions / retry** if the app needs to request an entry.
4. Quit/reopen after approval.

If the entries remain stale, you can reset only this app's two approval records in Terminal, then reopen and approve it again:

```sh
tccutil reset ListenEvent local.lofree.bluetoothmapper
tccutil reset Accessibility local.lofree.bluetoothmapper
```

These commands revoke this app's existing approvals; they do not grant access or reset other apps. Do not use system-wide resets, disable SIP, or run the app as root to get around this issue. Rebuilding again before completing approval can change the code identity again.

Apple explains that an ad-hoc signature's designated requirement is tied to that version of the code:
https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements

## Spaces shortcuts

The 0.4.2 Spaces presets assume Control–Left/Right; the app does not read customized system shortcuts automatically. Check System Settings → Keyboard → Keyboard Shortcuts → Mission Control. You can retain your customization and use a supported custom recorded shortcut in this app, or choose matching system shortcuts yourself. Nothing changes macOS shortcuts automatically.

The custom recorder currently captures Command/Option/Control/Shift, not Fn-only modifiers. Function-key-only customizations can therefore need a code/configuration improvement rather than repeated permission changes. Report the shortcut combination and OS version; do not post your entire system preference file.

## Learning and reconnection

Learning only sets the order of the two already-decoded signals; it cannot repair a denied device open. One successful Learn Back or Learn Forward sets the complementary order too and saves it across launches.

After a fresh connection, release both side buttons and move/click the mouse normally once. The decoder waits for a neutral report so a button held during connection does not become an accidental action.

## Reporting a bug

[Open an issue](https://github.com/newsman1/lofree-touch-macos/issues) with:

- macOS and app version, mouse model/connection mode.
- Which actions work and which fail.
- Whether the corresponding physical keyboard shortcut works.
- Relevant diagnostic output, with personal paths removed.
- Mac Mouse Fix version if bridge mode is involved.

Please distinguish this app's built-in actions from Mac Mouse Fix bridge behavior.
