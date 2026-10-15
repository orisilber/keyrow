import AppKit
import ApplicationServices
import Combine
import Carbon

func keyCodeForCharacter(_ character: String, fallback: UInt16, command: Bool = false) -> UInt16 {
    let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return fallback }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
    let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
    for key: UInt16 in 0..<128 {
        var dead: UInt32 = 0; var length = 0; var chars = [UniChar](repeating: 0, count: 4)
        let result = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown), command ? UInt32(cmdKey >> 8) : 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
        if result == noErr && String(utf16CodeUnits: chars, count: length).lowercased() == character.lowercased() { return key }
    }
    return fallback
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64
    var display: String
    static let click = Shortcut(keyCode: 49, modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue, display: "⇧⌘Space")
    static var scroll: Shortcut { Shortcut(keyCode: keyCodeForCharacter("j", fallback: 38, command: true), modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue, display: "⇧⌘J") }
    func matches(_ event: CGEvent) -> Bool {
        let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        return UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == keyCode && event.flags.intersection(relevant).rawValue == modifiers
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()
    @Published var theme: String { didSet { save() } }
    @Published var labelSize: Double { didSet { save() } }
    @Published var characters: String { didSet { save() } }
    @Published var automatic: Bool { didSet { save() } }
    @Published var chain: Bool { didSet { save() } }
    @Published var exhaustive: Bool { didSet { save() } }
    @Published var clickShortcut: Shortcut { didSet { save() } }
    @Published var scrollShortcut: Shortcut { didSet { save() } }
    @Published var scrollKeys: String { didSet { save() } }
    @Published var arrowScroll: Bool { didSet { save() } }
    @Published var numbers: Bool { didSet { save() } }
    @Published var commands: Bool { didSet { save() } }
    @Published var autoDeactivate: Bool { didSet { save() } }
    @Published var speed: Double { didSet { save() } }
    @Published var dashSpeed: Double { didSet { save() } }
    @Published var sounds: Bool { didSet { save() } }
    @Published var volume: Double { didSet { save() } }
    @Published var ignored: String { didSet { save() } }
    @Published var missionControl: Bool { didSet { save() } }
    @Published var hyper: Bool { didSet { save() } }
    private let defaults = UserDefaults.standard
    init() {
        let d = UserDefaults.standard
        theme = d.string(forKey: "theme") ?? "Dark"
        labelSize = d.object(forKey: "labelSize") as? Double ?? 10
        characters = d.string(forKey: "characters") ?? "ARSTNEIO"
        automatic = d.object(forKey: "automatic") as? Bool ?? true
        chain = d.bool(forKey: "chain")
        exhaustive = d.bool(forKey: "exhaustive")
        clickShortcut = d.data(forKey: "clickShortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .click
        scrollShortcut = d.data(forKey: "scrollShortcut").flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) } ?? .scroll
        scrollKeys = d.string(forKey: "scrollKeys") ?? "HJKL"
        arrowScroll = d.bool(forKey: "arrowScroll")
        numbers = d.object(forKey: "numbers") as? Bool ?? true
        commands = d.object(forKey: "commands") as? Bool ?? true
        autoDeactivate = d.bool(forKey: "autoDeactivate")
        speed = d.object(forKey: "speed") as? Double ?? 1
        dashSpeed = d.object(forKey: "dashSpeed") as? Double ?? 1.5
        sounds = d.bool(forKey: "sounds")
        volume = d.object(forKey: "volume") as? Double ?? 0.6
        ignored = d.string(forKey: "ignored") ?? ""
        missionControl = d.object(forKey: "missionControl") as? Bool ?? true
        hyper = d.bool(forKey: "hyper")
    }
    var alphabet: [Character] {
        var seen = Set<Character>()
        let clean = characters.uppercased().filter { $0.isASCII && $0.isLetter && seen.insert($0).inserted }
        return Array(clean.count >= 2 ? clean : "ARSTNEIO")
    }
    func save() {
        defaults.set(theme, forKey: "theme"); defaults.set(labelSize, forKey: "labelSize")
        defaults.set(characters, forKey: "characters"); defaults.set(automatic, forKey: "automatic")
        defaults.set(chain, forKey: "chain"); defaults.set(exhaustive, forKey: "exhaustive")
        defaults.set(try? JSONEncoder().encode(clickShortcut), forKey: "clickShortcut")
        defaults.set(try? JSONEncoder().encode(scrollShortcut), forKey: "scrollShortcut")
        defaults.set(scrollKeys, forKey: "scrollKeys"); defaults.set(arrowScroll, forKey: "arrowScroll")
        defaults.set(numbers, forKey: "numbers"); defaults.set(commands, forKey: "commands")
        defaults.set(autoDeactivate, forKey: "autoDeactivate"); defaults.set(speed, forKey: "speed")
        defaults.set(dashSpeed, forKey: "dashSpeed"); defaults.set(sounds, forKey: "sounds")
        defaults.set(volume, forKey: "volume"); defaults.set(ignored, forKey: "ignored")
        defaults.set(missionControl, forKey: "missionControl"); defaults.set(hyper, forKey: "hyper")
    }
}

enum Labels {
    // Expanding a leaf instead of mixing one- and two-letter codes makes every code prefix-free.
    static func generate(_ count: Int, alphabet: [Character]) -> [String] {
        guard count > 0, alphabet.count >= 2 else { return [] }
        var leaves = alphabet.map(String.init)
        while leaves.count < count {
            let prefix = leaves.removeLast()
            leaves.insert(contentsOf: alphabet.map { prefix + String($0) }, at: 0)
        }
        return Array(leaves.prefix(count)).sorted { a, b in
            if a.count != b.count { return a.count < b.count }
            return a.lexicographicallyPrecedes(b, by: { alphabet.firstIndex(of: $0)! < alphabet.firstIndex(of: $1)! })
        }
    }
}

func axValue(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
func axElement(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = axValue(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let p = axValue(element, kAXPositionAttribute), let s = axValue(element, kAXSizeAttribute),
          CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero; var size = CGSize.zero
    guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
          point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite else { return nil }
    return CGRect(origin: point, size: size)
}
struct Target {
    let element: AXUIElement
    var frame: CGRect
    let role: String
    let title: String
    var label: String = ""
    let actions: [String]
    var sourceFrame: CGRect? = nil
    var url = ""
    var missionControl = false
    var isInput: Bool { ["AXTextField", "AXTextArea", "AXComboBox"].contains(role) }
    var ownerPID: pid_t { var pid: pid_t = 0; AXUIElementGetPid(element, &pid); return pid }
}

struct VisibleWindow {
    let pid: pid_t
    let frame: CGRect
}
func visibleWindows() -> [VisibleWindow] {
    guard let data = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
    return data.compactMap { item in
        guard let owner = item[kCGWindowOwnerPID as String] as? Int,
              owner != Int(getpid()) || (item[kCGWindowLayer as String] as? Int ?? 0) == 0,
              (item[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
              let bounds = item[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return VisibleWindow(pid: pid_t(owner), frame: frame)
    }
}
func visiblePoint(_ target: Target, windows: [VisibleWindow], avoiding: [CGRect] = []) -> CGPoint? {
    if target.missionControl { return CGPoint(x: target.frame.midX, y: target.frame.midY) }
    let ownerPID = target.ownerPID
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.15)
    // Browser address bars may include extension buttons inside the reported
    // combo-box bounds. Prefer the editable leading portion when clicking it.
    let leading: [(Double, Double)] = target.role == "AXComboBox" ? [(0.15, 0.5)] : []
    for (x, y) in leading + [(0.5, 0.5), (0.15, 0.15), (0.85, 0.15), (0.15, 0.85), (0.85, 0.85), (0.05, 0.5), (0.95, 0.5), (0.5, 0.05), (0.5, 0.95), (0.01, 0.01), (0.99, 0.99)] {
        let point = CGPoint(x: target.frame.minX + target.frame.width * x, y: target.frame.minY + target.frame.height * y)
        guard !avoiding.contains(where: { $0.contains(point) }) else { continue }
        let coveringWindow = windows.first(where: { $0.frame.contains(point) })
        if target.role == "AXMenuBarItem" || coveringWindow == nil || coveringWindow?.pid == ownerPID { return point }
        // Window bounds also include transparent, click-through system surfaces,
        // such as Notification Center's full-screen host. Ask Accessibility which
        // app actually receives this point before treating that surface as cover.
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success, let hit {
            var hitPID: pid_t = 0
            if AXUIElementGetPid(hit, &hitPID) == .success && hitPID == ownerPID { return point }
        }
    }
    return nil
}
struct ControlQuery {
    let root: AXUIElement
    let elements: Set<AXUIElement>
}
struct ControlGeometry {
    let element: AXUIElement
    let frame: CGRect
    let enabled: Bool
}
func semanticControls(_ element: AXUIElement) -> [AXUIElement]? {
    let predicate: [String: Any] = ["AXSearchKey": ["AXControlSearchKey", "AXLinkSearchKey"],
        "AXResultsLimit": 3000, "AXDirection": "AXDirectionNext", "AXVisibleOnly": true]
    var found: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(element, "AXUIElementsForSearchPredicate" as CFString, predicate as CFDictionary, &found) == .success else { return nil }
    return found as? [AXUIElement]
}
func preparedControlsAreCurrent(_ result: ScanResult, pid: pid_t) -> (valid: Bool, reason: String) {
    // Gecko does not emit a layout notification for every ordinary DOM insertion.
    for query in result.controlQueries {
        guard let current = semanticControls(query.root), Set(current) == query.elements else { return (false, "query_" + (axValue(query.root, kAXRoleAttribute) as? String ?? "unknown")) }
    }
    var seen = Set<AXUIElement>()
    let geometry = (result.targets + result.areas).compactMap { target -> ControlGeometry? in
        guard seen.insert(target.element).inserted else { return nil }
        return ControlGeometry(element: target.element, frame: target.sourceFrame ?? target.frame, enabled: true)
    } + result.disabledControls
    let lock = NSLock(); var valid = true
    let workers = pid == getpid() ? 1 : min(8, max(1, geometry.count))
    func check(_ worker: Int) {
        for index in stride(from: worker, to: geometry.count, by: workers) {
            lock.lock(); let stop = !valid; lock.unlock(); if stop { return }
            let old = geometry[index]
            var raw: CFArray?
            let names = [kAXPositionAttribute, kAXSizeAttribute, kAXEnabledAttribute, "AXHidden"]
            let success = AXUIElementCopyMultipleAttributeValues(old.element, names as CFArray, [], &raw)
            var matches = false
            if success == .success, let values = raw as? [CFTypeRef], values.count == 4,
               CFGetTypeID(values[0]) == AXValueGetTypeID(), CFGetTypeID(values[1]) == AXValueGetTypeID() {
                var point = CGPoint.zero; var size = CGSize.zero
                if AXValueGetValue(values[0] as! AXValue, .cgPoint, &point), AXValueGetValue(values[1] as! AXValue, .cgSize, &size) {
                    matches = abs(point.x - old.frame.minX) < 1 && abs(point.y - old.frame.minY) < 1 && abs(size.width - old.frame.width) < 1 && abs(size.height - old.frame.height) < 1 && (values[2] as? Bool ?? true) == old.enabled && values[3] as? Bool != true
                }
            }
            if !matches { lock.lock(); valid = false; lock.unlock(); return }
        }
    }
    if workers == 1 { check(0) } else { DispatchQueue.concurrentPerform(iterations: workers, execute: check) }
    return (valid, valid ? "" : "geometry")
}
struct ScanResult {
    var targets: [Target]
    var areas: [Target]
    var visited: Int
    var truncated: Bool
    var milliseconds: Int
    var phases: [String: Double] = [:]
    var observationRoots: [AXUIElement] = []
    var cached = false
    var controlQueries: [ControlQuery] = []
    var disabledControls: [ControlGeometry] = []
    var sourceWindow: AXUIElement? = nil
}

func missionControlRoot() -> AXUIElement? {
    if let manager = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager").first {
        let app = AXUIElementCreateApplication(manager.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.08)
        if (axValue(app, kAXChildrenAttribute) as? [AXUIElement] ?? []).contains(where: {
            (axValue($0, kAXIdentifierAttribute) as? String ?? "") == "mc.display" && !(axValue($0, kAXChildrenAttribute) as? [AXUIElement] ?? []).isEmpty
        }) { return app }
    }
    guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
    let app = AXUIElementCreateApplication(dock.processIdentifier)
    AXUIElementSetMessagingTimeout(app, 0.08)
    return (axValue(app, kAXChildrenAttribute) as? [AXUIElement] ?? []).first {
        ["mc", "appexpose"].contains(axValue($0, kAXIdentifierAttribute) as? String ?? "") && !(axValue($0, kAXChildrenAttribute) as? [AXUIElement] ?? []).isEmpty
    }
}

// Fetch each element in one cross-process request, then reuse it throughout a scan.
private struct ElementSnapshot {
    let element: AXUIElement
    let values: [CFTypeRef]
    static let names = [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute,
        kAXEnabledAttribute, kAXChildrenAttribute, kAXTitleAttribute,
        kAXDescriptionAttribute, kAXURLAttribute, "AXHidden",
        "AXVerticalScrollBar", "AXHorizontalScrollBar"]
    init(_ element: AXUIElement, light: Bool = false) {
        self.element = element
        var result: CFArray?
        AXUIElementCopyMultipleAttributeValues(element, (light ? Array(Self.names.prefix(9)) : Self.names) as CFArray, [], &result)
        var fetched = result as? [CFTypeRef] ?? []
        while fetched.count < Self.names.count { fetched.append(kCFNull) }
        values = fetched
    }
    func value(_ index: Int) -> CFTypeRef? {
        guard values.indices.contains(index), CFGetTypeID(values[index]) != CFNullGetTypeID(), CFGetTypeID(values[index]) != AXValueGetTypeID() || AXValueGetType(values[index] as! AXValue) != .axError else { return nil }
        return values[index]
    }
    var role: String { value(0) as? String ?? "" }
    var children: [AXUIElement] { value(4) as? [AXUIElement] ?? [] }
    var title: String {
        if let text = [5, 6].compactMap({ value($0) as? String }).first(where: { !$0.isEmpty }) { return text }
        if ["AXTextField", "AXTextArea", "AXComboBox"].contains(role), let placeholder = axValue(element, "AXPlaceholderValue") as? String, !placeholder.isEmpty { return placeholder }
        return role.replacingOccurrences(of: "AX", with: "")
    }
    var url: String {
        guard let v = value(7) else { return "" }
        if let text = v as? String { return text }
        return CFGetTypeID(v) == CFURLGetTypeID() ? (v as! URL).absoluteString : ""
    }
    var frame: CGRect? {
        guard let p = value(1), let s = value(2), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
              point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite else { return nil }
        return CGRect(origin: point, size: size)
    }
}

final class AccessibilityScanner {
    private var prepared = Set<pid_t>()
    func scan(pid: pid_t, screens: [CGRect], exhaustive: Bool, mission: Bool = false, scrolling: Bool = false, cancelled: () -> Bool = { false }) -> ScanResult {
        // In-process AX calls can invoke SwiftUI directly. They must stay on its
        // main actor, unlike cross-process Accessibility requests to other apps.
        if pid == getpid() && !Thread.isMainThread {
            return DispatchQueue.main.sync { self.scan(pid: pid, screens: screens, exhaustive: exhaustive, mission: mission, scrolling: scrolling, cancelled: cancelled) }
        }
        let start = Date(); let deadline = start.addingTimeInterval(exhaustive ? 3 : 1)
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.08)
        if prepared.insert(pid).inserted {
            AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        var cache: [AXUIElement: ElementSnapshot] = [:]
        func snapshot(_ element: AXUIElement) -> ElementSnapshot {
            if let saved = cache[element] { return saved }
            let node = ElementSnapshot(element, light: !scrolling && !exhaustive); cache[element] = node; return node
        }
        func prefetch(_ elements: [AXUIElement]) {
            let missing = elements.filter { cache[$0] == nil }
            guard pid != getpid(), missing.count >= 4 else { return }
            let lock = NSLock()
            var loaded: [AXUIElement: ElementSnapshot] = [:]
            let workers = min(8, missing.count)
            DispatchQueue.concurrentPerform(iterations: workers) { worker in
                for index in stride(from: worker, to: missing.count, by: workers) {
                    if cancelled() { return }
                    let node = ElementSnapshot(missing[index], light: !scrolling && !exhaustive)
                    lock.lock(); loaded[missing[index]] = node; lock.unlock()
                }
            }
            cache.merge(loaded) { old, _ in old }
        }
        var observationRoots: [AXUIElement] = []
        var controlQueries: [ControlQuery] = []
        var disabledControls: [ControlGeometry] = []
        var targets: [Target] = []; var areas: [Target] = []; var visited = Set<AXUIElement>()
        var roots: [(AXUIElement, CGRect?)] = []
        var sourceWindow: AXUIElement?
        if let window = axElement(application, kAXFocusedWindowAttribute) ?? axElement(application, kAXMainWindowAttribute) {
            sourceWindow = window
            roots.append((window, snapshot(window).frame))
        } else {
            for window in axValue(application, kAXWindowsAttribute) as? [AXUIElement] ?? [] { roots.append((window, snapshot(window).frame)) }
        }
        if let menu = axElement(application, kAXMenuBarAttribute) { roots.append((menu, nil)) }
        for child in axValue(application, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            let role = snapshot(child).role
            if role == "AXMenu" || role == "AXPopover" { roots.append((child, nil)) }
        }
        let missionRoot = mission ? missionControlRoot() : nil
        if let missionRoot { roots = [(missionRoot, nil)] }
        let rootsTime = ProcessInfo.processInfo.systemUptime
        let roles: Set<String> = ["AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXMenuItem", "AXMenuBarItem", "AXTextField", "AXTextArea", "AXComboBox", "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXTab", "AXRow", "AXCell"]
        var stack = roots.reversed().map { ($0.0, $0.1, 0, false, false) }
        let maxNodes = exhaustive ? 40000 : 16000
        while let (element, clip, depth, inWeb, queryLeaf) = stack.popLast(), visited.count < maxNodes, Date() < deadline, !cancelled() {
            guard depth < 90, visited.insert(element).inserted else { continue }
            let node = snapshot(element); let role = node.role
            if node.value(8) as? Bool == true { continue }
            if ["AXWindow", "AXWebArea", "AXScrollArea"].contains(role) { observationRoots.append(element) }
            let controlsInDocument = role == "AXWebArea" ? semanticControls(element) : nil
            if let controlsInDocument { controlQueries.append(ControlQuery(root: element, elements: Set(controlsInDocument))) }
            let web = inWeb || role == "AXWebArea"
            let frame = node.frame
            // Offscreen web subtrees contain hundreds of controls in long feeds.
            if web, let frame, frame.width > 2, frame.height > 2, let clip, !frame.intersects(clip) { continue }
            let enabled = node.value(3) as? Bool ?? true
            let children = queryLeaf ? [] : node.children
            var visible: CGRect?
            if let frame, frame.width > 2, frame.height > 2 {
                let clipped = clip.map { frame.intersection($0) } ?? frame
                visible = screens.map { clipped.intersection($0) }.filter { !$0.isNull && $0.width > 2 && $0.height > 2 }.max { $0.width * $0.height < $1.width * $1.height }
            }
            var actions: [String] = []
            func readActions() {
                var result: CFArray?; AXUIElementCopyActionNames(element, &result)
                actions = result as? [String] ?? []
            }
            if missionRoot != nil || ["AXMenuItem", "AXMenuBarItem"].contains(role) || exhaustive && !roles.contains(role) && visible != nil { readActions() }
            // Accessibility press actions on text and structural groups often just
            // forward to a parent link. Label the semantic control once instead.
            let fallback = exhaustive && !["AXStaticText", "AXToolbar", "AXWebArea", "AXScrollArea"].contains(role) && children.isEmpty && actions.contains(kAXPressAction)
            if !enabled, let frame, visible != nil, roles.contains(role) { disabledControls.append(ControlGeometry(element: element, frame: frame, enabled: false)) }
            if enabled, let rect = visible, roles.contains(role) || fallback {
                if !(rect.width > 700 && rect.height > 200 && ["AXRow", "AXCell"].contains(role)) {
                    var target = Target(element: element, frame: rect, role: role, title: String(node.title.prefix(200)), actions: actions, missionControl: missionRoot != nil)
                    target.sourceFrame = frame; target.url = node.url; targets.append(target)
                }
            }
            let pageWrapper = role == "AXGroup" && clip != nil && visible != nil && visible!.width > clip!.width * 0.9 && visible!.height > clip!.height * 0.9
            var overflow = false
            if scrolling, role == "AXGroup", let frame, visible != nil, !pageWrapper, !children.isEmpty {
                let extends = children.contains { child in
                    guard let rect = snapshot(child).frame else { return false }
                    return rect.maxY > frame.maxY + 8 || rect.maxX > frame.maxX + 8 || rect.minY < frame.minY - 8 || rect.minX < frame.minX - 8 || rect.height <= 2 && abs(rect.maxY - frame.maxY) < 4 || rect.width <= 2 && abs(rect.maxX - frame.maxX) < 4
                }
                if extends { if actions.isEmpty { readActions() }; overflow = actions.contains("AXScrollToVisible") }
            }
            let scrollable = node.value(9) != nil || node.value(10) != nil || overflow
            if let rect = visible, ["AXScrollArea", "AXWebArea"].contains(role) || scrollable {
                var area = Target(element: element, frame: rect, role: role, title: node.title, actions: [])
                area.sourceFrame = frame; areas.append(area)
            }
            var childClip = clip
            if ["AXWindow", "AXScrollArea", "AXWebArea"].contains(role) || scrollable, let frame {
                childClip = clip.map { $0.intersection(frame) } ?? frame
            }
            // Gecko exposes its browser toolbar/sidebar as a separate native
            // accessibility root. Enumerate its controls in-process as well as
            // the page, preserving browser UI without visiting decorative text.
            let nativeRoot = !web && !queryLeaf && (role == "AXToolbar" || role == "AXGroup" && depth <= 3 && (frame?.width ?? 0) > 0 && (frame?.width ?? 1000) < 600 && (frame?.height ?? 0) > 100)
            if nativeRoot, !exhaustive, !scrolling, let controls = semanticControls(element), !controls.isEmpty {
                controlQueries.append(ControlQuery(root: element, elements: Set(controls)))
                prefetch(controls)
                for child in controls.reversed() { stack.append((child, childClip, depth + 1, false, true)) }
                continue
            }
            if role == "AXWebArea", !exhaustive, !scrolling, let controls = controlsInDocument, !controls.isEmpty {
                prefetch(controls)
                for child in controls.reversed() { stack.append((child, childClip, depth + 1, true, true)) }
                continue
            }
            prefetch(children)
            for child in children.reversed() { stack.append((child, childClip, depth + 1, web, false)) }
        }
        let walkTime = ProcessInfo.processInfo.systemUptime
        var geometry = Set<String>()
        var links: [String: [CGRect]] = [:]
        let windows = visibleWindows()
        let controls = targets.filter { !["AXRow", "AXCell"].contains($0.role) }
        func filterVisibleTargets() -> [Target] {
        targets.filter { target in
            if ["AXRow", "AXCell"].contains(target.role), controls.contains(where: { target.frame.contains($0.frame) }) { return false }
            let f = target.frame
            let key = "\(Int(f.minX.rounded()))/\(Int(f.minY.rounded()))/\(Int(f.width.rounded()))/\(Int(f.height.rounded()))"
            guard geometry.insert(key).inserted else { return false }
            if !target.url.isEmpty {
                let adjacent = links[target.url, default: []].contains { r in
                    let horizontalOverlap = min(r.maxX, f.maxX) - max(r.minX, f.minX)
                    return r.intersects(f) || horizontalOverlap > min(r.width, f.width) * 0.5 && max(r.minY, f.minY) - min(r.maxY, f.maxY) < 100
                }
                if adjacent { return false }
                links[target.url, default: []].append(f)
            }
            return visiblePoint(target, windows: windows) != nil
        }.sorted { a, b in Int(a.frame.minY / 5) != Int(b.frame.minY / 5) ? a.frame.minY < b.frame.minY : a.frame.minX < b.frame.minX }
        }
        // Hit testing may land on KeyRow's own SwiftUI window even when the
        // scanned target belongs to another app. Run the complete filter on main.
        targets = Thread.isMainThread ? filterVisibleTargets() : DispatchQueue.main.sync(execute: filterVisibleTargets)
        var kept: [Target] = []
        for area in areas.sorted(by: { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }) {
            if !kept.contains(where: { abs($0.frame.minX - area.frame.minX) < 5 && abs($0.frame.minY - area.frame.minY) < 5 && abs($0.frame.width - area.frame.width) < 10 && abs($0.frame.height - area.frame.height) < 10 }) { kept.append(area) }
        }
        let end = ProcessInfo.processInfo.systemUptime
        return ScanResult(targets: targets, areas: kept, visited: visited.count, truncated: !stack.isEmpty, milliseconds: Int(Date().timeIntervalSince(start) * 1000), phases: ["walk_ms": (walkTime - rootsTime) * 1000, "filter_ms": (end - walkTime) * 1000, "snapshots": Double(cache.count)], observationRoots: observationRoots, controlQueries: controlQueries, disabledControls: disabledControls, sourceWindow: sourceWindow)
    }
}
