import SwiftUI

/// A status bar rendered below the terminal surface, showing styled segments
/// produced by the user's status bar script.
struct StatusBarView: View {
    let segments: [StatusBarSegment]
    var fontFamily: String? = nil
    var backgroundColor: Color = Color.black.opacity(0.85)

    var body: some View {
        HStack(spacing: 0) {
            // Left-aligned segments
            ForEach(segments.filter { $0.align == .left }) { segment in
                SegmentView(segment: segment, fontFamily: fontFamily)
            }

            Spacer()

            // Right-aligned segments
            ForEach(segments.filter { $0.align == .right }) { segment in
                SegmentView(segment: segment, fontFamily: fontFamily)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(backgroundColor)
    }
}

/// Renders a single status bar segment with its styling.
private struct SegmentView: View {
    let segment: StatusBarSegment
    var fontFamily: String? = nil

    private var font: Font {
        let weight: Font.Weight = segment.bold ? .bold : .regular
        if let fontFamily {
            return .custom(fontFamily, size: 12).weight(weight)
        }
        return .system(size: 12, weight: weight)
    }

    private var truncatedText: String {
        guard let first = segment.text.first else { return "" }
        return "\(first)..."
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            styledText(segment.text)
            styledText(truncatedText)
                .help(segment.text)
        }
        .padding(.horizontal, 2)
        .background(segment.bg ?? .clear)
    }

    private func styledText(_ text: String) -> some View {
        Text(text)
            .font(font)
            .italic(segment.italic)
            .underline(segment.underline)
            .foregroundColor(segment.fg ?? .white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
