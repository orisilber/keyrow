// A real, nonactivating floating window for the visibility regression check.
import AppKit

let args = CommandLine.arguments.dropFirst().compactMap(Double.init)
guard args.count == 4 else { exit(2) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let screenHeight = NSScreen.screens.first?.frame.maxY ?? 0
let frame = CGRect(x: args[0], y: screenHeight - args[1] - args[3], width: args[2], height: args[3])
let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.level = .floating
panel.isOpaque = true
panel.backgroundColor = .windowBackgroundColor
panel.hidesOnDeactivate = false
let button = NSButton(title: "Covered control fixture", target: nil, action: nil)
button.frame = CGRect(origin: .zero, size: frame.size)
panel.contentView = button
panel.orderFrontRegardless()
print("ready")
fflush(stdout)
app.run()
