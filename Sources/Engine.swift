import AppKit
import ApplicationServices

enum NavigationMode: String { case idle, clicking, scrolling, loading }

final class Engine: ObservableObject {
    @Published var trusted = AXIsProcessTrusted()
    @Published var listening = false
    @Published var paused = false { didSet { if paused { dismiss() } } }
    @Published var hyperError = ""
    private let hyper = HyperController()
    private var hyperHeld = false
    var recording = false
    private(set) var mode: NavigationMode = .idle
    private var intended: NavigationMode = .idle
    private var targets: [Target] = []
    private var areas: [Target] = []
    private var prefix = ""
    private var selected = 0
    private var tutor = false
    private var generation = 0
    private var pid: pid_t = 0
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private let overlay = Overlay()
    private let scanQueue = DispatchQueue(label: "keyrow.accessibility", qos: .userInitiated)
    private var held: [UInt16: (Double, Double)] = [:]
    private var scrollTimer: Timer?
    private var permissionTimer: Timer?
    private var missionTimer: Timer?
    private var missionWasOpen = false
    private var lastClick: (Target, Date, pid_t)?
    private var lastG: Date?
    private var scrollPoint: CGPoint?
    private var swallowed = Set<UInt16>()
    private var modifierLatch = false
    var diagnosticsURL: URL?
    private let eventMarker: Int64 = 0x4b4559524f57
    init() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if self.mode != .idle && app.processIdentifier != self.pid { self.dismiss() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.dismiss() }
    }
    func start() {
        refreshPermission()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshPermission() }
        missionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.trusted, !self.paused, !self.recording, Preferences.shared.missionControl else { return }
            self.scanQueue.async {
                let open = missionControlRoot() != nil
                DispatchQueue.main.async {
                    if open && !self.missionWasOpen && self.mode == .idle { self.activate(.clicking) }
                    if !open && self.missionWasOpen && self.mode != .idle { self.dismiss() }
                    self.missionWasOpen = open
                }
            }
        }
    }
    func refreshPermission() {
        let allowed = AXIsProcessTrusted()
        if trusted != allowed { trusted = allowed }
        if allowed && tap == nil { installTap() }
        if !allowed && tap != nil { stopTap(); dismiss() }
        if allowed && Preferences.shared.hyper != hyper.enabled {
            do { try hyper.update(Preferences.shared.hyper); hyperError = "" }
            catch { hyperError = error.localizedDescription; Preferences.shared.hyper = false }
        }
        if mode == .idle { writeDiagnostics() }
    }
    private func installTap() {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<Engine>.fromOpaque(context).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = engine.tap { CGEvent.tapEnable(tap: tap, enable: true) }; engine.dismiss()
                return Unmanaged.passUnretained(event)
            }
            return engine.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { listening = false; return }
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true); listening = true
    }
    private func stopTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil; tapSource = nil; listening = false
    }
    func activate(_ requested: NavigationMode) {
        if mode == requested || intended == requested && mode == .loading { dismiss(); return }
        guard !paused, trusted, let app = NSWorkspace.shared.frontmostApplication else { return }
        let ignored = Preferences.shared.ignored.split(whereSeparator: { $0 == "\n" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !ignored.contains(app.bundleIdentifier ?? ""), !ignored.contains(app.localizedName ?? "") else { return }
        generation += 1; let current = generation
        pid = app.processIdentifier; let appPID = pid
        mode = .loading; intended = requested; prefix = ""; selected = 0; tutor = false
        let screens = overlay.screenRects; let exhaustive = Preferences.shared.exhaustive
        overlay.show(targets: [], prefix: "", selected: 0, scrolling: false, message: "Reading controls…   ·   Esc exit")
        scanQueue.async { [weak self] in
            let result = AccessibilityScanner().scan(pid: appPID, screens: screens, exhaustive: exhaustive)
            DispatchQueue.main.async {
                guard let self, self.generation == current, self.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
                self.targets = result.targets; self.areas = result.areas
                let labels = Labels.generate(self.targets.count, alphabet: Preferences.shared.alphabet)
                for index in self.targets.indices { self.targets[index].label = labels[index] }
                for index in self.areas.indices { self.areas[index].label = String(index) }
                self.mode = requested
                let empty = requested == .clicking ? self.targets.isEmpty : self.areas.isEmpty
                self.render(message: empty ? "No accessible \(requested == .clicking ? "controls" : "scroll areas")   ·   Esc exit" : result.truncated ? "\(self.targets.count) targets   ·   Scan limit reached   ·   Esc exit" : "")
                self.writeDiagnostics(result: result)
                if let url = self.diagnosticsURL { self.overlay.savePreview(to: url.deletingLastPathComponent().appendingPathComponent("overlay-preview.png")) }
            }
        }
    }
    func dismiss() {
        generation += 1; mode = .idle; intended = .idle; prefix = ""; held.removeAll()
        scrollTimer?.invalidate(); scrollTimer = nil; overlay.hide(); writeDiagnostics()
        scrollPoint = nil
    }
    private func render(message: String = "") {
        overlay.show(targets: mode == .scrolling ? areas : targets, prefix: prefix, selected: selected, scrolling: mode == .scrolling, message: message, tutor: tutor)
        writeDiagnostics()
    }
    private func unicode(_ event: CGEvent) -> String {
        var chars = [UniChar](repeating: 0, count: 8); var length = 0
        event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: min(length, 8)).uppercased()
    }
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if event.getIntegerValueField(.eventSourceUserData) == eventMarker { return false }
        let key = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if hyper.enabled && key == HyperController.trigger && (type == .keyDown || type == .keyUp) {
            if type == .keyDown && !hyperHeld {
                hyperHeld = true; postHyperFlags(HyperController.flags)
                if !recording && !paused {
                    let click = Preferences.shared.clickShortcut; let scroll = Preferences.shared.scrollShortcut
                    if click.keyCode == UInt16.max && click.modifiers == HyperController.flags.rawValue { modifierLatch = true; DispatchQueue.main.async { self.activate(.clicking) } }
                    else if scroll.keyCode == UInt16.max && scroll.modifiers == HyperController.flags.rawValue { modifierLatch = true; DispatchQueue.main.async { self.activate(.scrolling) } }
                }
            } else if type == .keyUp {
                hyperHeld = false; modifierLatch = false; postHyperFlags(event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]))
            }
            return true
        }
        if hyper.enabled && hyperHeld { event.flags.formUnion(HyperController.flags) }
        if type == .leftMouseDown || type == .rightMouseDown { if mode != .idle { dismiss() }; return false }
        if type == .keyUp { held.removeValue(forKey: key); return swallowed.remove(key) != nil }
        if recording || paused { return false }
        let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        let mods = event.flags.intersection(relevant)
        if type == .flagsChanged {
            let click = Preferences.shared.clickShortcut; let scroll = Preferences.shared.scrollShortcut
            let action: NavigationMode? = click.keyCode == UInt16.max && mods.rawValue == click.modifiers ? .clicking : scroll.keyCode == UInt16.max && mods.rawValue == scroll.modifiers ? .scrolling : nil
            if let action, !modifierLatch { modifierLatch = true; DispatchQueue.main.async { self.activate(action) } }
            if action == nil { modifierLatch = false }
            return false
        }
        guard type == .keyDown else { return false }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 && swallowed.contains(key) { return true }
        if Preferences.shared.clickShortcut.matches(event) || Preferences.shared.scrollShortcut.matches(event) {
            let ignored = Preferences.shared.ignored.split(whereSeparator: { $0 == "\n" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }
            let app = NSWorkspace.shared.frontmostApplication
            if ignored.contains(app?.bundleIdentifier ?? "") || ignored.contains(app?.localizedName ?? "") { return false }
            let requested: NavigationMode = Preferences.shared.clickShortcut.matches(event) ? .clicking : .scrolling
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { DispatchQueue.main.async { self.activate(requested) } }
            swallowed.insert(key); return true
        }
        // A second Return immediately after a click completes a native double-click.
        if mode == .idle, key == 36, mods.isEmpty, let (target, date, oldPID) = lastClick,
           Date().timeIntervalSince(date) < NSEvent.doubleClickInterval, NSWorkspace.shared.frontmostApplication?.processIdentifier == oldPID {
            lastClick = nil; physicalClick(target, flags: [], count: 2); swallowed.insert(key); return true
        }
        guard mode != .idle else { return false }
        swallowed.insert(key)
        if key == 53 { dismiss(); return true }
        if mode == .loading { return true }
        if mode == .scrolling { handleScroll(key: key, text: unicode(event), flags: event.flags); return true }
        if key == 51 { if !prefix.isEmpty { prefix.removeLast(); selectFirstMatch(); render() }; return true }
        let controlN = event.flags.contains(.maskControl) && key == keyCodeForCharacter("n", fallback: 45)
        let controlP = event.flags.contains(.maskControl) && key == keyCodeForCharacter("p", fallback: 35)
        if key == 48 || key == 125 || key == 126 || controlN || controlP {
            let backwards = key == 126 || key == 48 && event.flags.contains(.maskShift) || controlP
            cycle(backwards ? -1 : 1); return true
        }
        if key == 36 || key == 49 { let flags = event.flags; DispatchQueue.main.async { self.clickSelected(flags: flags) }; return true }
        let text = unicode(event)
        if text == "?" { tutor.toggle(); render(); return true }
        // Global app commands cancel navigation and remain available; hint letters use the current input layout.
        if event.flags.contains(.maskCommand) && text.count != 1 { dismiss(); swallowed.remove(key); return false }
        if text.count == 1, let char = text.first, Preferences.shared.alphabet.contains(char) {
            let proposed = prefix + text
            if let match = targets.firstIndex(where: { $0.label.hasPrefix(proposed) }) {
                prefix = proposed; selected = match
                if targets[match].label == proposed && Preferences.shared.automatic { let flags = event.flags.subtracting(.maskShift); DispatchQueue.main.async { self.clickSelected(flags: flags) } }
                else { render() }
            } else { feedback(); prefix = ""; selectFirstMatch(); render() }
        }
        return true
    }
    private func selectFirstMatch() { selected = targets.firstIndex(where: { $0.label.hasPrefix(prefix) }) ?? 0 }
    private func cycle(_ delta: Int) {
        let indices = mode == .scrolling ? Array(areas.indices) : targets.indices.filter { targets[$0].label.hasPrefix(prefix) }
        guard !indices.isEmpty else { return }
        let position = indices.firstIndex(of: selected) ?? 0
        selected = indices[(position + delta + indices.count) % indices.count]; render()
    }
    private func clickSelected(flags: CGEventFlags) {
        guard targets.indices.contains(selected) else { feedback(); return }
        let target = targets[selected]; let oldPID = pid
        guard visiblePoint(target, windows: visibleWindows()) != nil else { render(message: "Target is covered by another window   ·   Esc exit"); return }
        guard let currentFrame = axFrame(target.element), currentFrame.intersects(target.frame), currentFrame.contains(CGPoint(x: target.frame.midX, y: target.frame.midY)), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            let desired = intended; dismiss(); activate(desired); return
        }
        let chain = Preferences.shared.chain && !target.isInput && !target.missionControl && !flags.contains(.maskShift)
        dismiss()
        if target.missionControl {
            let point = CGPoint(x: target.frame.midX, y: target.frame.midY)
            CGWarpMouseCursorPosition(point)
            let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
            move?.setIntegerValueField(.eventSourceUserData, value: eventMarker); move?.post(tap: .cghidEventTap)
        }
        if target.missionControl || target.role == "AXMenuBarItem" || target.role == "AXMenuItem", !flags.contains(.maskShift), !flags.contains(.maskCommand), target.actions.contains(kAXPressAction) {
            if AXUIElementPerformAction(target.element, kAXPressAction as CFString) != .success { physicalClick(target, flags: flags, count: 1) }
        } else { physicalClick(target, flags: flags, count: 1) }
        lastClick = !target.missionControl && !target.isInput && flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty ? (target, Date(), oldPID) : nil
        feedback(click: true)
        if chain { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.mode == .idle, NSWorkspace.shared.frontmostApplication?.processIdentifier == oldPID else { return }
            self.activate(.clicking)
        } }
    }
    private func physicalClick(_ target: Target, flags: CGEventFlags, count: Int) {
        guard let point = visiblePoint(target, windows: visibleWindows()) else { feedback(); return }
        CGWarpMouseCursorPosition(point)
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        move?.setIntegerValueField(.eventSourceUserData, value: eventMarker); move?.post(tap: .cghidEventTap)
        let right = flags.contains(.maskShift)
        let button: CGMouseButton = right ? .right : .left
        let down: CGEventType = right ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = right ? .rightMouseUp : .leftMouseUp
        for type in [down, up] {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { continue }
            event.flags = flags.intersection([.maskCommand, .maskAlternate, .maskControl])
            event.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
            event.post(tap: .cghidEventTap)
        }
    }
    private func handleScroll(key: UInt16, text: String, flags: CGEventFlags) {
        guard !areas.isEmpty else { return }
        let controlN = flags.contains(.maskControl) && key == keyCodeForCharacter("n", fallback: 45)
        let controlP = flags.contains(.maskControl) && key == keyCodeForCharacter("p", fallback: 35)
        if key == 48 || !Preferences.shared.arrowScroll && [125, 126].contains(key) || controlN || controlP {
            cycle(key == 126 || key == 48 && flags.contains(.maskShift) || controlP ? -1 : 1); return
        }
        if let number = Int(text), areas.indices.contains(number) { selected = number; render(); return }
        let keys = Array(Preferences.shared.scrollKeys.uppercased())
        var vector: (Double, Double)?
        if keys.count == 4, let char = text.first, let index = keys.firstIndex(of: char) {
            vector = [(0, 1), (-1, 0), (1, 0), (0, -1)][index]
        }
        if Preferences.shared.arrowScroll {
            if key == 123 { vector = (0, 1) }; if key == 124 { vector = (0, -1) }
            if key == 125 { vector = (-1, 0) }; if key == 126 { vector = (1, 0) }
        }
        if let vector {
            let multiplier = flags.contains(.maskShift) ? Preferences.shared.dashSpeed : Preferences.shared.speed
            held[key] = (vector.0 * multiplier, vector.1 * multiplier)
            scroll(vertical: vector.0 * multiplier * 30, horizontal: vector.1 * multiplier * 30)
            if scrollTimer == nil { scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                guard let self else { return }
                if self.held.isEmpty { self.scrollTimer?.invalidate(); self.scrollTimer = nil; return }
                self.scroll(vertical: self.held.values.reduce(0) { $0 + $1.0 } * 10, horizontal: self.held.values.reduce(0) { $0 + $1.1 } * 10)
            } }
            return
        }
        if Preferences.shared.commands {
            let height = areas[selected].frame.height
            if text == "D" || text == "U" { scroll(vertical: text == "D" ? -height / 2 : height / 2, horizontal: 0) }
            if text == "G", flags.contains(.maskShift) { scroll(vertical: -100000, horizontal: 0); lastG = nil }
            else if text == "G" {
                if let last = lastG, Date().timeIntervalSince(last) < 0.6 { scroll(vertical: 100000, horizontal: 0); lastG = nil }
                else { lastG = Date() }
            }
        }
        if Preferences.shared.autoDeactivate { dismiss() }
    }
    private func scroll(vertical: Double, horizontal: Double) {
        guard mode == .scrolling, areas.indices.contains(selected), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { dismiss(); return }
        let target = areas[selected]
        let nested = areas.enumerated().filter { $0.offset != selected && target.frame.contains($0.element.frame) }.map { $0.element.frame }
        guard let point = visiblePoint(target, windows: visibleWindows(), avoiding: nested) else { render(message: "Scroll area is covered by another window   ·   Esc exit"); held.removeAll(); return }
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(vertical), wheel2: Int32(horizontal), wheel3: 0) else { return }
        // Chromium routes wheel events using its last mouse hit-test, so update the
        // pointer before scrolling a different region. WebKit also accepts wheel.location.
        if scrollPoint != point {
            let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
            move?.setIntegerValueField(.eventSourceUserData, value: eventMarker)
            move?.post(tap: .cghidEventTap)
            CGWarpMouseCursorPosition(point)
            scrollPoint = point
        }
        event.location = point; event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
        event.post(tap: .cghidEventTap)
    }
    private func feedback(click: Bool = false) {
        if Preferences.shared.sounds, let sound = NSSound(named: click ? "Pop" : "Tink") { sound.volume = Float(Preferences.shared.volume); sound.play() }
    }
    private func postHyperFlags(_ flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: !flags.isEmpty) else { return }
        event.type = .flagsChanged; event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: eventMarker); event.post(tap: .cgSessionEventTap)
    }
    func shutdown() {
        dismiss(); if hyperHeld { postHyperFlags([]); hyperHeld = false }
        try? hyper.update(false); stopTap()
    }
    private func writeDiagnostics(result: ScanResult? = nil) {
        guard let url = diagnosticsURL else { return }
        let serialize: (Target) -> [String: Any] = { ["label": $0.label, "title": $0.title, "role": $0.role, "frame": [Double($0.frame.minX), Double($0.frame.minY), Double($0.frame.width), Double($0.frame.height)]] }
        var payload: [String: Any] = ["mode": mode.rawValue, "trusted": trusted, "listening": listening, "pid": pid, "frontApp": NSWorkspace.shared.frontmostApplication?.localizedName ?? "", "selected": selected, "prefix": prefix, "targets": targets.map(serialize), "areas": areas.map(serialize)]
        if let result { payload["visited"] = result.visited; payload["truncated"] = result.truncated; payload["milliseconds"] = result.milliseconds }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url, options: .atomic) }
    }
}
