import Foundation

struct FuriganaSegment: Equatable {
    let text: String
    let furigana: String?
}

struct FuriganaParser {
    static func parse(_ input: String) -> [FuriganaSegment] {
        var segments: [FuriganaSegment] = []
        var remaining = input[...]

        let pattern = /([^\[\]]+)\[([^\]]+)\]/
        while let match = remaining.firstMatch(of: pattern) {
            let before = String(remaining[..<match.range.lowerBound])
            if !before.isEmpty {
                segments.append(FuriganaSegment(text: before, furigana: nil))
            }
            segments.append(FuriganaSegment(text: String(match.1), furigana: String(match.2)))
            remaining = remaining[match.range.upperBound...]
        }

        if !remaining.isEmpty {
            segments.append(FuriganaSegment(text: String(remaining), furigana: nil))
        }

        return segments
    }
}
