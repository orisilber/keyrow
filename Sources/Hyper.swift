import AppKit

final class HyperController {
    static let trigger: UInt16 = 79 // F18, the HID mapping's clean press/release trigger.
    static let flags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    static let source: UInt64 = 0x700000039
    static let destination: UInt64 = 0x700000069
    private(set) var enabled = false
    private var ownsMapping = false
    private let src = "HIDKeyboardModifierMappingSrc"
    private let dst = "HIDKeyboardModifierMappingDst"
    private func hidutil(_ arguments: [String]) throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil"); process.arguments = ["property"] + arguments
        let output = Pipe(); let errors = Pipe(); process.standardOutput = output; process.standardError = errors
        process.arguments = ["property", "--matching", "keyboard"] + arguments
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        if process.terminationStatus != 0 { throw NSError(domain: "KeyRow", code: 1, userInfo: [NSLocalizedDescriptionKey: "macOS could not update the Caps Lock mapping."]) }
        return data
    }
    private func read() throws -> [[String: UInt64]] {
        let data = try hidutil(["--get", "UserKeyMapping"])
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.hasPrefix("RegistryID") {
            let regex = try NSRegularExpression(pattern: "(?m)^[0-9a-fA-F]+[ \\t]+UserKeyMapping[ \\t]+")
            let ns = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { throw NSError(domain: "KeyRow", code: 2, userInfo: [NSLocalizedDescriptionKey: "No keyboard mapping could be read."]) }
            let values = try matches.enumerated().map { index, match in
                let start = NSMaxRange(match.range)
                let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
                return try decode(ns.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            guard values.dropFirst().allSatisfy({ $0 == values[0] }) else { throw NSError(domain: "KeyRow", code: 5, userInfo: [NSLocalizedDescriptionKey: "Your keyboards have different mappings. KeyRow has preserved them. Use your existing Hyper remapper."]) }
            return values[0]
        }
        return try decode(text)
    }
    private func decode(_ text: String) throws -> [[String: UInt64]] {
        if text.isEmpty || text == "(null)" || text == "null" { return [] }
        let data = Data(text.utf8)
        guard let values = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]] else {
            throw NSError(domain: "KeyRow", code: 2, userInfo: [NSLocalizedDescriptionKey: "The existing keyboard mapping could not be read. It has been preserved."])
        }
        return try values.map { item in
            func number(_ key: String) -> UInt64? {
                if let value = item[key] as? NSNumber { return value.uint64Value }
                if let value = item[key] as? String { return value.hasPrefix("0x") ? UInt64(value.dropFirst(2), radix: 16) : UInt64(value) }
                return nil
            }
            guard let s = number(src), let d = number(dst) else { throw NSError(domain: "KeyRow", code: 3, userInfo: [NSLocalizedDescriptionKey: "The existing keyboard mapping could not be read. It has been preserved."]) }
            return [src:s,dst:d]
        }
    }
    private func write(_ mappings: [[String: UInt64]]) throws {
        let data = try JSONSerialization.data(withJSONObject: ["UserKeyMapping": mappings])
        _ = try hidutil(["--set", String(data: data, encoding: .utf8)!])
    }
    func update(_ requested: Bool) throws {
        if requested == enabled { return }
        var mappings = try read()
        if requested {
            if let existing = mappings.first(where: { $0[src] == Self.source }) {
                guard existing[dst] == Self.destination else {
                    throw NSError(domain: "KeyRow", code: 4, userInfo: [NSLocalizedDescriptionKey: "Caps Lock already has a different mapping. KeyRow has preserved it. Use your existing Hyper remapper or remove that mapping first."])
                }
            } else {
                mappings.append([src:Self.source,dst:Self.destination]); try write(mappings); ownsMapping = true
            }
            enabled = true
        } else {
            if ownsMapping {
                mappings.removeAll { $0[src] == Self.source && $0[dst] == Self.destination }
                try write(mappings); ownsMapping = false
            }
            enabled = false
        }
    }
}
