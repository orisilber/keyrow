import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var prefs = Preferences.shared
    @ObservedObject var engine: Engine
    @State private var page = "General"
    @State private var launchOnLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError = ""
    let pages = [("General", "gearshape"), ("Clicking", "cursorarrow.click.2"), ("Scrolling", "scroll"), ("Ignored Apps", "app.badge"), ("About", "info.circle")]
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(pages, id: \.0) { item in
                    Button { page = item.0 } label: {
                        HStack(spacing: 10) {
                            if item.0 == "Clicking" || item.0 == "Scrolling" {
                                Image(systemName: item.1).font(.system(size: 12)).foregroundStyle(.white).frame(width: 20, height: 20).background(Color.blue).clipShape(RoundedRectangle(cornerRadius: 4))
                            } else { Image(systemName: item.1).frame(width: 20) }
                            Text(item.0).fontWeight(.medium); Spacer()
                        }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(page == item.0 ? Color.primary.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("KeyRow").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(10)
                    .background(Color.primary.opacity(0.04)).clipShape(Capsule())
            }.padding(12).padding(.top, 40).frame(width: 205)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !engine.trusted || !engine.listening { permission }
                    switch page {
                    case "Clicking": clicking
                    case "Scrolling": scrolling
                    case "Ignored Apps": ignored
                    case "About": about
                    default: general
                    }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.top, 8).frame(width: 540)
        }.frame(width: 750, height: 640).background(colorScheme == .dark ? Color(white: 0.27) : Color(nsColor: .windowBackgroundColor)).ignoresSafeArea()
    }
    func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0, content: content).padding(.horizontal, 14).padding(.vertical, 4)
                .background(Color.primary.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
    func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title); Spacer(minLength: 18); content() }.padding(.vertical, 11)
    }
    func toggle(_ title: String, _ binding: Binding<Bool>) -> some View {
        row(title) { Toggle(title, isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small) }
    }
    var permission: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(engine.trusted ? "Restart KeyRow to connect keyboard input" : "Allow Accessibility to navigate your Mac", systemImage: "hand.raised.fill").fontWeight(.semibold)
            Text("KeyRow reads visible controls and sends clicks and scrolls locally. Enable KeyRow in System Settings → Privacy & Security → Accessibility.").font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Open Accessibility Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
                Button("Check Again") { engine.refreshPermission() }
            }
        }.padding(14).background(Color.blue.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    var general: some View {
        VStack(spacing: 20) {
            card("Appearance") {
                row("Theme") {
                    ForEach(["Original", "Dark", "Light"], id: \.self) { theme in
                        Button { prefs.theme = theme } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    LinearGradient(colors: theme == "Original" ? [.black, .green.opacity(0.6), .black] : theme == "Dark" ? [.green, .blue, .black] : [.yellow, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    Text("KR").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(theme == "Dark" ? .white : .black)
                                        .padding(.horizontal, 4).padding(.vertical, 1).background(theme == "Original" ? Color.yellow : theme == "Dark" ? Color.black : Color.white).clipShape(RoundedRectangle(cornerRadius: 2))
                                }.frame(width: 56, height: 48).clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(prefs.theme == theme ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: prefs.theme == theme ? 3 : 1))
                                Text(theme).font(.caption).foregroundStyle(.secondary)
                            }.frame(width: 62)
                        }.buttonStyle(.plain)
                    }
                }
                Divider()
                row("Label size") { Text("A").font(.caption); Slider(value: $prefs.labelSize, in: 6...14, step: 1).frame(width: 200); Text("A").font(.title3) }
            }
            card("Application") {
                toggle("Launch on login", Binding(get: { launchOnLogin }, set: { value in
                    do { if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; launchOnLogin = value; loginError = "" }
                    catch { loginError = error.localizedDescription }
                }))
                if !loginError.isEmpty { Text(loginError).font(.caption).foregroundStyle(.red) }
                Divider()
                toggle("Pause navigation", $engine.paused)
            }
            card("Keyboard") {
                row("Input source") { Text("Current macOS layout").foregroundStyle(.secondary) }
                Divider(); toggle("Hyperkey enabled", $prefs.hyper)
                Text("Hyper maps Caps Lock to ⌃⌥⇧⌘ while KeyRow runs. Existing keyboard mappings are preserved and restored on quit. Leave this off when using another Caps Lock remapper.").font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
                if !engine.hyperError.isEmpty { Text(engine.hyperError).font(.caption).foregroundStyle(.orange).padding(.bottom, 10) }
            }
            card("Sound Effects") {
                toggle("Enable sound effects", $prefs.sounds)
                Divider()
                row("Volume") { Image(systemName: "speaker.fill"); Slider(value: $prefs.volume, in: 0...1).frame(width: 200); Image(systemName: "speaker.wave.2.fill") }
            }
        }
    }
    var clicking: some View {
        VStack(spacing: 20) {
            card("Clicking") {
                row("Shortcut") { ShortcutRecorder(shortcut: $prefs.clickShortcut, engine: engine).frame(width: 190, height: 26) }
                Divider(); toggle("Automatic click", $prefs.automatic)
                Divider(); toggle("Chain clicks", $prefs.chain)
                Text("Chain mode shows fresh labels after each click. Clicking an input field ends the chain so you can type.").font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
                Divider(); toggle("Mission Control auto-activate", $prefs.missionControl)
            }
            card("Labels") {
                row("Label characters") { TextField("ARSTNEIO", text: $prefs.characters).textFieldStyle(.roundedBorder).frame(width: 200) }
                Divider()
                row("Browser labels") { Picker("Browser labels", selection: $prefs.exhaustive) { Text("Fast").tag(false); Text("Exhaustive").tag(true) }.labelsHidden().pickerStyle(.segmented).frame(width: 200) }
            }
            card("Controls") {
                row("Focus next / previous") { Text("Tab / ⇧Tab").foregroundStyle(.secondary) }; Divider()
                row("Left / right / command click") { Text("↵ / ⇧↵ / ⌘↵").foregroundStyle(.secondary) }; Divider()
                row("Double click") { Text("↵ twice").foregroundStyle(.secondary) }; Divider()
                row("Inspect focused control") { Text("?").foregroundStyle(.secondary) }; Divider()
                row("Exit") { Text("Esc").foregroundStyle(.secondary) }
            }
        }
    }
    var scrolling: some View {
        VStack(spacing: 20) {
            card("Scrolling") {
                row("Shortcut") { ShortcutRecorder(shortcut: $prefs.scrollShortcut, engine: engine).frame(width: 190, height: 26) }; Divider()
                row("Arrow keys") { Picker("Arrow keys", selection: $prefs.arrowScroll) { Text("Select").tag(false); Text("Scroll").tag(true) }.labelsHidden().pickerStyle(.segmented).frame(width: 200) }; Divider()
                toggle("Show scroll area numbers", $prefs.numbers); Divider()
                row("Scroll keys") { TextField("HJKL", text: $prefs.scrollKeys).textFieldStyle(.roundedBorder).frame(width: 200) }; Divider()
                toggle("Scroll commands", $prefs.commands); Divider()
                toggle("Auto deactivation", $prefs.autoDeactivate)
            }
            card("Speed") {
                row("Scroll speed") { Image(systemName: "tortoise.fill"); Slider(value: $prefs.speed, in: 0.2...5).frame(width: 200); Image(systemName: "hare.fill") }; Divider()
                row("Dash speed") { Image(systemName: "tortoise.fill"); Slider(value: $prefs.dashSpeed, in: 0.2...8).frame(width: 200); Image(systemName: "hare.fill") }
            }
            Text("Hold H/J/K/L to scroll left/down/up/right. Hold Shift to dash. Use Tab or 0–9 to select an area. D/U scroll half a page; gg goes to the top and ⇧G to the bottom. Esc exits.").font(.callout).foregroundStyle(.secondary)
        }
    }
    var ignored: some View {
        card("Ignored Apps") {
            Text("Add an app name or bundle identifier on each line. Navigation shortcuts pass through in these apps.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 10)
            TextEditor(text: $prefs.ignored).font(.system(.body, design: .monospaced)).frame(height: 270)
            HStack { Spacer(); Menu("Add running app") {
                ForEach(NSWorkspace.shared.runningApplications.filter({ $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }).sorted(by: { $0.localizedName ?? "" < $1.localizedName ?? "" }), id: \.processIdentifier) { app in
                    Button(app.localizedName ?? "App") { if let id = app.bundleIdentifier { prefs.ignored += (prefs.ignored.isEmpty ? "" : "\n") + id } }
                }
            } }.padding(.vertical, 10)
        }
    }
    var about: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("KeyRow").font(.largeTitle.bold())
            Text("Keyboard navigation for macOS").font(.title3).foregroundStyle(.secondary)
            Text("A local recreation of Homerow's labels-only clicking and scrolling workflow. Search is omitted.")
            Label(engine.trusted && engine.listening ? "Accessibility connected" : "Accessibility permission needed", systemImage: engine.trusted && engine.listening ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(engine.trusted && engine.listening ? .green : .orange)
            Text("Version 0.1.0").foregroundStyle(.secondary)
            Text("No accounts, network requests, or usage tracking. This is independent software and is not affiliated with Homerow.").font(.callout).foregroundStyle(.secondary)
            Button("Open practice window") { PracticeWindow.shared.show() }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut
    let engine: Engine
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(); button.engine = engine
        button.onRecord = { shortcut = $0 }; button.title = shortcut.display
        return button
    }
    func updateNSView(_ nsView: RecorderButton, context: Context) { if !nsView.isRecording { nsView.title = shortcut.display }; nsView.onRecord = { shortcut = $0 } }
}
final class RecorderButton: NSButton {
    weak var engine: Engine?
    var onRecord: ((Shortcut) -> Void)?
    var isRecording = false
    private var monitor: Any?
    private var lastModifiers: NSEvent.ModifierFlags = []
    override init(frame: NSRect) { super.init(frame: frame); bezelStyle = .rounded; target = self; action = #selector(record); setAccessibilityLabel("Record Shortcut") }
    required init?(coder: NSCoder) { fatalError() }
    @objc func record() {
        if isRecording { finish(); return }
        isRecording = true; engine?.recording = true; engine?.dismiss(); title = "Type shortcut…"
        lastModifiers = []
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection([.command, .shift, .control, .option])
            if event.type == .flagsChanged {
                if mods.isEmpty, !self.lastModifiers.isEmpty {
                    self.commit(key: UInt16.max, flags: self.lastModifiers, text: "")
                } else {
                    if mods.rawValue.nonzeroBitCount >= self.lastModifiers.rawValue.nonzeroBitCount { self.lastModifiers = mods }
                    self.title = self.display(self.lastModifiers)
                }
                return event
            }
            if event.keyCode == 53 { self.finish(); return nil }
            guard !mods.isEmpty else { self.title = "Include a modifier"; return nil }
            let text = event.keyCode == 49 ? "Space" : event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            self.commit(key: event.keyCode, flags: mods, text: text); return nil
        }
    }
    private func display(_ flags: NSEvent.ModifierFlags) -> String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
    }
    private func commit(key: UInt16, flags: NSEvent.ModifierFlags, text: String) {
        let cg = CGEventFlags(rawValue: UInt64(flags.rawValue))
        onRecord?(Shortcut(keyCode: key, modifiers: cg.rawValue, display: display(flags) + text)); finish()
    }
    private func finish() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; isRecording = false; engine?.recording = false }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}
