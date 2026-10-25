import Foundation

// Exact descriptor observed on the user's Touch@LOFREE Bluetooth interface.
let verifiedDescriptor: [UInt8] = "05 01 09 02 A1 01 85 03 09 01 A1 00 05 09 19 01 29 03 15 00 25 01 75 01 95 05 81 02 75 03 95 01 81 01 05 01 09 30 09 31 16 01 80 26 FF 7F 75 10 95 02 81 06 09 38 15 81 25 7F 75 08 95 01 81 06 05 0C 0A 38 02 95 01 75 08 81 06 C0 C0 06 01 FF 09 01 A1 01 85 05 09 05 15 00 26 FF 00 75 08 95 04 B1 02 C0".split(separator: " ").map { UInt8($0, radix: 16)! }

enum SideEdge: Equatable { case down(UInt8), up(UInt8), cancel }
struct SideDecoder {
    private var previous: UInt8 = 0
    private var waitingForNeutral = true
    mutating func reset() { previous = 0; waitingForNeutral = true }
    mutating func consume(reportID: UInt32, bytes: [UInt8]) -> [SideEdge] {
        guard reportID == 3 else { return [] }
        guard bytes.count == 8, bytes[0] == 3, bytes[1] & 0xE0 == 0 else {
            reset(); return [.cancel]
        }
        let side = bytes[1] & 0x18
        // Combined side buttons, or side+ordinary clicks, cancel the gesture.
        if side == 0x18 || (side != 0 && bytes[1] & 7 != 0) {
            reset(); return [.cancel]
        }
        if waitingForNeutral {
            if side == 0 { waitingForNeutral = false }
            return []
        }
        guard side != previous else { return [] }
        let old = previous
        previous = side
        if old != 0 && side != 0 { reset(); return [.cancel] }
        return old == 0 ? [.down(side)] : [.up(old)]
    }
}
