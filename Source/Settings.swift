import Foundation

enum OutputMode: String, Codable, CaseIterable { case builtIn, mouseFix }
enum ActionKind: String, Codable, CaseIterable {
    case spaceLeft, spaceRight, launchpad, none, back, forward, missionControl, appWindows, desktop, spotlight, screenshot, copy, paste, undo, redo, previousTab, nextTab, shortcut
    var title: String {
        switch self {
        case .spaceLeft: return "Previous Space"
        case .spaceRight: return "Next Space"
        case .launchpad: return "Launchpad"
        case .none: return "Do nothing"
        case .back: return "Back"
        case .forward: return "Forward"
        case .missionControl: return "Mission Control"
        case .appWindows: return "App windows"
        case .desktop: return "Show Desktop (F11)"
        case .spotlight: return "Spotlight"
        case .screenshot: return "Screenshot selection"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .previousTab: return "Previous tab"
        case .nextTab: return "Next tab"
        case .shortcut: return "Custom keyboard shortcut…"
        }
    }
}
struct ActionSpec: Codable, Equatable {
    var kind: ActionKind
    var keyCode: UInt16? = nil
    var flags: UInt64 = 0
    var label: String = ""
    static let none = ActionSpec(kind: .none)
}
struct Bindings: Codable, Equatable {
    var click: ActionSpec
    var doubleClick: ActionSpec = .none
    var hold: ActionSpec = .none
    func action(_ gesture: Gesture) -> ActionSpec {
        switch gesture { case .click: return click; case .doubleClick: return doubleClick; case .hold: return hold }
    }
    mutating func set(_ gesture: Gesture, _ action: ActionSpec) {
        switch gesture { case .click: click = action; case .doubleClick: doubleClick = action; case .hold: hold = action }
    }
}
enum Gesture: String, Codable, CaseIterable { case click, doubleClick, hold
    var title: String { switch self { case .click: return "Click"; case .doubleClick: return "Double-click"; case .hold: return "Hold (0.5 seconds)" } }
}
struct Preferences: Codable, Equatable {
    var enabled = true
    var mode: OutputMode = .builtIn
    var swapped = false
    var back = Bindings(click: ActionSpec(kind: .back))
    var forward = Bindings(click: ActionSpec(kind: .forward))
    var attemptedLoginRegistration = false
    var hasSeenSettings = false
    mutating func learn(bit: UInt8, asBack: Bool) -> Bool {
        guard bit == 8 || bit == 16 else { return false }
        swapped = asBack ? bit == 16 : bit == 8
        return true
    }
    func isBack(_ bit: UInt8) -> Bool { bit == (swapped ? 0x10 : 0x08) }
    func bindings(_ bit: UInt8) -> Bindings { isBack(bit) ? back : forward }
}
final class PreferenceStore {
    let defaults: UserDefaults
    let key = "lofreePreferencesV1"
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> Preferences {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Preferences.self, from: data) else { return Preferences() }
        return saved
    }
    func save(_ preferences: Preferences) { if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: key) } }
}
