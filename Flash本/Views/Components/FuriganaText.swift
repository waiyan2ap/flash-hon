import SwiftUI
import CoreText

struct FuriganaText: UIViewRepresentable {
    let text: String
    var font: UIFont = .preferredFont(forTextStyle: .title3)
    var textColor: UIColor = .label

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = createAttributedString()
    }

    private func createAttributedString() -> NSAttributedString {
        let segments = FuriganaParser.parse(text)
        let result = NSMutableAttributedString()

        for segment in segments {
            if let furigana = segment.furigana {
                let annotation = CTRubyAnnotationCreateWithAttributes(
                    CTRubyAlignment.auto,
                    CTRubyOverhang.auto,
                    CTRubyPosition.before,
                    furigana as CFString,
                    [:] as CFDictionary
                )

                let attrString = NSAttributedString(
                    string: segment.text,
                    attributes: [kCTRubyAnnotationAttributeName as NSAttributedString.Key: annotation]
                )
                result.append(attrString)
            } else {
                result.append(NSAttributedString(string: segment.text))
            }
        }

        result.addAttribute(.font, value: font, range: NSRange(location: 0, length: result.length))
        result.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: result.length))

        return result
    }
}
