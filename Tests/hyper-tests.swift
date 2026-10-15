import Foundation

@main struct HyperTests {
    static func main() throws {
        precondition(HyperController.destination == 0x70000006d && HyperController.trigger == 79, "HID usage and macOS event key code must both identify F18")
        let src = HyperController.src, dst = HyperController.dst
        let cap = [src: HyperController.source, dst: HyperController.destination]
        let unrelated: [String: UInt64] = [src: 0x70000003a, dst: 0x70000003b]
        var maps: [UInt64: [[String: UInt64]]] = [1: [cap], 2: [unrelated], 3: []]
        let baseline = maps
        let controller = HyperController(keyboards: {
            maps.keys.sorted().map { id in
                HyperController.Keyboard(id: id, read: { maps[id]! }, write: { maps[id] = $0 })
            }
        })
        try controller.update(true)
        precondition(controller.enabled && maps[1] == [cap] && maps[2] == [unrelated, cap] && maps[3] == [cap])
        maps[5] = [[src: HyperController.source, dst: HyperController.legacyDestination]]
        maps[4] = [unrelated]
        try controller.update(true)
        precondition(maps[5] == [cap], "Legacy F14 mapping was not migrated")
        precondition(maps[4] == [unrelated, cap], "New keyboard was not mapped")
        maps[2]!.insert([src: 0x70000003c, dst: 0x70000003d], at: 0)
        try controller.update(false)
        precondition(maps[1] == baseline[1], "Pre-existing mapping was removed")
        precondition(maps[2]!.count == 2 && maps[2]!.contains(unrelated), "Unrelated edits were overwritten")
        precondition(maps[3] == [] && maps[4] == [unrelated], "Owned mapping was not restored")
        maps[3] = [[src: HyperController.source, dst: 0x700000029]]
        let conflicting = maps
        do { try controller.update(true); fatalError("Conflicting Caps Lock mapping was overwritten") }
        catch { precondition(maps == conflicting) }
        var first: [[String: UInt64]] = []
        let broken = HyperController(keyboards: {
            [HyperController.Keyboard(id: 10, read: { first }, write: { first = $0 }),
             HyperController.Keyboard(id: 11, read: { [] }, write: { _ in throw NSError(domain: "test", code: 1) })]
        })
        do { try broken.update(true); fatalError("Expected the second keyboard's write failure") }
        catch { precondition(first.isEmpty && !broken.enabled, "Partial mapping change was not rolled back") }
        print("PASS: independent mappings, hot-plug, restore, unrelated edits, and conflict preservation")
    }
}
