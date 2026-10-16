import Foundation

@main struct HyperDeviceTests {
    static func main() throws {
        // This is a read-only native stress check. It must run on a Mac with a
        // connected keyboard; mappings are never changed by this executable.
        let initial = Set(HyperController.systemKeyboards().map(\.id))
        precondition(!initial.isEmpty, "No keyboard services are available")
        for _ in 0..<1000 {
            let snapshot = HyperController.systemKeyboards()
            precondition(Set(snapshot.map(\.id)) == initial, "Keyboard changed during the lifetime check; rerun with stable devices")
            for keyboard in snapshot { _ = try keyboard.read() }
        }
        print("PASS: 1000 fresh native keyboard snapshots read and released without a stale connection or lifetime crash")
    }
}
