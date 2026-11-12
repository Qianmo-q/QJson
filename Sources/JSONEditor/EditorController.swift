import AppKit
import JSONCore

final class EditorController: NSObject, NSTextViewDelegate {
    let scrollView = NSScrollView()
    private(set) var textView: CodeTextView!
    private var ruler: LineNumberRulerView!
    weak var model: AppModel?

    private(set) var lineStarts: [Int] = [0]
    private var lastHighlightRange = NSRange(location: 0, length: 0)
    private var errorLineRange: NSRange?
    private var errorLineNumber: Int?
    private var searchRanges: [NSRange] = []
    private var currentSearchRange: NSRange?
    private var highlightScheduled = false
    private var observer: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        super.init()
        buildViews()
        applyTheme()
        installObservers()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    private func buildViews() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)

        let textView = CodeTextView(
            frame: NSRect(x: 0, y: 0, width: 760, height: 600),
            textContainer: container
        )
        textView.editor = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = Palette.background
        textView.textColor = Palette.text
        textView.insertionPointColor = Palette.text
        textView.font = Theme.editorFont
        textView.typingAttributes = [
            .font: Theme.editorFont,
            .foregroundColor: Palette.text,
        ]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 12)
        textView.usesFindBar = false
        textView.isIncrementalSearchingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.allowsDocumentBackgroundColorChange = false
        textView.selectedTextAttributes = [.backgroundColor: Palette.selection]
        textView.delegate = self
        self.textView = textView

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Palette.background
        scrollView.documentView = textView

        let ruler = LineNumberRulerView(scrollView: scrollView, textView: textView)
        self.ruler = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView = ruler
    }

    private func installObservers() {
        scrollView.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleHighlight()
            self?.ruler.needsDisplay = true
        }
    }

    // MARK: - 对外操作

    var text: String { textView.string }

    func replaceAllText(_ text: String, undoable: Bool) {
        let length = textView.textStorage?.length ?? 0
        let full = NSRange(location: 0, length: length)
        if undoable, textView.undoManager != nil {
            textView.undoManager?.beginUndoGrouping()
            textView.insertText(text, replacementRange: full)
            textView.undoManager?.endUndoGrouping()
        } else {
            textView.undoManager?.removeAllActions()
            textView.textStorage?.replaceCharacters(in: full, with: text)
            applyBaseAttributes()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            handleTextChanged()
        }
    }

    func replaceCharacters(in range: NSRange, with replacement: String) {
        let length = textView.textStorage?.length ?? 0
        guard range.location >= 0, range.location <= length else { return }
        let safe = NSRange(location: range.location, length: min(range.length, length - range.location))
        textView.insertText(replacement, replacementRange: safe)
    }

    func reveal(_ range: NSRange, select: Bool = true) {
        let length = textView.textStorage?.length ?? 0
        guard range.location >= 0, range.location <= length else { return }
        let safe = NSRange(location: range.location, length: min(range.length, length - range.location))
        if select { textView.setSelectedRange(safe) }
        textView.scrollRangeToVisible(safe)
        if safe.length > 0 {
            textView.showFindIndicator(for: safe)
        }
    }

    func setErrorHighlight(line: Int?, range: NSRange?) {
        errorLineNumber = line
        errorLineRange = range
        ruler.update(lineStarts: lineStarts, errorLine: line)
        refreshHighlight()
    }

    func setSearchHighlights(ranges: [NSRange], current: NSRange?) {
        searchRanges = ranges
        currentSearchRange = current
        refreshHighlight()
    }

    func clearTransientHighlights() {
        errorLineNumber = nil
        errorLineRange = nil
        searchRanges = []
        currentSearchRange = nil
        ruler.update(lineStarts: lineStarts, errorLine: nil)
        refreshHighlight()
    }

    func focus() {
        textView.window?.makeFirstResponder(textView)
    }

    func caretLineColumn() -> (line: Int, column: Int) {
        lineColumn(at: textView.selectedRange().location, lineStarts: lineStarts)
    }

    // MARK: - 主题

    func applyTheme() {
        scrollView.backgroundColor = Palette.background
        scrollView.verticalScroller?.needsDisplay = true
        textView.backgroundColor = Palette.background
        textView.textColor = Palette.text
        textView.insertionPointColor = Palette.text
        textView.selectedTextAttributes = [.backgroundColor: Palette.selection]
        textView.typingAttributes = [
            .font: Theme.editorFont,
            .foregroundColor: Palette.text,
        ]
        ruler?.needsDisplay = true
    }

    private func applyBaseAttributes() {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        storage.addAttributes(
            [.font: Theme.editorFont, .foregroundColor: Palette.text],
            range: NSRange(location: 0, length: storage.length)
        )
    }

    // MARK: - 文本变化

    func handleTextChanged() {
        let text = textView.string
        lineStarts = Self.fastLineStarts(text)
        errorLineNumber = nil
        errorLineRange = nil
        searchRanges = []
        currentSearchRange = nil
        ruler.update(lineStarts: lineStarts, errorLine: nil)
        let length = textView.textStorage?.length ?? 0
        lastHighlightRange = clamp(lastHighlightRange, length)
        refreshHighlight()
        updateCaret()
        model?.editorTextDidChange(text, lineStarts: lineStarts)
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateCaret()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        model?.undoManager
    }

    private func updateCaret() {
        let caret = lineColumn(at: textView.selectedRange().location, lineStarts: lineStarts)
        model?.editorCaretMoved(line: caret.line, column: caret.column, selectionLength: textView.selectedRange().length)
    }

    // MARK: - 高亮

    func scheduleHighlight() {
        guard !highlightScheduled else { return }
        highlightScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.highlightScheduled = false
            self?.refreshHighlight()
        }
    }

    func refreshHighlight() {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              let storage = textView.textStorage else { return }
        let length = storage.length
        let previous = clamp(lastHighlightRange, length)
        if previous.length > 0 {
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: previous)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: previous)
        }
        guard length > 0 else {
            lastHighlightRange = NSRange(location: 0, length: 0)
            return
        }
        let visible = textView.visibleRect
        let probe = NSRect(
            x: visible.minX,
            y: visible.minY - 200,
            width: max(visible.width, 1),
            height: max(visible.height, 1) + 400
        )
        let glyphRange = layoutManager.glyphRange(forBoundingRect: probe, in: container)
        var charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        charRange.location = min(charRange.location, length)
        charRange.length = min(charRange.length, length - charRange.location)
        let lineRange = (storage.string as NSString).lineRange(for: charRange)
        let highlightRange = clamp(lineRange, length)
        lastHighlightRange = highlightRange
        guard highlightRange.length > 0 else { return }

        let tokens = VisibleSyntaxLexer.tokens(in: storage.string as NSString, visibleRange: highlightRange)
        for token in tokens {
            let clipped = NSIntersectionRange(token.range, highlightRange)
            guard clipped.length > 0 else { continue }
            layoutManager.addTemporaryAttribute(
                .foregroundColor,
                value: Theme.color(for: token.kind),
                forCharacterRange: clipped
            )
        }

        if let errorLineRange {
            let clipped = NSIntersectionRange(errorLineRange, highlightRange)
            if clipped.length > 0 {
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: Palette.errorBackground,
                    forCharacterRange: clipped
                )
            }
        }

        for range in searchRanges {
            let clipped = NSIntersectionRange(range, highlightRange)
            guard clipped.length > 0 else { continue }
            let isCurrent = currentSearchRange.map { NSEqualRanges($0, range) } ?? false
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: isCurrent ? Palette.currentMatchBackground : Palette.matchBackground,
                forCharacterRange: clipped
            )
        }
    }

    private func clamp(_ range: NSRange, _ length: Int) -> NSRange {
        guard range.location >= 0 else { return NSRange(location: 0, length: 0) }
        let location = min(range.location, length)
        return NSRange(location: location, length: min(range.length, length - location))
    }

    static func fastLineStarts(_ text: String) -> [Int] {
        var starts: [Int] = [0]
        let ns = text as NSString
        let total = ns.length
        guard total > 0 else { return starts }
        let chunkSize = 1 << 16
        var buffer = [unichar](repeating: 0, count: min(chunkSize, total))
        var base = 0
        while base < total {
            let count = min(chunkSize, total - base)
            buffer.withUnsafeMutableBufferPointer { pointer in
                guard let address = pointer.baseAddress else { return }
                ns.getCharacters(address, range: NSRange(location: base, length: count))
            }
            for index in 0..<count where buffer[index] == 0x0A {
                starts.append(base + index + 1)
            }
            base += count
        }
        return starts
    }
}
