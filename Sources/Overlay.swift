import AppKit

final class OverlayView: NSView {
    var targets: [Target] = []
    var prefix = ""
    var selected = 0
    var scrolling = false
    var message = ""
    var tutor = false
    var screenFrame = CGRect.zero
    override var isFlipped: Bool { true }
    func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY) }
    override func draw(_ dirtyRect: NSRect) {
        let prefs = Preferences.shared
        let font = NSFont.monospacedSystemFont(ofSize: prefs.labelSize, weight: .bold)
        let dark = prefs.theme == "Dark"
        let fill: NSColor = prefs.theme == "Original" ? NSColor(calibratedRed: 1, green: 0.95, blue: 0.38, alpha: 1) : dark ? NSColor(calibratedWhite: 0.13, alpha: 1) : NSColor(calibratedWhite: 0.98, alpha: 1)
        let foreground: NSColor = dark ? .white : .black
        var occupied: [CGRect] = []
        for (index, target) in targets.enumerated() where scrolling || target.label.hasPrefix(prefix) {
            let frame = local(target.frame)
            guard bounds.intersects(frame) else { continue }
            let focused = index == selected
            if focused || scrolling {
                let outline = NSBezierPath(roundedRect: frame.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
                (scrolling ? NSColor.systemBlue.withAlphaComponent(focused ? 0.9 : 0.35) : NSColor.systemGreen).setStroke()
                outline.lineWidth = focused ? 2.5 : 1; outline.stroke()
            }
            if scrolling && !prefs.numbers { continue }
            let text = target.label as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground]
            let size = text.size(withAttributes: attrs)
            var badge = CGRect(x: max(1, frame.minX), y: max(1, frame.minY), width: size.width + 8, height: size.height + 2)
            badge.origin.x = min(badge.origin.x, bounds.width - badge.width - 1)
            badge.origin.y = min(badge.origin.y, bounds.height - badge.height - 1)
            // Move a colliding label within its own element rather than covering another label.
            for _ in 0..<4 where occupied.contains(where: { $0.intersects(badge) }) {
                if badge.maxY + badge.height < frame.maxY { badge.origin.y += badge.height + 1 }
                else { badge.origin.x = min(frame.maxX - badge.width, badge.origin.x + badge.width + 2) }
            }
            occupied.append(badge)
            let shape = NSBezierPath(roundedRect: badge, xRadius: 2, yRadius: 2)
            let shadow = NSShadow(); shadow.shadowBlurRadius = 2; shadow.shadowOffset = NSSize(width: 0, height: 1); shadow.shadowColor = .black.withAlphaComponent(0.35)
            NSGraphicsContext.saveGraphicsState(); shadow.set(); fill.setFill(); shape.fill(); NSGraphicsContext.restoreGraphicsState()
            (focused ? (scrolling ? NSColor.systemBlue : NSColor.systemGreen) : NSColor.gray.withAlphaComponent(0.7)).setStroke()
            shape.lineWidth = 0.8; shape.stroke()
            text.draw(at: CGPoint(x: badge.minX + 4, y: badge.minY + 1), withAttributes: attrs)
        }
        let count = targets.filter { scrolling || $0.label.hasPrefix(prefix) }.count
        let status = message.isEmpty ? (scrolling ? "H J K L   ·   ⇧ dash   ·   Tab area   ·   Esc exit" : "\(prefix.isEmpty ? "Click" : prefix)   ·   \(count) targets   ·   Tab focus   ·   ↵ click   ·   Esc exit") : message
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
        let statusSize = (status as NSString).size(withAttributes: attrs)
        let box = CGRect(x: (bounds.width - statusSize.width - 28) / 2, y: 35, width: statusSize.width + 28, height: 30)
        NSColor(calibratedWhite: 0.12, alpha: 0.94).setFill(); NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        (status as NSString).draw(at: CGPoint(x: box.minX + 14, y: box.minY + 7), withAttributes: attrs)
        if tutor, targets.indices.contains(selected) {
            let target = targets[selected]
            let text = "\(target.label) · \(target.title) · \(target.role)" as NSString
            let s = text.size(withAttributes: attrs)
            let box = CGRect(x: max(8, min(local(target.frame).minX, bounds.width - s.width - 24)), y: min(bounds.height - 35, local(target.frame).maxY + 8), width: s.width + 20, height: 28)
            NSColor(calibratedWhite: 0.12, alpha: 0.96).setFill(); NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
            text.draw(at: CGPoint(x: box.minX + 10, y: box.minY + 6), withAttributes: attrs)
        }
    }
}

final class Overlay {
    private var panels: [(NSPanel, OverlayView)] = []
    var screenRects: [CGRect] {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map { CGRect(x: $0.frame.minX, y: height - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
    }
    func show(targets: [Target], prefix: String, selected: Int, scrolling: Bool, message: String = "", tutor: Bool = false) {
        if panels.count != NSScreen.screens.count { hide(); create() }
        if panels.isEmpty { create() }
        for (panel, view) in panels {
            view.targets = targets; view.prefix = prefix; view.selected = selected
            view.scrolling = scrolling; view.message = message; view.tutor = tutor
            view.needsDisplay = true
            panel.orderFrontRegardless()
        }
    }
    private func create() {
        let rects = screenRects
        for (index, screen) in NSScreen.screens.enumerated() {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
            let view = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.screenFrame = rects[index]; panel.contentView = view
            panels.append((panel, view))
        }
    }
    func hide() { for (panel, _) in panels { panel.orderOut(nil) }; panels.removeAll() }
    func savePreview(to url: URL) {
        guard let (_, view) = panels.first, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: url, options: .atomic) }
    }
}
