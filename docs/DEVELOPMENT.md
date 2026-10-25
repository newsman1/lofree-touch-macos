# Development notes

## Device and report profile

The supported Bluetooth device reports VID 9354 / PID 33382 and the exact descriptor pinned in `Source/SideDecoder.swift`.

Input report 3 has eight bytes, including its leading `03` report-ID byte. Byte 1 contains the ordinary button bits and side masks `08` / `10`; subsequent bytes contain motion/wheel data, which this decoder ignores. Changes are decoded into edges, not repeated actions for every held report.

The captured descriptor allocates five button bits but declares Button usages 1 through 3. That mismatch plausibly explains the lack of standard side-button events; it is not a verified diagnosis of macOS internals.

A live regression log showed the exact descriptor match while `IOHIDDeviceConformsTo(mouse)` returned false before open. Accordingly, that function is diagnostic only. `DeviceProfile.swift` matches IDs, Bluetooth transport and descriptor; matching also requires exactly one candidate. Do not reintroduce the redundant collection gate.

Metadata discovery is broad, but the manager is not opened and only the exact selected Lofree receives an input callback. Device access uses `kIOHIDOptionsTypeNone`. Teardown unschedules/unregisters callbacks and closes the device before freeing its callback buffer.

## Source layout

- `DeviceProfile.swift`: verified device matcher.
- `SideDecoder.swift`: input report-to-edge decoder.
- `GestureEngine.swift`: click/double-click/hold timing and cancellation.
- `Settings.swift`: persisted settings, calibration and action definitions.
- `EventFactory.swift`: independent public-Quartz extra-button event construction.
- `main.swift`: AppKit UI, HID lifecycle, reconnection, permissions, login service and action dispatch.
- `Tests/main.swift`: deterministic tests; event-construction tests never post events.
- `build_icon.py`: ICNS packaging of already-sized PNGs, without third-party dependencies.

The internal `--preview` argument shows a Settings UI with input handling, permission requests, login registration and preference writes disabled. It is for layout checks, not normal operation.

## Validation

The development environment was Apple Silicon / macOS Sequoia 15.8.1. Compilation, ad-hoc signature verification and deterministic tests passed. The original raw capture replay yielded five complete `08` gestures and eight complete `10` gestures; no private capture/log is bundled.

The user reported working basic navigation, double-click/hold actions, saved learning and Mac Mouse Fix 3.1.0 bridge recognition on the actual mouse. That does not establish compatibility with all firmware, Macs, OS versions, login/wake configurations, or MMF gestures.

The source corresponding to 0.4.2 is unchanged in this publication package. The release executable is byte-identical to the installed working executable used during development. New documentation, license and packaging do not change the binary's signature.

## Mac Mouse Fix bridge research

The upstream source inspected during development accepts synthetic events without a recognized HID sender when compiled with `NO_FILTER=1`. Its receiver checks button pressure to distinguish down/up; our event factory sets that explicitly. No sender identity is spoofed and no virtual HID driver is created.

Reference commit and files:
https://github.com/noah-nuebling/mac-mouse-fix/blob/ec3258d119ef652a98e097eb38d408ac379994e0/Helper/Core/Buttons/ButtonInputReceiver.m
https://github.com/noah-nuebling/mac-mouse-fix/blob/ec3258d119ef652a98e097eb38d408ac379994e0/Mouse%20Fix.xcodeproj/project.pbxproj

No upstream source is redistributed. The bridge implementation is independently written against public Apple APIs.

## Public distribution

The current app is ad-hoc signed, not notarized. A future Developer ID signed/notarized distribution would require the maintainer's Apple developer signing identity and notarization workflow. Do not publish keys, account credentials, local capture files or users' saved preference exports.
