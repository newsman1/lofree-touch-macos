import CoreGraphics

// Public Quartz events only. Extra button numbers are set explicitly because
// CGMouseButton's named cases cover only left/right/center.
func makeBridgeEvent(back: Bool, down: Bool, source: CGEventSource?, location: CGPoint, flags: CGEventFlags) -> CGEvent? {
    guard let event = CGEvent(mouseEventSource: source, mouseType: down ? .otherMouseDown : .otherMouseUp, mouseCursorPosition: location, mouseButton: .center) else { return nil }
    event.setIntegerValueField(.mouseEventButtonNumber, value: back ? 3 : 4)
    event.setDoubleValueField(.mouseEventPressure, value: down ? 1 : 0)
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.setIntegerValueField(.eventSourceUserData, value: 0x4C4F46524545)
    event.flags = flags
    return event
}
