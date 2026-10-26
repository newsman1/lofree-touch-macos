# Development

## Source layout

| File | Purpose |
| --- | --- |
| `Source/DeviceProfile.swift` | Matches the verified Bluetooth device profile. |
| `Source/SideDecoder.swift` | Decodes raw reports into side-button edges. |
| `Source/GestureEngine.swift` | Handles click, double-click, hold and cancellation. |
| `Source/Settings.swift` | Stores action choices and button order. |
| `Source/EventFactory.swift` | Constructs synthetic extra-button events. |
| `Source/main.swift` | UI, device lifecycle, reconnection, login and action dispatch. |
| `Tests/main.swift` | Decoder, profile, settings, gesture and event-construction tests. |
| `build_icon.py` | Packages pre-sized PNGs as an ICNS file. |

## Device profile

The supported device has vendor ID **9354**, product ID **33382**, a Bluetooth transport, and the exact 100-byte report descriptor in `SideDecoder.swift`. Exactly one matching device must be present.

`IOHIDDeviceConformsTo(mouse)` can return false before this device is opened, so it is logged for diagnostics rather than used as an additional matching condition.

Metadata discovery does not open the HID manager. Only the selected Lofree is opened, using `kIOHIDOptionsTypeNone`. Callbacks are unscheduled/unregistered and the device is closed before the callback buffer is freed.

## Report decoding

Input report 3 is eight bytes, including its leading `03` report ID. Byte 1 contains the side masks `08` and `10`; motion and wheel bytes are ignored by the decoder.

The descriptor allocates five button bits but declares Button usages 1 through 3. This may explain why side signals are available in raw reports without standard macOS side-button events. It is not a confirmed diagnosis of macOS internals.

The decoder requires a neutral side-button report before accepting a new gesture. It ignores repeated held reports and cancels combined side-button or side-plus-ordinary-button gestures.

## Build and test

```sh
sh build.sh
sh test.sh
```

The build targets arm64/macOS 15.0 and uses AppKit, ApplicationServices, IOKit and ServiceManagement. It creates an ad-hoc signed app ZIP without installing or launching it. Temporary build/test paths are printed and may be deleted afterward.

Tests cover profile matching, report decoding, settings/calibration persistence, gesture timing, cancellation and synthetic bridge event fields. Event-construction tests do not post events. Optional capture replay expects the original development capture's five `08` and eight `10` gestures; that capture is not distributed.

The `--preview` argument opens Settings with input handling, permission requests, login registration and preference writes disabled, for layout checks.

## Validation

Compilation, signature verification and deterministic tests passed on Apple Silicon with macOS Sequoia 15.8.1. Basic navigation, saved learning, double-click/hold actions and Mac Mouse Fix 3.1.0 bridge recognition have also been tested on the physical mouse.

Wider OS/firmware compatibility, all login/wake combinations and complete Mac Mouse Fix gesture support have not been systematically validated.

## Mac Mouse Fix bridge

The bridge emits public Quartz extra-button events. It sets pressure to distinguish down/up, as expected by Mac Mouse Fix's input receiver. It does not spoof a HID sender or create a virtual HID device.

The upstream code inspected during development accepts events without a recognized device when compiled with `NO_FILTER=1`. This is implementation behavior, not an official integration contract:

- [Button input receiver](https://github.com/noah-nuebling/mac-mouse-fix/blob/ec3258d119ef652a98e097eb38d408ac379994e0/Helper/Core/Buttons/ButtonInputReceiver.m)
- [Build configuration](https://github.com/noah-nuebling/mac-mouse-fix/blob/ec3258d119ef652a98e097eb38d408ac379994e0/Mouse%20Fix.xcodeproj/project.pbxproj)

No Mac Mouse Fix source is included in this project.

## Distribution

The current release is ad-hoc signed and not notarized. Developer ID signing and notarization would require the maintainer's Apple developer identity and a separate distribution workflow.
