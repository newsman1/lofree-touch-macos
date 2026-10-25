import AppKit
import ApplicationServices
import IOKit.hid
import ServiceManagement

final class FlippedDocument: NSView { override var isFlipped: Bool { true } }

final class SettingsWindow: NSWindow {
    var record: ((NSEvent) -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, let record = record { self.record = nil; record(event); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let record = record { self.record = nil; record(event); return }
        super.sendEvent(event)
    }
}

final class Controller: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let store = PreferenceStore()
    var preferences: Preferences
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var device: IOHIDDevice?
    var buffer: UnsafeMutablePointer<UInt8>?
    var decoder = SideDecoder()
    var engine = GestureEngine()
    var syntheticDown: Set<UInt8> = []
    var bridgeTimers: [UInt8: Timer] = [:]
    var retryTimer: Timer?
    var gestureTimer: Timer?
    var suspended = false
    var observers: [NSObjectProtocol] = []
    var window: SettingsWindow!
    var statusItem: NSStatusItem!
    var menuState: NSMenuItem!
    var pauseItem: NSMenuItem!
    let statusLabel = NSTextField(wrappingLabelWithString: "Starting…")
    let loginLabel = NSTextField(labelWithString: "")
    let loginToggle = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    let pauseToggle = NSButton(checkboxWithTitle: "Enable side buttons", target: nil, action: nil)
    let swapToggle = NSButton(checkboxWithTitle: "Swap the two physical side buttons", target: nil, action: nil)
    let modePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    let log = NSTextView(frame: NSRect(x: 0, y: 0, width: 780, height: 130))
    var actionPickers: [NSPopUpButton] = []
    var recordButtons: [NSButton] = []
    var stateText = "Starting…"
    var lastError = ""
    var lastInventory = ""
    var learning: Bool?
    var learningCandidate: UInt8?
    var reportCount = 0
    var edgeCount = 0
    var actionCount = 0
    let deliveryLabel = NSTextField(labelWithString: "Input: waiting")
    var isTerminating = false
    let previewOnly = CommandLine.arguments.contains("--preview")
    let supported: Set<String> = ["com.apple.Safari", "com.apple.finder", "com.google.Chrome", "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox"]
    let eventSource: CGEventSource? = {
        let source = CGEventSource(stateID: .privateState)
        source?.localEventsSuppressionInterval = 0
        return source
    }()
    override init() { preferences = CommandLine.arguments.contains("--preview") ? Preferences() : store.load(); super.init() }
    var now: Double { ProcessInfo.processInfo.systemUptime }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avoid two installed copies mapping the same physical input twice.
        if !previewOnly, let id = Bundle.main.bundleIdentifier,
           let other = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate(options: []); NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        setupMenu(); setupWindow()
        if previewOnly { setState("Preview — mouse and login registration disabled"); refreshControls(); showSettings(); return }
        // Use the same metadata discovery path as the successful HID Probe.
        // Input access is still restricted to the exact selected Lofree.
        IOHIDManagerSetDeviceMatching(manager, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.cancelGestures() })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.suspended = true; self?.closeDevice() })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.suspended = false; self?.reconcile() })
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.reconcile() }
        RunLoop.main.add(retryTimer!, forMode: .common)
        append("Lofree Bluetooth Mapper 0.4.2. Saved defaults: 08=Back, 10=Forward; no calibration required.")
        let firstRun = !preferences.hasSeenSettings
        if firstRun { preferences.hasSeenSettings = true; persist(); showSettings() }
        // User requested automatic startup. Register once from a stable installation;
        // do not override later revocation in System Settings on every launch.
        if !preferences.attemptedLoginRegistration && Bundle.main.bundlePath.hasPrefix("/Applications/") {
            registerLogin()
        }
        reconcile(); refreshControls()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true; retryTimer?.invalidate(); closeDevice()
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    func persist() { if !previewOnly { store.save(preferences) } }
    func button(_ title: String, _ selector: Selector) -> NSButton { NSButton(title: title, target: self, action: selector) }
    func row(_ views: [NSView]) -> NSStackView { let row = NSStackView(views: views); row.spacing = 10; return row }
    func append(_ line: String) {
        log.string += line + "\n"
        if log.string.count > 18000 { log.string = String(log.string.suffix(14000)) }
        log.scrollToEndOfDocument(nil)
    }
    func setState(_ text: String) {
        stateText = text; statusLabel.stringValue = text; menuState?.title = text
        statusItem?.button?.toolTip = "Lofree Bluetooth Mapper — " + text
        statusItem?.button?.appearsDisabled = !preferences.enabled
    }
    func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: 26)
        statusItem.button?.image = mouseOutline()
        statusItem.button?.imagePosition = .imageOnly
        let menu = NSMenu(); menu.delegate = self
        menuState = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: ""); menuState.isEnabled = false; menu.addItem(menuState)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        pauseItem = NSMenuItem(title: "Pause buttons", action: #selector(togglePaused), keyEquivalent: ""); pauseItem.target = self; menu.addItem(pauseItem)
        menu.addItem(withTitle: "Grant permissions / retry", action: #selector(requestPermissions), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        let mainMenu = NSMenu(), appRoot = NSMenuItem(), appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Lofree Bluetooth Mapper", action: #selector(quit), keyEquivalent: "q").target = self
        appRoot.submenu = appMenu; mainMenu.addItem(appRoot); NSApp.mainMenu = mainMenu
    }
    func menuWillOpen(_ menu: NSMenu) { refreshControls() }
    func mouseOutline() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            // Compact top-down mouse shell, left thumb wing and two button caps.
            let shell = NSBezierPath()
            shell.move(to: NSPoint(x: 6, y: 16.5)); shell.line(to: NSPoint(x: 14, y: 16.5))
            shell.curve(to: NSPoint(x: 15.5, y: 15), controlPoint1: NSPoint(x: 15, y: 16.5), controlPoint2: NSPoint(x: 15.5, y: 16))
            shell.line(to: NSPoint(x: 15.5, y: 6))
            shell.curve(to: NSPoint(x: 10, y: 1.5), controlPoint1: NSPoint(x: 15.5, y: 3), controlPoint2: NSPoint(x: 13, y: 1.5))
            shell.curve(to: NSPoint(x: 4.5, y: 6), controlPoint1: NSPoint(x: 7, y: 1.5), controlPoint2: NSPoint(x: 4.5, y: 3))
            shell.line(to: NSPoint(x: 4.5, y: 15)); shell.curve(to: NSPoint(x: 6, y: 16.5), controlPoint1: NSPoint(x: 4.5, y: 16), controlPoint2: NSPoint(x: 5, y: 16.5))
            shell.lineWidth = 1.15; shell.stroke()
            let wing = NSBezierPath(); wing.move(to: NSPoint(x: 4.5, y: 12)); wing.line(to: NSPoint(x: 2, y: 10)); wing.curve(to: NSPoint(x: 4.5, y: 5), controlPoint1: NSPoint(x: 1, y: 7), controlPoint2: NSPoint(x: 2.5, y: 6)); wing.lineWidth = 1; wing.stroke()
            let caps = NSBezierPath(); caps.move(to: NSPoint(x: 6, y: 9)); caps.line(to: NSPoint(x: 14, y: 9)); caps.move(to: NSPoint(x: 10, y: 10)); caps.line(to: NSPoint(x: 10, y: 15)); caps.lineWidth = 1; caps.stroke()
            NSBezierPath(roundedRect: NSRect(x: 9.2, y: 11, width: 1.6, height: 3), xRadius: 0.7, yRadius: 0.7).fill()
            return true
        }
        image.isTemplate = true; return image
    }
    func setupWindow() {
        window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 770), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Lofree Bluetooth Mapper"; window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = NSSize(width: 800, height: 710)
        let scroller = NSScrollView(frame: window.contentView!.bounds)
        scroller.autoresizingMask = [.width, .height]; scroller.hasVerticalScroller = true; scroller.drawsBackground = false
        window.contentView!.addSubview(scroller)
        let document = FlippedDocument(); document.translatesAutoresizingMaskIntoConstraints = false
        scroller.documentView = document
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo: scroller.contentView.widthAnchor), stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 22), stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -22), stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20), stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -20)])
        let title = NSTextField(labelWithString: "Your Lofree, ready when you are."); title.font = .systemFont(ofSize: 22, weight: .semibold); stack.addArrangedSubview(title)
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString: "Settings save automatically. The mouse reconnects after sleep or Bluetooth disconnection. Close this window to keep it running in the menu bar."))
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(deliveryLabel)
        stack.addArrangedSubview(row([button("Learn Back", #selector(learnBack)), button("Learn Forward", #selector(learnForward)), button("Test Back shortcut", #selector(testBack))]))
        pauseToggle.target = self; pauseToggle.action = #selector(enabledChanged)
        loginToggle.target = self; loginToggle.action = #selector(loginChanged)
        stack.addArrangedSubview(row([pauseToggle, loginToggle])); stack.addArrangedSubview(loginLabel)
        modePicker.addItems(withTitles: ["Built-in actions", "Mac Mouse Fix bridge (experimental)"])
        modePicker.target = self; modePicker.action = #selector(modeChanged)
        stack.addArrangedSubview(row([NSTextField(labelWithString: "Button handling:"), modePicker]))
        let bridgeNote = NSTextField(wrappingLabelWithString: "Bridge mode emits mouse buttons 4/5 for Mac Mouse Fix to configure. Built-in actions are then off. Compatibility and hold/drag gestures vary by Mac Mouse Fix version; return to built-in actions if it does not recognize them.")
        bridgeNote.textColor = .secondaryLabelColor; stack.addArrangedSubview(bridgeNote)
        swapToggle.target = self; swapToggle.action = #selector(swapChanged); stack.addArrangedSubview(swapToggle)
        for side in 0..<2 {
            let heading = NSTextField(labelWithString: side == 0 ? "Back side button" : "Forward side button"); heading.font = .systemFont(ofSize: 13, weight: .semibold); stack.addArrangedSubview(heading)
            for (gestureIndex, gesture) in Gesture.allCases.enumerated() {
                let label = NSTextField(labelWithString: gesture.title); label.widthAnchor.constraint(equalToConstant: 150).isActive = true
                let picker = NSPopUpButton(frame: .zero, pullsDown: false); picker.addItems(withTitles: ActionKind.allCases.map { $0.title }); picker.tag = side * 3 + gestureIndex; picker.target = self; picker.action = #selector(actionChanged(_:)); picker.widthAnchor.constraint(equalToConstant: 245).isActive = true
                let record = button("Record shortcut…", #selector(recordShortcut(_:))); record.tag = picker.tag; record.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
                actionPickers.append(picker); recordButtons.append(record)
                stack.addArrangedSubview(row([label, picker, record]))
            }
        }
        let note = NSTextField(wrappingLabelWithString: "Double-click/hold are optional. Assigning double-click adds a 0.3-second wait to single clicks. Back/Forward target supported browsers and Finder. Custom shortcuts run in the focused app; navigation presets assume a US-compatible layout. The default physical order can be reversed with Swap.")
        note.textColor = .secondaryLabelColor; stack.addArrangedSubview(note)
        stack.addArrangedSubview(row([button("Grant permissions / retry", #selector(requestPermissions)), button("Restore defaults", #selector(restoreDefaults)), button("Copy diagnostics", #selector(copyDiagnostics)), button("Quit", #selector(quit))]))
        log.font = .monospacedSystemFont(ofSize: 10, weight: .regular); log.isEditable = false; log.isSelectable = true; log.isVerticallyResizable = true; log.isHorizontallyResizable = false; log.autoresizingMask = [.width]
        log.minSize = NSSize(width: 0, height: 70); log.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        log.textContainer?.containerSize = NSSize(width: 780, height: CGFloat.greatestFiniteMagnitude); log.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView(); scroll.documentView = log; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder; stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true; scroll.heightAnchor.constraint(equalToConstant: 110).isActive = true
        for field in stack.arrangedSubviews.compactMap({ $0 as? NSTextField }) { field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        window.center()
    }
    func windowWillClose(_ notification: Notification) { window.record = nil; refreshControls() }
    func windowDidResignKey(_ notification: Notification) { window.record = nil; refreshControls() }
    @objc func showSettings() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); refreshControls() }
    func refreshControls() {
        guard window != nil else { return }
        pauseToggle.state = preferences.enabled ? .on : .off
        pauseItem.title = preferences.enabled ? "Pause buttons" : "Resume buttons"
        swapToggle.state = preferences.swapped ? .on : .off
        modePicker.selectItem(at: preferences.mode == .builtIn ? 0 : 1)
        let service = SMAppService.mainApp
        loginToggle.state = service.status == .enabled || service.status == .requiresApproval ? .on : .off
        switch service.status {
        case .enabled: loginLabel.stringValue = "Launch at login is enabled."
        case .requiresApproval: loginLabel.stringValue = "Allow this app in System Settings → General → Login Items."
        default: loginLabel.stringValue = "Launch at login is off. Install in Applications before enabling it."
        }
        for i in actionPickers.indices {
            let bindings = i < 3 ? preferences.back : preferences.forward
            let action = bindings.action(Gesture.allCases[i % 3])
            actionPickers[i].selectItem(at: ActionKind.allCases.firstIndex(of: action.kind) ?? 0)
            actionPickers[i].isEnabled = preferences.mode == .builtIn
            recordButtons[i].isEnabled = preferences.mode == .builtIn && action.kind == .shortcut
            recordButtons[i].title = action.label.isEmpty ? "Record shortcut…" : action.label
        }
    }
    @objc func learnBack() { beginLearning(back: true) }
    @objc func learnForward() { beginLearning(back: false) }
    func beginLearning(back: Bool) {
        guard device != nil else { append("Cannot learn: mouse is not open. See status and Grant permissions / retry."); return }
        cancelGestures(); learning = back; learningCandidate = nil
        setState("Learning \(back ? "Back" : "Forward") — press and release its button")
        append("LEARN: release both side buttons, click normally with the Lofree, then press/release the \(back ? "Back" : "Forward") button. Input learning does not need Accessibility.")
    }
    @objc func testBack() {
        guard learning == nil else { append("Finish learning first."); return }
        guard preferences.enabled && preferences.mode == .builtIn else { append("Enable side buttons and choose Built-in actions before testing navigation."); return }
        guard AXIsProcessTrusted() else { append("TEST BLOCKED: Accessibility permission is missing for this build."); return }
        append("TEST: switch to Safari or Finder within 3 seconds; one Back shortcut will be attempted.")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
            self.perform([ActionRequest(action: ActionSpec(kind: .back), pid: pid, bit: self.preferences.swapped ? 16 : 8, gesture: .click)])
        }
    }
    @objc func togglePaused() { preferences.enabled.toggle(); persist(); reconcile(); refreshControls() }
    @objc func enabledChanged() { preferences.enabled = pauseToggle.state == .on; persist(); reconcile(); refreshControls() }
    @objc func modeChanged() { cancelGestures(); preferences.mode = modePicker.indexOfSelectedItem == 0 ? .builtIn : .mouseFix; persist(); decoder.reset(); refreshControls(); reconcile() }
    @objc func swapChanged() { cancelGestures(); preferences.swapped = swapToggle.state == .on; persist(); decoder.reset(); refreshControls() }
    @objc func actionChanged(_ sender: NSPopUpButton) {
        cancelGestures()
        let action = ActionSpec(kind: ActionKind.allCases[sender.indexOfSelectedItem])
        setAction(sender.tag, action); refreshControls()
    }
    func setAction(_ index: Int, _ action: ActionSpec) {
        if index < 3 { preferences.back.set(Gesture.allCases[index % 3], action) }
        else { preferences.forward.set(Gesture.allCases[index % 3], action) }
        persist()
    }
    @objc func recordShortcut(_ sender: NSButton) {
        cancelGestures(); sender.title = "Press shortcut (Esc cancels)…"
        let index = sender.tag
        window.record = { [weak self] event in
            guard let self = self else { return }
            if event.keyCode != 53 {
                let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
                let symbols = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
                let specials: [UInt16:String] = [123:"←",124:"→",125:"↓",126:"↑",36:"Return",48:"Tab",49:"Space",51:"Delete"]
                let key = specials[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
                self.setAction(index, ActionSpec(kind: .shortcut, keyCode: event.keyCode, flags: UInt64(flags.rawValue), label: symbols + key))
            }
            self.refreshControls()
        }
        window.makeKey()
    }
    @objc func restoreDefaults() {
        cancelGestures(); preferences.swapped = false; preferences.mode = .builtIn
        preferences.back = Bindings(click: ActionSpec(kind: .back)); preferences.forward = Bindings(click: ActionSpec(kind: .forward))
        persist(); decoder.reset(); refreshControls(); reconcile()
    }
    func registerLogin() {
        guard !previewOnly else { return }
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { append("Move this app to Applications before enabling Launch at login."); refreshControls(); return }
        do {
            if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval { try SMAppService.mainApp.register() }
            preferences.attemptedLoginRegistration = true; persist()
        } catch { append("Login registration failed: \(error.localizedDescription). Use Launch at login to retry.") }
        refreshControls()
    }
    @objc func loginChanged() {
        guard !previewOnly else { return }
        if loginToggle.state == .on { registerLogin() }
        else {
            do { try SMAppService.mainApp.unregister(); preferences.attemptedLoginRegistration = true; persist() }
            catch { append("Could not disable login item: \(error.localizedDescription)") }
            refreshControls()
        }
    }
    @objc func requestPermissions() {
        guard !previewOnly else { return }
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        if !AXIsProcessTrusted() { _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary) }
        lastError = ""; lastInventory = ""
        if device == nil { IOHIDManagerSetDeviceMatching(manager, nil) }
        reconcile()
        append("Approve Lofree Bluetooth Mapper in Input Monitoring and Accessibility if requested. If necessary quit/reopen the app; settings remain saved.")
    }
    @objc func copyDiagnostics() {
        let data = "Lofree Bluetooth Mapper 0.4.2\nApp: \(Bundle.main.bundlePath)\nReport count: \(reportCount); side edges: \(edgeCount); posted actions: \(actionCount)\nState: \(stateText)\nMode: \(preferences.mode.rawValue); swapped: \(preferences.swapped)\nInput preflight: \(CGPreflightListenEventAccess()); Accessibility: \(AXIsProcessTrusted())\nLogin status: \(SMAppService.mainApp.status.rawValue)\n" + log.string
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(data, forType: .string)
    }
    @objc func quit() { NSApp.terminate(nil) }

    func reconcile() {
        deliveryLabel.stringValue = "Input: \(reportCount) reports · \(edgeCount) side edges · \(actionCount) actions posted"
        guard !isTerminating && !previewOnly else { return }
        if !preferences.enabled { closeDevice(); setState("Paused — settings remembered"); return }
        if suspended { setState("Sleeping — reconnects on wake"); return }
        if device == nil { openDevice() }
        guard device != nil else { return }
        if let back = learning { setState("Learning \(back ? "Back" : "Forward") — press and release its button"); return }
        if !AXIsProcessTrusted() { cancelGestures(); setState("Mouse connected — Accessibility permission needed"); return }
        setState(reportCount == 0 ? "Mouse open — awaiting input delivery" : (preferences.mode == .builtIn ? "Receiving input — built-in actions" : "Receiving input — Mac Mouse Fix bridge (experimental)"))
    }
    func openDevice() {
        let all = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let candidates = all.filter { d in
            let vid = (IOHIDDeviceGetProperty(d, "VendorID" as CFString) as? NSNumber)?.intValue
            let pid = (IOHIDDeviceGetProperty(d, "ProductID" as CFString) as? NSNumber)?.intValue
            let name = (IOHIDDeviceGetProperty(d, "Product" as CFString) as? String ?? "").lowercased()
            return (vid == 9354 && pid == 33382) || name.contains("lofree")
        }
        let inventory = "Discovery: \(all.count) HID metadata entries, \(candidates.count) Lofree candidates. " + candidates.map { d in
            let name = IOHIDDeviceGetProperty(d, "Product" as CFString) as? String ?? "unknown"
            let transport = IOHIDDeviceGetProperty(d, "Transport" as CFString) as? String ?? "unknown"
            let descriptor = IOHIDDeviceGetProperty(d, "ReportDescriptor" as CFString) as? Data
            let exact = descriptor == Data(verifiedDescriptor)
            return "\(name), transport=\(transport), descriptorBytes=\(descriptor?.count ?? 0), verifiedProfile=\(exact), mouseCollection=\(IOHIDDeviceConformsTo(d, 1, 2))"
        }.joined(separator: "; ")
        if inventory != lastInventory { append(inventory); lastInventory = inventory }
        let matches = all.filter { d in
            let transport = IOHIDDeviceGetProperty(d, "Transport" as CFString) as? String ?? ""
            let vid = (IOHIDDeviceGetProperty(d, "VendorID" as CFString) as? NSNumber)?.intValue
            let pid = (IOHIDDeviceGetProperty(d, "ProductID" as CFString) as? NSNumber)?.intValue
            let descriptor = IOHIDDeviceGetProperty(d, "ReportDescriptor" as CFString) as? Data
            return matchesVerifiedProfile(vendor: vid, product: pid, transport: transport, descriptor: descriptor)
        }
        guard matches.count == 1, let selected = matches.first else {
            setState(matches.count > 1 ? "Multiple matching mice — connect one" : "Waiting for compatible Lofree Bluetooth mouse")
            return
        }
        let result = IOHIDDeviceOpen(selected, IOOptionBits(kIOHIDOptionsTypeNone))
        if result == kIOReturnSuccess { append("Verified profile matched. Non-exclusive IOHIDDeviceOpen succeeded.") }
        guard result == kIOReturnSuccess else {
            let error = String(format:"Mouse open failed: 0x%08X. Check Input Monitoring permission.", UInt32(bitPattern: result))
            if error != lastError { append(error); lastError = error }
            setState("Mouse access blocked — grant permissions / retry"); return
        }
        lastError = ""; device = selected; decoder.reset(); engine.cancel()
        buffer = .allocate(capacity: 8); buffer!.initialize(repeating: 0, count: 8)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(selected, buffer!, 8, { context, result, _, _, id, report, length in
            guard let context = context else { return }
            let owner = Unmanaged<Controller>.fromOpaque(context).takeUnretainedValue()
            guard owner.device != nil else { return }
            guard result == kIOReturnSuccess, length == 8 else { owner.cancelGestures(); owner.decoder.reset(); return }
            owner.reportCount += 1
            if owner.reportCount == 1 { owner.append("HID input delivery confirmed.") }
            owner.receive(id, Array(UnsafeBufferPointer(start: report, count: 8)))
        }, context)
        IOHIDDeviceRegisterRemovalCallback(selected, { context, _, _ in
            guard let context = context else { return }
            let owner = Unmanaged<Controller>.fromOpaque(context).takeUnretainedValue()
            owner.closeDevice(); owner.setState("Mouse disconnected — reconnecting automatically")
        }, context)
        IOHIDDeviceScheduleWithRunLoop(selected, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        append("Connected to verified Lofree Bluetooth interface. Saved button actions loaded.")
    }
    func closeDevice() {
        cancelGestures()
        if let device = device {
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceRegisterRemovalCallback(device, nil, nil)
            if let buffer = buffer { IOHIDDeviceRegisterInputReportCallback(device, buffer, 8, nil, nil) }
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        device = nil; buffer?.deallocate(); buffer = nil; decoder.reset(); learning = nil; learningCandidate = nil
    }
    func cancelGestures() {
        gestureTimer?.invalidate(); gestureTimer = nil; engine.cancel()
        for bit in Array(syntheticDown) { postBridge(bit, down: false) }
        syntheticDown.removeAll()
        for timer in bridgeTimers.values { timer.invalidate() }; bridgeTimers.removeAll()
    }
    func receive(_ id: UInt32, _ bytes: [UInt8]) {
        guard preferences.enabled && !suspended else { return }
        for edge in decoder.consume(reportID: id, bytes: bytes) {
            switch edge {
            case .cancel: cancelGestures(); learningCandidate = nil
            case .down(let bit):
                edgeCount += 1; append(String(format: "Detected side %02X down", bit))
                if learning != nil { learningCandidate = bit; continue }
                guard AXIsProcessTrusted() else { append("SKIPPED: Accessibility is not approved for this running build. Input is working; approve Accessibility and retry."); continue }
                guard window?.record == nil else { append("SKIPPED: shortcut recorder is active."); continue }
                if preferences.mode == .mouseFix {
                    guard !syntheticDown.contains(bit) else { continue }
                    guard postBridge(bit, down: true) else { continue }; syntheticDown.insert(bit)
                    let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                        guard let self = self else { return }; self.cancelGestures(); self.decoder.reset()
                    }
                    bridgeTimers[bit] = timer; RunLoop.main.add(timer, forMode: .common)
                } else {
                    guard NSEvent.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty else { continue }
                    let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
                    perform(engine.down(bit, pid: pid, at: now, bindings: preferences.bindings(bit))); scheduleGestureTimer()
                }
            case .up(let bit):
                edgeCount += 1; append(String(format: "Detected side %02X up", bit))
                if let back = learning {
                    if learningCandidate == bit {
                        _ = preferences.learn(bit: bit, asBack: back)
                        learning = nil; learningCandidate = nil; persist(); refreshControls()
                        append("LEARNED: physical order saved. Back=\(preferences.swapped ? "10" : "08"), Forward=\(preferences.swapped ? "08" : "10"). This survives relaunch.")
                    }
                    continue
                }
                if preferences.mode == .mouseFix {
                    if syntheticDown.remove(bit) != nil { postBridge(bit, down: false) }
                    bridgeTimers.removeValue(forKey: bit)?.invalidate()
                } else {
                    guard NSEvent.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty else { cancelGestures(); continue }
                    perform(engine.up(bit, at: now)); scheduleGestureTimer()
                }
            }
        }
    }
    func scheduleGestureTimer() {
        gestureTimer?.invalidate(); gestureTimer = nil
        guard let deadline = engine.nextDeadline else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: max(0.001, deadline - now), repeats: false) { [weak self] _ in
            guard let self = self else { return }; self.perform(self.engine.tick(at: self.now)); self.scheduleGestureTimer()
        }
        gestureTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func perform(_ requests: [ActionRequest]) {
        for request in requests {
            guard AXIsProcessTrusted() else { append("SKIPPED action: Accessibility permission missing."); continue }
            guard preferences.enabled, preferences.mode == .builtIn, AXIsProcessTrusted(), window?.record == nil,
                  NSEvent.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty,
                  let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier == request.pid else { continue }
            let action = request.action
            if action.kind == .back || action.kind == .forward { guard let id = app.bundleIdentifier, supported.contains(id) else { append("SKIPPED: Back/Forward requires a supported browser or Finder, not the Settings window."); continue } }
            let command = CGEventFlags.maskCommand, shift = CGEventFlags.maskShift, control = CGEventFlags.maskControl
            let code: CGKeyCode; let flags: CGEventFlags; let global: Bool
            switch action.kind {
            case .spaceLeft: code = 123; flags = control; global = true
            case .spaceRight: code = 124; flags = control; global = true
            case .launchpad:
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Launchpad.app"), configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    DispatchQueue.main.async { [weak self] in self?.append(error.map { "Launchpad failed: \($0.localizedDescription)" } ?? "Opened Launchpad") }
                }
                actionCount += 1; continue
            case .none: continue
            case .back: code = 33; flags = command; global = false
            case .forward: code = 30; flags = command; global = false
            case .missionControl: code = 126; flags = control; global = true
            case .appWindows: code = 125; flags = control; global = true
            case .desktop: code = 103; flags = []; global = true
            case .spotlight: code = 49; flags = command; global = true
            case .screenshot: code = 21; flags = [command, shift]; global = true
            case .copy: code = 8; flags = command; global = false
            case .paste: code = 9; flags = command; global = false
            case .undo: code = 6; flags = command; global = false
            case .redo: code = 6; flags = [command, shift]; global = false
            case .previousTab: code = 48; flags = [control, shift]; global = false
            case .nextTab: code = 48; flags = control; global = false
            case .shortcut:
                guard let key = action.keyCode else { continue }
                code = key; flags = CGEventFlags(rawValue: action.flags); global = true
            }
            guard let down = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: true), let up = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: false) else { continue }
            down.flags = flags; up.flags = flags
            if global { down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap) }
            else { down.postToPid(request.pid); up.postToPid(request.pid) }
            actionCount += 1
            append("\(preferences.isBack(request.bit) ? "Back" : "Forward") \(request.gesture.title): posted \(action.kind == .shortcut ? action.label : action.kind.title)")
        }
    }
    @discardableResult func postBridge(_ bit: UInt8, down: Bool) -> Bool {
        guard AXIsProcessTrusted(), let location = CGEvent(source: nil)?.location else { return false }
        let number: UInt32 = preferences.isBack(bit) ? 3 : 4
        let flags = CGEventFlags(rawValue: UInt64(NSEvent.modifierFlags.intersection([.command, .shift, .control, .option]).rawValue))
        guard let event = makeBridgeEvent(back: preferences.isBack(bit), down: down, source: eventSource, location: location, flags: flags) else { return false }
        event.post(tap: .cghidEventTap)
        actionCount += 1
        append("Bridge button \(number + 1) \(down ? "down" : "up") posted")
        return true
    }
}
let delegate = Controller()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
