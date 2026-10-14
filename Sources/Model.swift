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
    for (x, y) in [(0.5, 0.5), (0.15, 0.15), (0.85, 0.15), (0.15, 0.85), (0.85, 0.85), (0.05, 0.5), (0.95, 0.5), (0.5, 0.05), (0.5, 0.95), (0.01, 0.01), (0.99, 0.99)] {
        let point = CGPoint(x: target.frame.minX + target.frame.width * x, y: target.frame.minY + target.frame.height * y)
        guard !avoiding.contains(where: { $0.contains(point) }) else { continue }
        if target.role == "AXMenuBarItem" || windows.first(where: { $0.frame.contains(point) })?.pid == target.ownerPID || windows.first(where: { $0.frame.contains(point) }) == nil { return point }
    }
    return nil
}
struct ScanResult {
    var targets: [Target]
    var areas: [Target]
    var visited: Int
    var truncated: Bool
    var milliseconds: Int
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

final class AccessibilityScanner {
    func scan(pid: pid_t, screens: [CGRect], exhaustive: Bool, mission: Bool = false) -> ScanResult {
        let start = Date(); let deadline = start.addingTimeInterval(exhaustive ? 6 : 3)
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        // Chromium and Electron expose their page tree only while an accessibility client is present.
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        var targets: [Target] = []; var areas: [Target] = []; var visited = Set<AXUIElement>()
        var roots: [(AXUIElement, CGRect?)] = []
        if let window = axElement(application, kAXFocusedWindowAttribute) ?? axElement(application, kAXMainWindowAttribute) {
            roots.append((window, axFrame(window)))
        } else {
            for window in axValue(application, kAXWindowsAttribute) as? [AXUIElement] ?? [] { roots.append((window, axFrame(window))) }
        }
        if let menu = axElement(application, kAXMenuBarAttribute) { roots.append((menu, nil)) }
        // Open menu/popover roots are sometimes siblings of the focused window.
        for child in axValue(application, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            let role = axValue(child, kAXRoleAttribute) as? String ?? ""
            if role == "AXMenu" || role == "AXPopover" { roots.append((child, nil)) }
        }
        let missionRoot = missionControlRoot()
        if let missionRoot {
            roots = [(missionRoot, nil)]
        } else {
            for bundle in ["com.apple.systemuiserver", "com.apple.controlcenter"] {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
                    let element = AXUIElementCreateApplication(app.processIdentifier)
                    AXUIElementSetMessagingTimeout(element, 0.1)
                    if let menu = axElement(element, kAXMenuBarAttribute) { roots.append((menu, nil)) }
                }
            }
        }
        let roles: Set<String> = ["AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXMenuItem", "AXMenuBarItem", "AXTextField", "AXTextArea", "AXComboBox", "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXTab", "AXRow", "AXCell", "AXImage"]
        var stack = roots.reversed().map { ($0.0, $0.1, 0) }
        let maxNodes = exhaustive ? 40000 : 16000
        while let (element, clip, depth) = stack.popLast(), visited.count < maxNodes, Date() < deadline {
            guard depth < 90, visited.insert(element).inserted else { continue }
            let role = axValue(element, kAXRoleAttribute) as? String ?? ""
            if axValue(element, "AXHidden") as? Bool == true { continue }
            let enabled = axValue(element, kAXEnabledAttribute) as? Bool ?? true
            let frame = axFrame(element)
            var visible: CGRect?
            if let frame, frame.width > 2, frame.height > 2 {
                let clipped = clip.map { frame.intersection($0) } ?? frame
                visible = screens.map { clipped.intersection($0) }.filter { !$0.isNull && $0.width > 2 && $0.height > 2 }.max { $0.width * $0.height < $1.width * $1.height }
            }
            var actionsCF: CFArray?
            if enabled && visible != nil { AXUIElementCopyActionNames(element, &actionsCF) }
            let actions = actionsCF as? [String] ?? []
            let visibleChildren = axValue(element, kAXVisibleChildrenAttribute) as? [AXUIElement]
            let children = (visibleChildren?.isEmpty == false ? visibleChildren : nil) ?? axValue(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            let actionable = actions.contains(kAXPressAction) || actions.contains("AXOpen")
            if enabled, let rect = visible, (roles.contains(role) && role != "AXImage" || actionable) {
                let attributes = [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue", "AXHelp"] + (actions.contains("AXOpen") ? [kAXValueAttribute] : [])
                let title = attributes.compactMap { axValue(element, $0) as? String }.first { !$0.isEmpty } ?? role.replacingOccurrences(of: "AX", with: "")
                // A giant row/cell/container can hide its actual controls. Keep leaf controls instead.
                if !(rect.width > 700 && rect.height > 200 && ["AXRow", "AXCell"].contains(role)) {
                    targets.append(Target(element: element, frame: rect, role: role, title: String(title.prefix(200)), actions: actions, missionControl: missionRoot != nil))
                }
            }
            // WebKit exposes CSS overflow containers as groups, with children extending beyond
            // the group's viewport. AXScrollToVisible alone is not evidence of a scroll container.
            let pageWrapper = role == "AXGroup" && clip != nil && visible != nil && visible!.width > clip!.width * 0.9 && visible!.height > clip!.height * 0.9
            let overflow = role == "AXGroup" && frame != nil && !pageWrapper && actions.contains("AXScrollToVisible") && children.contains { child in
                guard let rect = axFrame(child), let frame, rect.width > 0, rect.height > 0 else { return false }
                let clippedVertical = rect.height <= 2 && (abs(rect.maxY - frame.maxY) < 4 || abs(rect.minY - frame.minY) < 4)
                let clippedHorizontal = rect.width <= 2 && (abs(rect.maxX - frame.maxX) < 4 || abs(rect.minX - frame.minX) < 4)
                return clippedVertical || clippedHorizontal || rect.maxY > frame.maxY + 8 || rect.maxX > frame.maxX + 8 || rect.minY < frame.minY - 8 || rect.minX < frame.minX - 8
            }
            let scrollable = actions.contains(where: { $0.hasPrefix("AXScroll") && $0 != "AXScrollToVisible" }) || axElement(element, "AXVerticalScrollBar") != nil || axElement(element, "AXHorizontalScrollBar") != nil || overflow
            if let rect = visible, ["AXScrollArea", "AXWebArea"].contains(role) || scrollable {
                let title = [kAXTitleAttribute, kAXDescriptionAttribute].compactMap { axValue(element, $0) as? String }.first { !$0.isEmpty } ?? "Scroll area"
                areas.append(Target(element: element, frame: rect, role: role, title: title, actions: []))
            }
            var childClip = clip
            if ["AXWindow", "AXScrollArea", "AXWebArea"].contains(role) || scrollable, let frame {
                childClip = clip.map { $0.intersection(frame) } ?? frame
            }
            // VisibleChildren avoids walking thousands of offscreen Finder/table rows.
            for child in children.reversed() { stack.append((child, childClip, depth + 1)) }
        }
        var geometry = Set<String>()
        let windows = visibleWindows()
        // Gecko can expose an actionable list and its link with identical bounds.
        // Preserve the actual control's name/action when collapsing that geometry.
        func priority(_ target: Target) -> Int {
            if roles.contains(target.role) && !["AXRow", "AXCell", "AXImage"].contains(target.role) { return 0 }
            return ["AXRow", "AXCell", "AXImage", "AXStaticText"].contains(target.role) ? 1 : 2
        }
        targets = targets.enumerated().sorted { a, b in
            priority(a.element) == priority(b.element) ? a.offset < b.offset : priority(a.element) < priority(b.element)
        }.map(\.element).filter { target in
            let f = target.frame
            let key = "\(Int(f.minX.rounded()))/\(Int(f.minY.rounded()))/\(Int(f.width.rounded()))/\(Int(f.height.rounded()))"
            return visiblePoint(target, windows: windows) != nil && geometry.insert(key).inserted
        }.sorted { a, b in Int(a.frame.minY / 5) != Int(b.frame.minY / 5) ? a.frame.minY < b.frame.minY : a.frame.minX < b.frame.minX }
        // WebArea and its enclosing ScrollArea often represent the same scrolling surface.
        var kept: [Target] = []
        for area in areas.sorted(by: { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }) {
            if !kept.contains(where: { abs($0.frame.minX - area.frame.minX) < 5 && abs($0.frame.minY - area.frame.minY) < 5 && abs($0.frame.width - area.frame.width) < 10 && abs($0.frame.height - area.frame.height) < 10 }) { kept.append(area) }
        }
        return ScanResult(targets: targets, areas: kept, visited: visited.count, truncated: !stack.isEmpty, milliseconds: Int(Date().timeIntervalSince(start) * 1000))
    }
}
