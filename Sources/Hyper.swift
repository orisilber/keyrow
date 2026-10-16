import AppKit
import IOKit.hidsystem
import IOKit.hid
import Carbon

final class HyperController {
    static let trigger = UInt16(kVK_F18) // F18 has distinct press and release events.
    static let flags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    static let source: UInt64 = 0x700000000 | UInt64(kHIDUsage_KeyboardCapsLock)
    static let destination: UInt64 = 0x700000000 | UInt64(kHIDUsage_KeyboardF18)
    static let legacyDestination: UInt64 = 0x700000069
    static let src = "HIDKeyboardModifierMappingSrc"
    static let dst = "HIDKeyboardModifierMappingDst"
    struct Keyboard {
        let id: UInt64
        let read: () throws -> [[String: UInt64]]
        let write: ([[String: UInt64]]) throws -> Void
    }
    private(set) var enabled = false
    private var owned = Set<UInt64>()
    private let keyboards: () -> [Keyboard]
    private let persistOwnership: Bool
    init(keyboards: (() -> [Keyboard])? = nil) {
        self.keyboards = keyboards ?? Self.systemKeyboards
        persistOwnership = keyboards == nil
        if persistOwnership { owned = Set((UserDefaults.standard.stringArray(forKey: "hyperMappingOwners") ?? []).compactMap(UInt64.init)) }
    }
    private func saveOwnership() {
        if persistOwnership { UserDefaults.standard.set(owned.map(String.init), forKey: "hyperMappingOwners") }
    }
    private static func error(_ message: String) -> NSError {
        NSError(domain: "KeyRow", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    // A simple HID client's service connections can outlive the devices they
    // describe after sleep or reconnection. Take a fresh snapshot on every poll.
    // Keep its client alive until every service has been released.
    private final class KeyboardSnapshot {
        let client: IOHIDEventSystemClient
        var services: [IOHIDServiceClient]
        init() {
            client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
            services = (IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? [])
                .filter { IOHIDServiceClientConformsTo($0, 1, 6) != 0 }
        }
        deinit { withExtendedLifetime(client) { services.removeAll() } }
        func keyboards() -> [Keyboard] {
            services.indices.compactMap { index in
                guard let id = IOHIDServiceClientGetRegistryID(services[index]) as? NSNumber else { return nil }
                return Keyboard(id: id.uint64Value, read: {
                    guard let raw = IOHIDServiceClientCopyProperty(self.services[index], "UserKeyMapping" as CFString) else { return [] }
                    guard let values = raw as? [[String: UInt64]] else { throw error("A keyboard mapping could not be read. It has been preserved.") }
                    return values
                }, write: { mappings in
                    guard IOHIDServiceClientSetProperty(self.services[index], "UserKeyMapping" as CFString, mappings as CFArray) else {
                        throw error("macOS could not update a keyboard's Caps Lock mapping.")
                    }
                })
            }
        }
    }
    static func systemKeyboards() -> [Keyboard] { KeyboardSnapshot().keyboards() }
    // Called periodically while enabled so newly connected and virtual keyboards
    // receive the mapping without replacing any other key mappings on that device.
    func update(_ requested: Bool) throws {
        if !requested && !enabled && owned.isEmpty { return }
        let devices = keyboards()
        let current = try devices.map { ($0, try $0.read()) }
        if requested {
            guard !devices.isEmpty else { throw Self.error("No keyboard is connected.") }
            for (_, mappings) in current {
                if mappings.contains(where: { $0[Self.src] == Self.source && $0[Self.dst] != Self.destination && $0[Self.dst] != Self.legacyDestination }) {
                    throw Self.error("A keyboard already maps Caps Lock to another key. That mapping has been preserved.")
                }
            }
            let wasEnabled = enabled
            do {
            for (device, var mappings) in current where !mappings.contains(where: { $0[Self.src] == Self.source && $0[Self.dst] == Self.destination }) {
                // Earlier KeyRow builds used the F14 HID usage by mistake.
                mappings.removeAll { $0[Self.src] == Self.source && $0[Self.dst] == Self.legacyDestination }
                mappings.append([Self.src: Self.source, Self.dst: Self.destination])
                try device.write(mappings)
                owned.insert(device.id); saveOwnership()
                guard try device.read().contains(where: { $0[Self.src] == Self.source && $0[Self.dst] == Self.destination }) else {
                    throw Self.error("A keyboard did not accept the Caps Lock mapping.")
                }
            }
            enabled = true
            } catch {
                if !wasEnabled {
                    // Roll back devices already changed if a later device fails.
                    for (device, _) in current where owned.contains(device.id) {
                        if var mappings = try? device.read() {
                            mappings.removeAll { $0[Self.src] == Self.source && $0[Self.dst] == Self.destination }
                            if (try? device.write(mappings)) != nil { owned.remove(device.id) }
                        }
                    }
                    saveOwnership()
                }
                throw error
            }
        } else {
            for (device, var mappings) in current where owned.contains(device.id) {
                mappings.removeAll { $0[Self.src] == Self.source && $0[Self.dst] == Self.destination }
                try device.write(mappings)
                owned.remove(device.id)
            }
            owned.removeAll(); saveOwnership()
            enabled = false
        }
    }
}
