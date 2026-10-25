import Foundation

struct ActionRequest: Equatable {
    let action: ActionSpec
    let pid: Int32
    let bit: UInt8
    let gesture: Gesture
}
struct GestureEngine {
    struct Press { let at: Double; let pid: Int32; let bindings: Bindings; let second: Bool; var held = false }
    struct Waiting { let deadline: Double; let pid: Int32; let bindings: Bindings }
    private var presses: [UInt8: Press] = [:]
    private var waiting: [UInt8: Waiting] = [:]
    static let doubleInterval = 0.30
    static let holdInterval = 0.50
    mutating func cancel() { presses.removeAll(); waiting.removeAll() }
    mutating func down(_ bit: UInt8, pid: Int32, at now: Double, bindings: Bindings) -> [ActionRequest] {
        var result = tick(at: now)
        guard presses[bit] == nil else { return result }
        let previous = waiting.removeValue(forKey: bit)
        let second = previous != nil && previous!.pid == pid && now < previous!.deadline
        if let previous = previous, !second, previous.bindings.click.kind != .none {
            result.append(ActionRequest(action: previous.bindings.click, pid: previous.pid, bit: bit, gesture: .click))
        }
        presses[bit] = Press(at: now, pid: pid, bindings: bindings, second: second)
        return result
    }
    mutating func up(_ bit: UInt8, at now: Double) -> [ActionRequest] {
        var result = tick(at: now)
        guard let press = presses.removeValue(forKey: bit), !press.held, now - press.at < 2 else { return result }
        if press.second {
            if press.bindings.doubleClick.kind != .none { result.append(ActionRequest(action: press.bindings.doubleClick, pid: press.pid, bit: bit, gesture: .doubleClick)) }
        } else if press.bindings.doubleClick.kind != .none {
            waiting[bit] = Waiting(deadline: now + Self.doubleInterval, pid: press.pid, bindings: press.bindings)
        } else if press.bindings.click.kind != .none {
            result.append(ActionRequest(action: press.bindings.click, pid: press.pid, bit: bit, gesture: .click))
        }
        return result
    }
    mutating func tick(at now: Double) -> [ActionRequest] {
        var result: [ActionRequest] = []
        for bit in Array(waiting.keys).sorted() {
            guard let pending = waiting[bit], now >= pending.deadline else { continue }
            waiting.removeValue(forKey: bit)
            if pending.bindings.click.kind != .none { result.append(ActionRequest(action: pending.bindings.click, pid: pending.pid, bit: bit, gesture: .click)) }
        }
        for bit in Array(presses.keys).sorted() {
            guard var press = presses[bit], !press.held, press.bindings.hold.kind != .none, now >= press.at + Self.holdInterval else { continue }
            press.held = true; presses[bit] = press
            result.append(ActionRequest(action: press.bindings.hold, pid: press.pid, bit: bit, gesture: .hold))
        }
        return result
    }
    var nextDeadline: Double? {
        let holds = presses.values.filter { !$0.held && $0.bindings.hold.kind != .none }.map { $0.at + Self.holdInterval }
        return (waiting.values.map { $0.deadline } + holds).min()
    }
}
