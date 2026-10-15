import AppKit
import ApplicationServices

enum NavigationMode: String { case idle, clicking, scrolling, loading }

private final class ScanTicket {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

final class Engine: ObservableObject {
    @Published var trusted = AXIsProcessTrusted()
    @Published var listening = false
    @Published var paused = false { didSet { if paused { dismiss() } } }
    @Published var hyperError = ""
    private let hyper = HyperController()
    private var hyperHeld = false
    private var hyperPresses = 0
    private var readyMilliseconds = 0.0
    private var invalidationReason = "startup"
    private var cacheRevision = 0
    private var activeScanRevision = 0
    private var cachedScan: (pid: pid_t, window: AXUIElement, frame: CGRect, revision: Int, result: ScanResult, time: Double, scrollComplete: Bool)?
    private var warmup: DispatchWorkItem?
    private var warming = false
    private var warmTicket: ScanTicket?
    private var warmTimer: Timer?
    private var observer: AXObserver?
    private var observerPID: pid_t = 0
    private var observedElements = Set<AXUIElement>()
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
    private let scanner = AccessibilityScanner()
    private let scanQueue = DispatchQueue(label: "keyrow.accessibility", qos: .userInteractive)
    private var held: [UInt16: (Double, Double)] = [:]
    private var scrollTimer: Timer?
    private var permissionTimer: Timer?
    private var missionTimer: Timer?
    private let missionQueue = DispatchQueue(label: "keyrow.mission-control", qos: .utility)
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
            self.invalidateScan(reason: "application")
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.dismiss(); self?.invalidateScan() }
    }
    func start() {
        refreshPermission()
        invalidateScan()
        warmTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.mode == .idle else { return }
            if self.cachedScan == nil || ProcessInfo.processInfo.systemUptime - (self.cachedScan?.time ?? 0) > 1.5 { self.scheduleWarmup() }
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshPermission() }
        missionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.trusted, !self.paused, !self.recording, Preferences.shared.missionControl else { return }
            self.missionQueue.async {
                let open = missionControlRoot() != nil
                DispatchQueue.main.async {
                    let changed = open != self.missionWasOpen
                    self.missionWasOpen = open
                    if open && changed && self.mode == .idle { self.activate(.clicking) }
                    if !open && changed && self.mode != .idle { self.dismiss() }
                }
            }
        }
    }
    func refreshPermission() {
        let allowed = AXIsProcessTrusted()
        if trusted != allowed { trusted = allowed }
        if allowed && tap == nil { installTap() }
        if !allowed && tap != nil { stopTap(); dismiss() }
        if allowed {
            do { try hyper.update(Preferences.shared.hyper); hyperError = "" }
            catch { hyperError = error.localizedDescription }
        }
        if mode == .idle { writeDiagnostics() }
    }
    private func installTap() {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .scrollWheel]
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
    // Layout and destruction notifications can describe decorative content. Keep a
    // candidate only when activation can re-query its semantic controls and
    // validate their geometry; input and window changes still discard it.
    private func invalidateScan(reason: String = "input", allowValidation: Bool = false) {
        invalidationReason = reason
        warmTicket?.cancel()
        cacheRevision += 1
        if !allowValidation { cachedScan = nil }
        scheduleWarmup()
    }
    private func watch(_ application: AXUIElement, pid: pid_t, roots: [AXUIElement] = []) {
        if observerPID != pid {
            if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
            observer = nil; observerPID = pid; observedElements.removeAll()
            var created: AXObserver?
            if AXObserverCreate(pid, { _, _, notification, context in
                guard let context else { return }
                Unmanaged<Engine>.fromOpaque(context).takeUnretainedValue().invalidateScan(reason: notification as String, allowValidation: ["AXLayoutChanged", "AXUIElementDestroyed"].contains(notification as String))
            }, &created) == .success, let created {
                observer = created
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
            }
        }
        guard let observer else { return }
        let names = ["AXLayoutChanged", "AXLoadComplete", "AXFocusedWindowChanged", "AXWindowCreated", "AXUIElementDestroyed", "AXSelectedChildrenChanged", "AXMoved", "AXResized"]
        for element in [application] + roots where observedElements.insert(element).inserted {
            for name in names { AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(self).toOpaque()) }
            // Scroll position changes must invalidate geometry before another activation.
            if axValue(element, kAXRoleAttribute) as? String == "AXScrollArea" {
                AXObserverAddNotification(observer, element, kAXValueChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
        }
    }
    private func scheduleWarmup() {
        warmup?.cancel()
        guard trusted, !paused, !recording, mode == .idle else { return }
        let task = DispatchWorkItem { [weak self] in self?.prepareScan() }
        warmup = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.075, execute: task)
    }
    private func prepareScan() {
        guard !warming, trusted, !paused, !recording, mode == .idle, !missionWasOpen,
              let app = NSWorkspace.shared.frontmostApplication else { return }
        let appPID = app.processIdentifier
        let application = AXUIElementCreateApplication(appPID)
        guard let window = axElement(application, kAXFocusedWindowAttribute), let frame = axFrame(window) else { return }
        watch(application, pid: appPID, roots: [window])
        let revision = cacheRevision
        let screens = overlay.screenRects; let exhaustive = Preferences.shared.exhaustive
        warming = true
        let ticket = ScanTicket(); warmTicket = ticket
        scanQueue.async { [weak self] in
            guard let scanner = self?.scanner else { return }
            let result = scanner.scan(pid: appPID, screens: screens, exhaustive: exhaustive, scrolling: false, cancelled: { ticket.cancelled })
            DispatchQueue.main.async {
                guard let self else { return }
                self.warming = false
                if ticket.cancelled { self.scheduleWarmup(); return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == appPID else { self.scheduleWarmup(); return }
                self.watch(application, pid: appPID, roots: result.observationRoots)
                if self.cacheRevision == revision, result.sourceWindow == window, axElement(application, kAXFocusedWindowAttribute) == window {
                    self.cachedScan = (appPID, window, frame, revision, result, ProcessInfo.processInfo.systemUptime, false)
                } else { self.scheduleWarmup() }
            }
        }
    }
    func activate(_ requested: NavigationMode) {
        if mode == requested || intended == requested && mode == .loading { dismiss(); return }
        guard !paused, trusted, let app = NSWorkspace.shared.frontmostApplication else { return }
        let ignored = Preferences.shared.ignored.split(whereSeparator: { $0 == "\n" || $0 == "," }).map { $0.trimmingCharacters(in: .whitespaces) }
        guard !ignored.contains(app.bundleIdentifier ?? ""), !ignored.contains(app.localizedName ?? "") else { return }
        let activationStart = ProcessInfo.processInfo.systemUptime
        generation += 1; let current = generation
        activeScanRevision = cacheRevision
        pid = app.processIdentifier; let appPID = pid
        mode = .loading; intended = requested; prefix = ""; selected = 0; tutor = false
        warmup?.cancel()
        warmTicket?.cancel()
        let mission = missionWasOpen || ["com.apple.dock", "com.apple.WindowManager"].contains(app.bundleIdentifier ?? "")
        if !mission, let cached = cachedScan, cached.pid == appPID, cached.revision == cacheRevision || !cached.result.controlQueries.isEmpty,
           requested != .scrolling || cached.scrollComplete,
           ProcessInfo.processInfo.systemUptime - cached.time < 3,
           let window = axElement(AXUIElementCreateApplication(appPID), kAXFocusedWindowAttribute), window == cached.window,
           axFrame(window) == cached.frame {
            let screens = overlay.screenRects; let exhaustive = Preferences.shared.exhaustive
            scanQueue.async { [weak self] in
                guard let scanner = self?.scanner else { return }
                let validation: (valid: Bool, reason: String)
                if appPID == getpid() { validation = DispatchQueue.main.sync { preparedControlsAreCurrent(cached.result, pid: appPID) } }
                else { validation = preparedControlsAreCurrent(cached.result, pid: appPID) }
                let valid = validation.valid
                var result: ScanResult
                if valid { result = cached.result; result.cached = true }
                else {
                    DispatchQueue.main.sync { self?.invalidateScan(); self?.activeScanRevision = self?.cacheRevision ?? 0 }
                    result = scanner.scan(pid: appPID, screens: screens, exhaustive: exhaustive, scrolling: requested == .scrolling)
                    result.phases["invalid_" + validation.reason] = 1
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    if valid, var refreshed = self.cachedScan { refreshed.time = ProcessInfo.processInfo.systemUptime; refreshed.revision = self.cacheRevision; self.cachedScan = refreshed }
                    let windows = visibleWindows()
                    result.targets = result.targets.filter { visiblePoint($0, windows: windows) != nil }
                    self.completeActivation(result, requested: requested, generation: current, start: activationStart)
                }
            }
            return
        }
        warmTicket?.cancel()
        let screens = overlay.screenRects; let exhaustive = Preferences.shared.exhaustive
        overlay.show(targets: [], prefix: "", selected: 0, scrolling: false, message: "Reading controls…   ·   Esc exit")
        scanQueue.async { [weak self] in
            guard let scanner = self?.scanner else { return }
            let result = scanner.scan(pid: appPID, screens: screens, exhaustive: exhaustive, mission: mission, scrolling: requested == .scrolling)
            DispatchQueue.main.async { self?.completeActivation(result, requested: requested, generation: current, start: activationStart) }
        }
    }
    private func completeActivation(_ result: ScanResult, requested: NavigationMode, generation current: Int, start: Double) {
        guard generation == current, pid == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        // Zen can briefly focus a floating address editor while its main window
        // changes. Do not save or display that scan as the next window's controls.
        if !missionWasOpen, let source = result.sourceWindow,
           let focused = axElement(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute), source != focused {
            guard ProcessInfo.processInfo.systemUptime - start < 1 else { dismiss(); return }
            let appPID = pid; let screens = overlay.screenRects; let exhaustive = Preferences.shared.exhaustive
            scanQueue.async { [weak self] in
                guard let self else { return }
                let next = self.scanner.scan(pid: appPID, screens: screens, exhaustive: exhaustive, scrolling: requested == .scrolling)
                DispatchQueue.main.async { self.completeActivation(next, requested: requested, generation: current, start: start) }
            }
            return
        }
        if !result.cached, !missionWasOpen, activeScanRevision == cacheRevision {
            let application = AXUIElementCreateApplication(pid)
            if let window = axElement(application, kAXFocusedWindowAttribute), let frame = axFrame(window) {
                watch(application, pid: pid, roots: result.observationRoots)
                cachedScan = (pid, window, frame, cacheRevision, result, ProcessInfo.processInfo.systemUptime, requested == .scrolling)
            }
        }
        targets = result.targets; areas = result.areas
        let labels = Labels.generate(targets.count, alphabet: Preferences.shared.alphabet)
        for index in targets.indices { targets[index].label = labels[index] }
        for index in areas.indices { areas[index].label = String(index) }
        mode = requested
        let empty = requested == .clicking ? targets.isEmpty : areas.isEmpty
        render(message: empty ? "No accessible \(requested == .clicking ? "controls" : "scroll areas")   ·   Esc exit" : result.truncated ? "\(targets.count) targets   ·   Scan limit reached   ·   Esc exit" : "", writeState: false)
        overlay.flush()
        readyMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        var measured = result
        if !result.cached { measured.phases["invalidation_" + invalidationReason] = 1 }
        writeDiagnostics(result: measured)
        if let url = diagnosticsURL { overlay.savePreview(to: url.deletingLastPathComponent().appendingPathComponent("overlay-preview.png")) }
    }
    func dismiss() {
        generation += 1; mode = .idle; intended = .idle; prefix = ""; held.removeAll()
        scrollTimer?.invalidate(); scrollTimer = nil; overlay.hide(); writeDiagnostics()
        scrollPoint = nil
        scheduleWarmup()
    }
    private func render(message: String = "", writeState: Bool = true) {
        overlay.show(targets: mode == .scrolling ? areas : targets, prefix: prefix, selected: selected, scrolling: mode == .scrolling, message: message, tutor: tutor)
        if writeState { writeDiagnostics() }
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
                hyperPresses += 1; hyperHeld = true; postHyperFlags(HyperController.flags)
                if !recording && !paused {
                    let click = Preferences.shared.clickShortcut; let scroll = Preferences.shared.scrollShortcut
                    if click.keyCode == UInt16.max && click.modifiers == HyperController.flags.rawValue { modifierLatch = true; DispatchQueue.main.async { self.activate(.clicking) } }
                    else if scroll.keyCode == UInt16.max && scroll.modifiers == HyperController.flags.rawValue { modifierLatch = true; DispatchQueue.main.async { self.activate(.scrolling) } }
                }
            } else if type == .keyUp {
                hyperHeld = false; modifierLatch = false; postHyperFlags(CGEventSource.flagsState(.hidSystemState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]))
            }
            return true
        }
        if hyper.enabled && hyperHeld { event.flags.formUnion(HyperController.flags) }
        if type == .scrollWheel { invalidateScan(); return false }
        if type == .leftMouseDown || type == .rightMouseDown { invalidateScan(); if mode != .idle { dismiss() }; return false }
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
        guard mode != .idle else { invalidateScan(); return false }
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
        invalidateScan()
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
        let plainClick = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
        if target.role == "AXComboBox", plainClick, AXUIElementSetAttributeValue(target.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success {
            // Focus the actual editor rather than a button sharing its AX bounds.
        } else if target.missionControl || target.role == "AXMenuBarItem" || target.role == "AXMenuItem", !flags.contains(.maskShift), !flags.contains(.maskCommand), target.actions.contains(kAXPressAction) {
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
        invalidateScan()
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
        warmTimer?.invalidate(); warmup?.cancel(); warmTicket?.cancel()
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        dismiss(); warmup?.cancel(); if hyperHeld { postHyperFlags([]); hyperHeld = false }
        try? hyper.update(false); stopTap()
    }
    private func writeDiagnostics(result: ScanResult? = nil) {
        guard let url = diagnosticsURL else { return }
        let serialize: (Target) -> [String: Any] = { ["label": $0.label, "title": $0.title, "role": $0.role, "frame": [Double($0.frame.minX), Double($0.frame.minY), Double($0.frame.width), Double($0.frame.height)]] }
        var payload: [String: Any] = ["ready_ms": readyMilliseconds, "hyper_enabled": hyper.enabled, "hyper_held": hyperHeld, "hyper_presses": hyperPresses, "hyper_error": hyperError, "mode": mode.rawValue, "trusted": trusted, "listening": listening, "pid": pid, "frontApp": NSWorkspace.shared.frontmostApplication?.localizedName ?? "", "selected": selected, "prefix": prefix, "targets": targets.map(serialize), "areas": areas.map(serialize)]
        if let result { payload["cache_hit"] = result.cached; payload["phases"] = result.phases; payload["visited"] = result.visited; payload["truncated"] = result.truncated; payload["milliseconds"] = result.milliseconds }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url, options: .atomic) }
    }
}
