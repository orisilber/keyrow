import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = Engine()
    var statusItem: NSStatusItem!
    var settings: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let path = Bundle.main.object(forInfoDictionaryKey: "KeyRowVerificationOutput") as? String {
            engine.diagnosticsURL = URL(fileURLWithPath: path)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--diagnostics"), CommandLine.arguments.count > index + 1 {
            engine.diagnosticsURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyRow")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Click with keyboard", action: #selector(clickMode), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Scroll with keyboard", action: #selector(scrollMode), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Practice…", action: #selector(practice), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Pause / Resume", action: #selector(pause), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit KeyRow", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }; statusItem.menu = menu
        let appMenu = NSMenu(); let root = NSMenuItem(); root.submenu = menu; appMenu.addItem(root)
        let editRoot = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editRoot.submenu = edit; appMenu.addItem(editRoot); NSApp.mainMenu = appMenu
        engine.start()
        if !engine.trusted || CommandLine.arguments.contains("--settings") { showSettings() }
        if CommandLine.arguments.contains("--practice") { practice() }
    }
    @objc func clickMode() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.engine.activate(.clicking) } }
    @objc func scrollMode() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.engine.activate(.scrolling) } }
    @objc func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 750, height: 640), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "KeyRow Settings"; window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            let host = NSHostingView(rootView: SettingsView(engine: engine)); host.sizingOptions = []
            window.contentView = host; window.isReleasedWhenClosed = false
            window.setFrame(NSRect(x: 0, y: 0, width: 750, height: 640), display: false); window.center()
            settings = window
        }
        NSApp.activate(ignoringOtherApps: true); settings?.makeKeyAndOrderFront(nil)
    }
    @objc func practice() { PracticeWindow.shared.show() }
    @objc func pause() { engine.paused.toggle(); engine.dismiss() }
    @objc func quit() { engine.shutdown(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) { engine.shutdown() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
}

final class PracticeWindow: NSObject {
    static let shared = PracticeWindow()
    private var window: NSWindow?
    func show() {
        if window == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 720, height: 580), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "KeyRow Practice"; w.contentView = NSHostingView(rootView: PracticeView()); w.center(); w.isReleasedWhenClosed = false; window = w
        }
        NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
}
struct PracticeView: View {
    @State var clicks = 0
    @State var checked = false
    @State var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Keyboard practice").font(.title.bold())
            Text("Activate clicking, type a label, and watch the result. These controls only change this practice window.").foregroundStyle(.secondary)
            HStack { Button("Count click") { clicks += 1 }; Text("Clicks: \(clicks)").accessibilityIdentifier("click-count"); Toggle("Enable option", isOn: $checked) }
            TextField("Practice text", text: $text).textFieldStyle(.roundedBorder)
            HStack(spacing: 20) {
                ScrollView { VStack(alignment: .leading) { ForEach(0..<100, id: \.self) { i in Button("Left item \(i)") { text = "Left item \(i)" } } }.frame(maxWidth: .infinity, alignment: .leading) }.border(Color.gray.opacity(0.4))
                ScrollView { VStack(alignment: .leading) { ForEach(0..<100, id: \.self) { i in Button("Right item \(i)") { text = "Right item \(i)" } } }.frame(maxWidth: .infinity, alignment: .leading) }.border(Color.gray.opacity(0.4))
            }
            Text("⇧⌘Space: click · ⇧⌘J: scroll · Esc: exit").font(.caption).foregroundStyle(.secondary)
        }.padding(25).frame(minWidth: 550, minHeight: 450)
    }
}

func selfTest() {
    let alphabet = Array("ARSTNEIO")
    for count in [0, 1, 8, 9, 63, 64, 65, 500, 4000] {
        let labels = Labels.generate(count, alphabet: alphabet)
        precondition(labels.count == count && Set(labels).count == count, "Wrong label count")
        let set = Set(labels)
        for label in labels { for length in 1..<label.count { precondition(!set.contains(String(label.prefix(length))), "Label prefix collision") } }
    }
    precondition(Labels.generate(10, alphabet: ["A"]).isEmpty)
    let event = CGEvent(keyboardEventSource: nil, virtualKey: 49, keyDown: true)!
    event.flags = [.maskCommand, .maskShift]
    precondition(Shortcut.click.matches(event)); event.flags.insert(.maskControl); precondition(!Shortcut.click.matches(event))
    print("PASS: unique prefix-free labels for 0–4000 targets; shortcut modifier matching")
}

func verificationDriver(_ args: [String]) {
    guard AXIsProcessTrusted() else { print("Driver requires the approved KeyRow Accessibility permission"); exit(2) }
    func send(_ code: UInt16, flags: CGEventFlags, text: String? = nil, hold: Double = 0) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { exit(3) }
            event.flags = flags
            if let text { let chars = Array(text.utf16); chars.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: $0.baseAddress) } }
            event.post(tap: .cgSessionEventTap)
            Thread.sleep(forTimeInterval: down ? max(0.03, hold) : 0.03)
        }
    }
    guard let command = args.first else { exit(4) }
    switch command {
    case "hyper-chord":
        let source = CGEventSource(stateID: .combinedSessionState)
        func trigger(_ down: Bool) {
            let event = CGEvent(keyboardEventSource: source, virtualKey: HyperController.trigger, keyDown: down)!
            event.flags = []; event.post(tap: .cgSessionEventTap)
            Thread.sleep(forTimeInterval: 0.08)
        }
        trigger(true); send(80, flags: []); trigger(false); send(80, flags: [])
        print("Sent F19 during Hyper and after release")
    case "focus":
        guard args.count > 1, let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[1]).first(where: { $0.processIdentifier != getpid() }) else { print("App not running"); exit(5) }
        app.activate(options: [.activateIgnoringOtherApps])
        let until = Date().addingTimeInterval(3)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        print("Focused \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "none")")
    case "hotkey":
        let shortcut = args.count > 1 && args[1] == "scroll" ? Preferences.shared.scrollShortcut : Preferences.shared.clickShortcut
        send(shortcut.keyCode, flags: CGEventFlags(rawValue: shortcut.modifiers))
    case "text", "hint", "double-hint":
        guard args.count > 1 else { exit(4) }
        for character in args[1] { send(keyCodeForCharacter(String(character).lowercased(), fallback: 0), flags: [], text: String(character)) }
        if command == "double-hint" { send(36, flags: []) }
    case "stop":
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.keyrow.app") where app.processIdentifier != getpid() { app.terminate() }
        let until = Date().addingTimeInterval(3)
        while NSRunningApplication.runningApplications(withBundleIdentifier: "local.keyrow.app").contains(where: { $0.processIdentifier != getpid() }) && Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    case "inspect":
        guard args.count > 1, let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[1]).first(where: { $0.processIdentifier != getpid() }) else { exit(5) }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.15)
        var nodes: [[String: Any]] = []; var seen = Set<AXUIElement>()
        var stack = [axElement(element, kAXFocusedWindowAttribute) ?? element]
        while let current = stack.popLast(), seen.count < 10000 {
            guard seen.insert(current).inserted else { continue }
            let role = axValue(current, kAXRoleAttribute) as? String ?? ""
            var row: [String: Any] = ["role": role]
            var actionsCF: CFArray?; AXUIElementCopyActionNames(current, &actionsCF); row["actions"] = actionsCF as? [String] ?? []
            var namesCF: CFArray?; AXUIElementCopyAttributeNames(current, &namesCF); row["attributes"] = namesCF as? [String] ?? []
            for name in [kAXTitleAttribute, kAXDescriptionAttribute, kAXIdentifierAttribute, kAXFocusedAttribute, kAXSelectedAttribute, kAXValueAttribute, "AXPlaceholderValue", kAXURLAttribute] {
                if role == "AXSecureTextField" && name == kAXValueAttribute { continue }
                if let value = axValue(current, name) {
                    if let text = value as? String { row[name] = String(text.prefix(500)) }
                    else if let number = value as? NSNumber { row[name] = number }
                    else if CFGetTypeID(value) == CFURLGetTypeID() { row[name] = (value as! URL).absoluteString }
                }
            }
            if let frame = axFrame(current) { row["frame"] = [frame.minX, frame.minY, frame.width, frame.height] }
            nodes.append(row)
            stack.append(contentsOf: (axValue(current, kAXChildrenAttribute) as? [AXUIElement] ?? []).reversed())
        }
        let data = try! JSONSerialization.data(withJSONObject: nodes, options: [.sortedKeys]); print(String(data: data, encoding: .utf8)!)
    case "wheel":
        guard args.count >= 5, let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[1]).first, let x = Double(args[2]), let y = Double(args[3]), let amount = Int32(args[4]) else { exit(4) }
        let point = CGPoint(x: x, y: y)
        CGWarpMouseCursorPosition(point)
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)!
        move.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
        let event = CGEvent(scrollWheelEvent2Source: nil, units: args.contains("line") ? .line : .pixel, wheelCount: 2, wheel1: amount, wheel2: 0, wheel3: 0)!
        event.location = point
        if args.contains("phase") { event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 1) }
        if args.contains("pid") { event.postToPid(app.processIdentifier) } else { event.post(tap: .cghidEventTap) }
        Thread.sleep(forTimeInterval: 0.1)
        print("Wheel delivered")
    case "point":
        guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else { exit(4) }
        var element: AXUIElement?
        AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(x), Float(y), &element)
        var rows: [[String: Any]] = []
        for _ in 0..<8 {
            guard let current = element else { break }
            var row: [String: Any] = ["role": axValue(current, kAXRoleAttribute) as? String ?? "", "title": axValue(current, kAXTitleAttribute) as? String ?? "", "description": axValue(current, kAXDescriptionAttribute) as? String ?? ""]
            var process: pid_t = 0; AXUIElementGetPid(current, &process); row["pid"] = process
            if let rect = axFrame(current) { row["frame"] = [rect.minX,rect.minY,rect.width,rect.height] }
            rows.append(row); element = axElement(current, kAXParentAttribute)
        }
        let point = CGEvent(source: nil)?.location ?? .zero
        let data = try! JSONSerialization.data(withJSONObject: ["pointer": [point.x,point.y], "hit": rows], options: [.sortedKeys]); print(String(data: data, encoding: .utf8)!)
    case "window":
        guard args.count >= 6, let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[1]).first,
              let window = axElement(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute),
              let x = Double(args[2]), let y = Double(args[3]), let w = Double(args[4]), let h = Double(args[5]) else { exit(4) }
        var point = CGPoint(x: x, y: y); var size = CGSize(width: w, height: h)
        let p = AXValueCreate(.cgPoint, &point)!; let s = AXValueCreate(.cgSize, &size)!
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s)
        Thread.sleep(forTimeInterval: 0.1)
        print(String(describing: axFrame(window)))
    case "key":
        guard args.count > 1 else { exit(4) }
        var flags: CGEventFlags = []
        if args.contains("shift") { flags.insert(.maskShift) }; if args.contains("cmd") { flags.insert(.maskCommand) }
        if args.contains("ctrl") { flags.insert(.maskControl) }; if args.contains("alt") { flags.insert(.maskAlternate) }
        let special: [String: UInt16] = ["Return": 36, "Space": 49, "Escape": 53, "Tab": 48, "Up": 126, "Down": 125, "Left": 123, "Right": 124, "Backspace": 51, "F18": 79]
        let code = special[args[1]] ?? keyCodeForCharacter(args[1].lowercased(), fallback: 0, command: flags.contains(.maskCommand))
        let text = special[args[1]] == nil ? (flags.contains(.maskShift) ? args[1].uppercased() : args[1].lowercased()) : nil
        let hold = args.firstIndex(of: "hold").flatMap { args.count > $0 + 1 ? Double(args[$0 + 1]) : nil } ?? 0
        send(code, flags: flags, text: flags.contains(.maskCommand) ? nil : text, hold: hold)
    case "wait":
        guard args.count > 2 else { exit(4) }
        let until = Date().addingTimeInterval(8)
        while Date() < until {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: args[1])), let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any], state["mode"] as? String == args[2] { print("Reached \(args[2])"); return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        print("Timed out waiting for \(args[2])"); exit(6)
    default: exit(4)
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--driver") { verificationDriver(Array(CommandLine.arguments.dropFirst(index + 1))) }
else if CommandLine.arguments.contains("--self-test") { selfTest() }
else {
    let application = NSApplication.shared
    let delegate = AppDelegate(); application.delegate = delegate; application.run()
}
