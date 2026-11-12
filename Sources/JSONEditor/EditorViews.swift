import AppKit
import JSONCore

final class CodeTextView: NSTextView {
    weak var editor: EditorController?

    override func didChangeText() {
        super.didChangeText()
        editor?.handleTextChanged()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        editor?.applyTheme()
        editor?.refreshHighlight()
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        editor?.scheduleHighlight()
    }
}

final class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    var lineStarts: [Int] = [0]
    var errorLine: Int?
    var theme: PaletteTheme = .shared

    override var isFlipped: Bool { true }

    override var requiredThickness: CGFloat {
        let digits = max(2, String(max(1, lineStarts.count)).count)
        return max(44, CGFloat(digits) * 8 + 20)
    }

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    func update(lineStarts: [Int], errorLine: Int?) {
        self.lineStarts = lineStarts.isEmpty ? [0] : lineStarts
        self.errorLine = errorLine
        let desired = requiredThickness
        if abs(ruleThickness - desired) > 0.5 {
            ruleThickness = desired
            scrollView?.tile()
        }
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        theme.gutterBackground.setFill()
        bounds.fill()

        // 右侧分隔线
        theme.border.setStroke()
        let separator = NSBezierPath()
        separator.lineWidth = 1
        separator.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        separator.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        separator.stroke()

        guard let textView = textView as? CodeTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let contentView = scrollView?.contentView,
              (textView.textStorage?.length ?? 0) > 0 else {
            return
        }

        let visibleRect = contentView.bounds
        let inset = textView.textContainerInset
        let containerRect = NSRect(
            x: visibleRect.minX - inset.width,
            y: visibleRect.minY - inset.height,
            width: visibleRect.width + inset.width * 2,
            height: visibleRect.height + inset.height * 2
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        guard glyphRange.length > 0 else { return }
        let relativePoint = convert(NSPoint.zero, from: textView)

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
            let characterRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            let number = lineNumber(at: characterRange.location, lineStarts: self.lineStarts)
            let isError = (number == self.errorLine)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Theme.rulerFont,
                .foregroundColor: isError ? self.theme.errorText : self.theme.gutterText,
            ]
            let string = "\(number)" as NSString
            let size = string.size(withAttributes: attributes)
            let y = relativePoint.y + usedRect.minY + inset.height + (usedRect.height - size.height) / 2
            let x = self.bounds.width - size.width - 9
            string.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        }
    }
}

struct PaletteTheme {
    let gutterBackground: NSColor
    let gutterText: NSColor
    let errorText: NSColor
    let border: NSColor

    static let shared = PaletteTheme(
        gutterBackground: Palette.gutterBackground,
        gutterText: Palette.gutterText,
        errorText: Palette.errorText,
        border: Palette.border
    )
}
