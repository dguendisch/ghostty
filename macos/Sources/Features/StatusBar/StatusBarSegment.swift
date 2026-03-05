import SwiftUI

/// A single styled segment of the status bar, parsed from JSON output
/// of the user's status bar script.
struct StatusBarSegment: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let fg: Color?
    let bg: Color?
    let bold: Bool
    let italic: Bool
    let underline: Bool
    let align: SegmentAlignment

    enum SegmentAlignment: String {
        case left
        case right
    }

    /// Parse a JSON string into an array of status bar segments.
    /// Returns an empty array if the JSON is invalid.
    static func parse(json: String) -> [StatusBarSegment] {
        guard let data = json.data(using: .utf8) else { return [] }

        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { dict in
            guard let text = dict["text"] as? String else { return nil }

            return StatusBarSegment(
                text: text,
                fg: (dict["fg"] as? String).flatMap { Color(hex: $0) },
                bg: (dict["bg"] as? String).flatMap { Color(hex: $0) },
                bold: dict["bold"] as? Bool ?? false,
                italic: dict["italic"] as? Bool ?? false,
                underline: dict["underline"] as? Bool ?? false,
                align: SegmentAlignment(rawValue: dict["align"] as? String ?? "left") ?? .left
            )
        }
    }

    static func == (lhs: StatusBarSegment, rhs: StatusBarSegment) -> Bool {
        lhs.id == rhs.id
    }
}

extension Color {
    /// Initialize a Color from a hex string like "#a6e3a1" or "a6e3a1".
    init?(hex: String) {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexStr.hasPrefix("#") {
            hexStr.removeFirst()
        }

        guard hexStr.count == 6,
              let value = UInt64(hexStr, radix: 16) else {
            return nil
        }

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
