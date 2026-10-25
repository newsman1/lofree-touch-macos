import Foundation
import CoreGraphics

func packet(_ flags: UInt8) -> [UInt8] { [3, flags, 0, 0, 0, 0, 0, 0] }
func check(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
var decoder = SideDecoder()
check(decoder.consume(reportID: 3, bytes: packet(8)).isEmpty, "Startup-held button must not trigger")
check(decoder.consume(reportID: 3, bytes: packet(0)).isEmpty, "Startup release must only arm")
check(decoder.consume(reportID: 3, bytes: packet(8)) == [.down(8)], "08 down")
check(decoder.consume(reportID: 3, bytes: [3,8,20,0,30,0,0,0]).isEmpty, "Movement while held must not repeat")
check(decoder.consume(reportID: 3, bytes: packet(0)) == [.up(8)], "08 release")
check(decoder.consume(reportID: 3, bytes: packet(0)).isEmpty, "Duplicate release")
check(decoder.consume(reportID: 3, bytes: packet(16)) == [.down(16)], "10 down")
check(decoder.consume(reportID: 3, bytes: packet(0)) == [.up(16)], "10 release")
for flag: UInt8 in [1, 2, 4] {
    check(decoder.consume(reportID: 3, bytes: packet(flag)).isEmpty, "Ordinary button ignored")
    check(decoder.consume(reportID: 3, bytes: packet(0)).isEmpty, "Ordinary release ignored")
}
_ = decoder.consume(reportID: 3, bytes: packet(8))
check(decoder.consume(reportID: 3, bytes: packet(24)) == [.cancel], "Combined side buttons cancel")
check(decoder.consume(reportID: 3, bytes: packet(16)).isEmpty, "Must wait for both released")
check(decoder.consume(reportID: 3, bytes: packet(0)).isEmpty, "Combination release doesn't navigate")
_ = decoder.consume(reportID: 3, bytes: packet(8))
check(decoder.consume(reportID: 3, bytes: packet(9)) == [.cancel], "Side+left cancels")
_ = decoder.consume(reportID: 3, bytes: packet(0))
check(decoder.consume(reportID: 5, bytes: [5,1]).isEmpty, "Unrelated report ignored")
check(decoder.consume(reportID: 3, bytes: [3,8]) == [.cancel], "Short report rejected")
check(decoder.consume(reportID: 3, bytes: packet(0x80)) == [.cancel], "Unknown bits rejected")

if CommandLine.arguments.count > 1 {
    let log = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    let regex = try NSRegularExpression(pattern: #"RAW type=0 id=3 len=8 result=0x00000000 ((?:[0-9A-F]{2} ){7}[0-9A-F]{2})"#)
    let ns = log as NSString
    var replay = SideDecoder(), downs: [UInt8:Int] = [:], ups: [UInt8:Int] = [:]
    var packets = 0
    for match in regex.matches(in: log, range: NSRange(location: 0, length: ns.length)) {
        let data = ns.substring(with: match.range(at: 1)).split(separator: " ").map { UInt8($0, radix: 16)! }
        packets += 1
        for edge in replay.consume(reportID: 3, bytes: data) {
            switch edge {
            case .down(let bit): downs[bit, default: 0] += 1
            case .up(let bit): ups[bit, default: 0] += 1
            case .cancel: fatalError("Unexpected cancellation in real capture")
            }
        }
    }
    check(downs[8] == 5 && ups[8] == 5, "Expected five complete 08 gestures from supplied capture")
    check(downs[16] == 8 && ups[16] == 8, "Expected eight complete 10 gestures from supplied capture")
    print("Replay: \(packets) stored raw packets; 08=\(ups[8]!) complete gestures; 10=\(ups[16]!) complete gestures.")
}
print("Decoder tests passed: held/repeated input, movement, ordinary clicks, simultaneous buttons and malformed/unrelated reports.")

let defaultPreferences = Preferences()
check(defaultPreferences.isBack(8) && !defaultPreferences.isBack(16), "Standard side order")
check(defaultPreferences.enabled && defaultPreferences.mode == .builtIn, "Ready-to-use defaults")
var changed = defaultPreferences
changed.swapped = true
changed.mode = .mouseFix
changed.back.doubleClick = ActionSpec(kind: .shortcut, keyCode: 8, flags: 1048576, label: "⌘C")
let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(changed))
check(restored == changed && restored.isBack(16), "Settings survive serialization including swap, mode and custom shortcut")
var gestures = GestureEngine()
let clickOnly = Bindings(click: ActionSpec(kind: .back))
check(gestures.down(8, pid: 100, at: 0, bindings: clickOnly).isEmpty, "No navigation on down")
let one = gestures.up(8, at: 0.1)
check(one.count == 1 && one[0].gesture == .click && one[0].action.kind == .back, "Default click is immediate")
check(gestures.up(8, at: 0.2).isEmpty, "No orphan release action")
var doubleBindings = clickOnly
doubleBindings.doubleClick = ActionSpec(kind: .copy)
_ = gestures.down(8, pid: 100, at: 1, bindings: doubleBindings)
check(gestures.up(8, at: 1.1).isEmpty, "Single waits when double-click is assigned")
_ = gestures.down(8, pid: 100, at: 1.2, bindings: doubleBindings)
let doubleResult = gestures.up(8, at: 1.3)
check(doubleResult.count == 1 && doubleResult[0].gesture == .doubleClick && doubleResult[0].action.kind == .copy, "Double-click replaces single")
check(gestures.tick(at: 2).isEmpty, "No delayed single after double")
_ = gestures.down(8, pid: 100, at: 3, bindings: doubleBindings)
_ = gestures.up(8, at: 3.1)
check(gestures.tick(at: 3.39).isEmpty, "No premature single")
check(gestures.tick(at: 3.41).count == 1, "Pending single runs after deadline")
var holdBindings = clickOnly
holdBindings.hold = ActionSpec(kind: .missionControl)
_ = gestures.down(8, pid: 100, at: 4, bindings: holdBindings)
check(gestures.tick(at: 4.49).isEmpty, "No premature hold")
let hold = gestures.tick(at: 4.5)
check(hold.count == 1 && hold[0].gesture == .hold, "Hold fires once at threshold")
check(gestures.tick(at: 4.9).isEmpty && gestures.up(8, at: 5).isEmpty, "Hold never also clicks or repeats")
_ = gestures.down(8, pid: 100, at: 6, bindings: holdBindings)
gestures.cancel()
check(gestures.tick(at: 8).isEmpty && gestures.up(8, at: 8).isEmpty, "Pause/focus/disconnect cancellation clears held action")
_ = gestures.down(8, pid: 100, at: 9, bindings: doubleBindings)
_ = gestures.up(8, at: 9.1)
gestures.cancel()
check(gestures.tick(at: 10).isEmpty && gestures.nextDeadline == nil, "Cancellation clears delayed singles")
_ = gestures.down(8, pid: 100, at: 11, bindings: clickOnly)
check(gestures.up(8, at: 14).isEmpty, "Long unassigned hold does not become a click")
print("Gesture and preference tests passed: default actions, serialization, swap, immediate single, double, hold, timers and cancellation.")

let source = CGEventSource(stateID: .privateState)
source?.localEventsSuppressionInterval = 0
for back in [true, false] {
    for down in [true, false] {
        let event = makeBridgeEvent(back: back, down: down, source: source, location: CGPoint(x: 120, y: 140), flags: .maskShift)!
        check(event.type == (down ? .otherMouseDown : .otherMouseUp), "Bridge event type")
        check(event.getIntegerValueField(.mouseEventButtonNumber) == (back ? 3 : 4), "Bridge 4/5 button index")
        check(event.getDoubleValueField(.mouseEventPressure) == (down ? 1 : 0), "MMF reads down/up from pressure")
        check(event.location == CGPoint(x: 120, y: 140) && event.flags == .maskShift, "Bridge retains location and modifier")
    }
}
print("Bridge event construction passed: button indices, down/up pressure, event types, location and modifiers. No events posted.")

var calibrated = Preferences()
check(calibrated.learn(bit: 16, asBack: true) && calibrated.isBack(16), "Learning a reversed Back saves correct order")
check(calibrated.learn(bit: 8, asBack: false) && calibrated.isBack(16), "Learning Forward agrees with learned Back")
let savedCalibration = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(calibrated))
check(savedCalibration.isBack(16) && !savedCalibration.isBack(8), "Learning survives preference serialization")
check(!calibrated.learn(bit: 4, asBack: true) && calibrated.isBack(16), "Wheel button cannot overwrite learning")
check(ActionKind.allCases.contains(.spaceLeft) && ActionKind.allCases.contains(.spaceRight) && ActionKind.allCases.contains(.launchpad), "New actions are available")
print("Persistent calibration tests passed; Spaces/Launchpad presets present.")

check(matchesVerifiedProfile(vendor: 9354, product: 33382, transport: "Bluetooth Low Energy", descriptor: Data(verifiedDescriptor)), "Captured device must match regardless of separate ConformsTo mouseCollection result")
check(!matchesVerifiedProfile(vendor: 9355, product: 33382, transport: "Bluetooth Low Energy", descriptor: Data(verifiedDescriptor)), "Wrong vendor rejected")
check(!matchesVerifiedProfile(vendor: 9354, product: 33383, transport: "Bluetooth Low Energy", descriptor: Data(verifiedDescriptor)), "Wrong product rejected")
check(!matchesVerifiedProfile(vendor: 9354, product: 33382, transport: "USB", descriptor: Data(verifiedDescriptor)), "USB rejected")
check(!matchesVerifiedProfile(vendor: 9354, product: 33382, transport: "Bluetooth", descriptor: nil), "Missing descriptor rejected")
check(!matchesVerifiedProfile(vendor: 9354, product: 33382, transport: "Bluetooth", descriptor: Data([3,8])), "Different descriptor rejected")
print("Device discovery regression tests passed; the exact captured profile is accepted without a mouse-collection gate.")
