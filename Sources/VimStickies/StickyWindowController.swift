import AppKit
import CVimBridge

@MainActor
private final class StickyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class StickyWindowController: NSWindowController, NSWindowDelegate {
    private let onClose: (StickyWindowController) -> Void
    private let onFrameChange: (NSRect) -> Void
    private let editorView: StickyEditorView
    private var userAdjusted = false
    private var settleFrame: NSRect?
    private var settleChecks = 0
    private var settleTimer: Timer?

    init(
        initialText: String,
        colorscheme: Colorscheme,
        calendarPreferences: CalendarView.Preferences,
        restoredFrame: NSRect?,
        onTextChange: @escaping (String) -> Void,
        onFrameChange: @escaping (NSRect) -> Void,
        onClose: @escaping (StickyWindowController) -> Void
    ) {
        self.onClose = onClose
        self.onFrameChange = onFrameChange

        let window = StickyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        editorView = StickyEditorView(
            initialText: initialText,
            colorscheme: colorscheme,
            calendarPreferences: calendarPreferences,
            onTextChange: onTextChange,
            onClose: { [weak window] in window?.close() }
        )

        super.init(window: window)
        configure(window, restoredFrame: restoredFrame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepareForDeactivation() {
        editorView.deactivate()
    }

    func captureFrame() {
        guard let window else {
            return
        }
        var frame = window.frame
        frame.size.width = max(frame.size.width, window.minSize.width)
        frame.size.height = max(frame.size.height, window.minSize.height)
        onFrameChange(frame)
    }

    func applyColorscheme(_ scheme: Colorscheme) {
        window?.backgroundColor = scheme.colors.body
        editorView.applyColorscheme(scheme)
    }

    func setAlwaysOnTop(_ flag: Bool) {
        window?.level = flag ? .floating : .normal
    }

    func applyCalendarPreferences(_ preferences: CalendarView.Preferences) {
        editorView.applyCalendarPreferences(preferences)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        editorView.setWindowFocused(true)
        editorView.activate()
        editorView.refreshCalendar()
        window?.makeFirstResponder(editorView.textView)
    }

    func windowDidResignKey(_ notification: Notification) {
        editorView.deactivate()
        editorView.setWindowFocused(false)
    }

    func windowWillClose(_ notification: Notification) {
        editorView.deactivate()
        onClose(self)
    }

    func windowDidMove(_ notification: Notification) {
        userAdjusted = true
        captureFrame()
    }

    func windowDidResize(_ notification: Notification) {
        userAdjusted = true
        captureFrame()
    }

    private func configure(_ window: StickyPanel, restoredFrame: NSRect?) {
        window.delegate = self
        window.title = "Sticky"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.minSize = NSSize(width: 260, height: 200)
        window.backgroundColor = editorView.colorscheme.colors.body
        window.isOpaque = true
        window.hasShadow = true
        window.contentView = editorView
        editorView.autoresizingMask = [.width, .height]
        if let restoredFrame {
            var frame = restoredFrame
            if frame.width < window.minSize.width {
                frame.size.width = window.minSize.width
            }
            if frame.height < window.minSize.height {
                frame.size.height = window.minSize.height
            }
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
        settleFrame = window.frame
        let watchdog = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else {
                    self?.settleTimer?.invalidate()
                    return
                }
                self.settleChecks += 1
                if self.settleChecks >= 16 {
                    self.settleTimer?.invalidate()
                    return
                }
                if !self.userAdjusted, let settle = self.settleFrame, window.frame != settle {
                    window.setFrame(settle, display: true)
                }
            }
        }
        RunLoop.main.add(watchdog, forMode: .common)
        settleTimer = watchdog
        window.makeFirstResponder(editorView.textView)
    }
}

@MainActor
private final class StickyEditorView: NSView, NSTextViewDelegate, VimTextViewEventHandler {
    let textView: VimTextView

    private let buffer: VSBufferRef
    private let titleBar = NSView()
    private let closeButton = NSButton(title: "□", target: nil, action: nil)
    private let modeLabel = NSTextField(labelWithString: "NORMAL")
    private let calendarView = CalendarView()
    private let scrollView = NSScrollView()
    private let onTextChange: (String) -> Void
    private let onClose: () -> Void
    private var isRendering = false
    private var clockTimer: Timer?
    private var calendarPreferences: CalendarView.Preferences

    private(set) var colorscheme: Colorscheme

    override var fittingSize: NSSize {
        frame.size
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 260, height: 200)
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
    }

    init(
        initialText: String,
        colorscheme: Colorscheme,
        calendarPreferences: CalendarView.Preferences,
        onTextChange: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onTextChange = onTextChange
        self.onClose = onClose
        self.colorscheme = colorscheme
        self.calendarPreferences = calendarPreferences

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        textView = VimTextView(frame: .zero, textContainer: textContainer)

        VSInitialize()
        guard let buffer = initialText.withCString({ VSCreateBuffer($0) }) else {
            fatalError("Unable to create libvim buffer")
        }
        self.buffer = buffer

        super.init(frame: .zero)
        configureView()
        renderEngineState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func activate() {
        VSActivateBuffer(buffer)
        renderEngineState()
    }

    func deactivate() {
        VSActivateBuffer(buffer)
        if VSGetMode() == VSModeInsert {
            commitNativeInsert()
        }
        if VSGetMode() != VSModeNormal {
            sendKey("<esc>")
        }
        renderEngineState()
    }

    func setWindowFocused(_ focused: Bool) {
        titleBar.isHidden = !focused
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func applyCalendarPreferences(_ preferences: CalendarView.Preferences) {
        calendarPreferences = preferences
        calendarView.applyPreferences(preferences)
        updateCalendarHeight()
        layoutSubtreeIfNeeded()
    }

    func refreshCalendar() {
        calendarView.clockTick()
    }

    func applyColorscheme(_ scheme: Colorscheme) {
        colorscheme = scheme
        let colors = scheme.colors

        wantsLayer = true
        layer?.backgroundColor = colors.body.cgColor
        layer?.borderColor = colors.ink.withAlphaComponent(0.35).cgColor
        layer?.borderWidth = 1

        titleBar.wantsLayer = true
        titleBar.layer?.backgroundColor = colors.bar.cgColor

        closeButton.attributedTitle = NSAttributedString(
                string: "□",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .bold),
                    .foregroundColor: colors.ink
                ]
            )

        modeLabel.textColor = colors.ink

        textView.textColor = .black
        textView.insertionPointColor = .black
        textView.selectedTextAttributes = [
            .backgroundColor: colors.ink.withAlphaComponent(0.22),
            .foregroundColor: NSColor.black
        ]
        textView.needsDisplay = true

        calendarView.applyColors(background: colors.body, ink: colors.ink)
    }

    func vimTextView(_ textView: VimTextView, handle event: NSEvent) -> Bool {
        VSActivateBuffer(buffer)

        if VSGetMode() == VSModeInsert {
            guard event.keyCode == 53 else {
                return false
            }

            commitNativeInsert()
            sendKey("<esc>")
            renderEngineState()
            return true
        }

        if event.modifierFlags.contains(.command) {
            return false
        }

        if let key = specialKey(for: event) {
            sendKey(key)
            renderEngineState()
            return true
        }

        guard let input = event.charactersIgnoringModifiers, !input.isEmpty else {
            return true
        }

        if input == ":" || input == "/" || input == "?" {
            NSSound.beep()
            return true
        }

        if event.modifierFlags.contains(.control) {
            sendKey("<c-\(input.lowercased())>")
        } else {
            sendInput(input)
        }
        renderEngineState()
        return true
    }

    func vimTextViewDidMoveSelection(_ textView: VimTextView) {
        VSActivateBuffer(buffer)
        guard VSGetMode() != VSModeInsert else {
            return
        }

        let position = enginePosition(atUTF16Offset: textView.selectedRange().location)
        VSSetCursor(Int32(position.line), Int32(position.column))
        renderEngineState()
    }

    func textDidChange(_ notification: Notification) {
        guard !isRendering else {
            return
        }
        onTextChange(textView.string)
    }

    @objc private func closeSticky(_ sender: Any?) {
        onClose()
    }

    private func configureView() {
        wantsLayer = true

        titleBar.wantsLayer = true

        closeButton.target = self
        closeButton.action = #selector(closeSticky(_:))
        closeButton.isBordered = false

        modeLabel.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        modeLabel.alignment = .right

        titleBar.addSubview(closeButton)
        titleBar.addSubview(modeLabel)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        textView.eventHandler = self
        textView.delegate = self
        textView.autoresizingMask = [.width]
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
        textView.textContainerInset = NSSize(width: 7, height: 6)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        addSubview(titleBar)
        addSubview(calendarView)
        addSubview(scrollView)

        calendarView.onGeometryChange = { [weak self] in
            self?.updateCalendarHeight()
        }
        calendarView.applyPreferences(calendarPreferences)
        updateCalendarHeight()

        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.calendarView.clockTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer

        applyColorscheme(colorscheme)
    }

    private func updateCalendarHeight() {
        let visible = calendarPreferences.isVisible
        calendarView.isHidden = !visible
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        let titleBarHeight: CGFloat = titleBar.isHidden ? 0 : 13
        let calendarHeight = calendarView.isHidden ? 0 : calendarView.neededHeight
        let width = bounds.width
        let height = bounds.height

        titleBar.frame = NSRect(x: 0, y: height - titleBarHeight, width: width, height: titleBarHeight)

        let scrollHeight = height - titleBarHeight - calendarHeight
        scrollView.frame = NSRect(x: 0, y: 0, width: width, height: max(scrollHeight, 0))
        calendarView.frame = NSRect(x: 0, y: scrollHeight, width: width, height: calendarHeight)

        let closeY = titleBarHeight > 0 ? (titleBarHeight - 12) / 2 : 0
        closeButton.frame = NSRect(x: 6, y: closeY, width: 12, height: 12)
        modeLabel.sizeToFit()
        modeLabel.frame = NSRect(
            x: width - modeLabel.frame.width - 6,
            y: titleBarHeight > 0 ? (titleBarHeight - modeLabel.frame.height) / 2 : 0,
            width: modeLabel.frame.width,
            height: modeLabel.frame.height
        )
    }

    private func commitNativeInsert() {
        textView.unmarkText()
        textView.string.withCString { VSSetText(buffer, $0) }
        let position = enginePosition(atUTF16Offset: textView.selectedRange().location)
        VSSetCursor(Int32(position.line), Int32(position.column))
    }

    private func renderEngineState() {
        let mode = VSGetMode()
        let text = copyEngineText()
        if textView.string != text {
            isRendering = true
            textView.string = text
            isRendering = false
            onTextChange(text)
        }

        textView.isEditable = true
        textView.acceptsNativeEdits = mode == VSModeInsert
        textView.drawsBlockCursor = mode == VSModeNormal
        updateModeIcon(mode)

        if mode == VSModeVisual {
            var visualRange = VSVisualRange()
            if VSGetVisualRange(&visualRange) {
                textView.setSelectedRange(selectionRange(for: visualRange, in: text))
            }
        } else {
            let cursor = VSGetCursor()
            let offset = utf16Offset(
                line: Int(cursor.line),
                byteColumn: Int(cursor.column),
                in: text,
                afterCharacter: false
            )
            textView.setSelectedRange(NSRange(location: offset, length: 0))
        }
        textView.scrollRangeToVisible(textView.selectedRange())
        textView.needsDisplay = true
    }

    private func updateModeIcon(_ mode: VSMode) {
        modeLabel.stringValue = switch mode {
        case VSModeInsert: "INSERT"
        case VSModeVisual: "VISUAL"
        default: "NORMAL"
        }
    }

    private func copyEngineText() -> String {
        guard let pointer = VSCopyText(buffer) else {
            return ""
        }
        defer { VSFree(pointer) }
        return String(cString: pointer)
    }

    private func sendInput(_ input: String) {
        input.withCString { VSInput($0) }
    }

    private func sendKey(_ key: String) {
        key.withCString { VSKey($0) }
    }

    private func specialKey(for event: NSEvent) -> String? {
        switch event.keyCode {
        case 53: "<esc>"
        case 36, 76: "<cr>"
        case 51: "<bs>"
        case 123: "<left>"
        case 124: "<right>"
        case 125: "<down>"
        case 126: "<up>"
        default: nil
        }
    }

    private func enginePosition(atUTF16Offset requestedOffset: Int) -> (line: Int, column: Int) {
        let text = textView.string as NSString
        let offset = min(max(requestedOffset, 0), text.length)
        let prefix = text.substring(to: offset)
        let lines = prefix.components(separatedBy: "\n")
        return (lines.count, lines.last?.utf8.count ?? 0)
    }

    private func selectionRange(for visualRange: VSVisualRange, in text: String) -> NSRange {
        let startsBeforeEnd = visualRange.startLine < visualRange.endLine
            || (visualRange.startLine == visualRange.endLine
                && visualRange.startColumn <= visualRange.endColumn)
        let firstLine = startsBeforeEnd ? visualRange.startLine : visualRange.endLine
        let firstColumn = startsBeforeEnd ? visualRange.startColumn : visualRange.endColumn
        let lastLine = startsBeforeEnd ? visualRange.endLine : visualRange.startLine
        let lastColumn = startsBeforeEnd ? visualRange.endColumn : visualRange.startColumn

        let start = utf16Offset(
            line: Int(firstLine),
            byteColumn: Int(firstColumn),
            in: text,
            afterCharacter: false
        )

        if visualRange.linewise {
            let end = startOfLine(Int(lastLine) + 1, in: text) ?? (text as NSString).length
            let lineStart = startOfLine(Int(firstLine), in: text) ?? start
            return NSRange(location: lineStart, length: max(0, end - lineStart))
        }

        let end = utf16Offset(
            line: Int(lastLine),
            byteColumn: Int(lastColumn),
            in: text,
            afterCharacter: true
        )
        return NSRange(location: start, length: max(0, end - start))
    }

    private func startOfLine(_ requestedLine: Int, in text: String) -> Int? {
        guard requestedLine >= 1 else {
            return 0
        }

        let lines = text.components(separatedBy: "\n")
        guard requestedLine <= lines.count else {
            return nil
        }
        return lines.prefix(requestedLine - 1).reduce(0) { $0 + $1.utf16.count + 1 }
    }

    private func utf16Offset(
        line requestedLine: Int,
        byteColumn requestedColumn: Int,
        in text: String,
        afterCharacter: Bool
    ) -> Int {
        let lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else {
            return 0
        }

        let lineIndex = min(max(requestedLine - 1, 0), lines.count - 1)
        let line = lines[lineIndex]
        let lineStart = lines.prefix(lineIndex).reduce(0) { $0 + $1.utf16.count + 1 }
        let byteOffset = min(max(requestedColumn, 0), line.utf8.count)

        var utf8Index = line.utf8.index(line.utf8.startIndex, offsetBy: byteOffset)
        var stringIndex = String.Index(utf8Index, within: line)
        while stringIndex == nil, utf8Index > line.utf8.startIndex {
            utf8Index = line.utf8.index(before: utf8Index)
            stringIndex = String.Index(utf8Index, within: line)
        }

        guard var index = stringIndex else {
            return lineStart
        }
        if afterCharacter, index < line.endIndex {
            index = line.index(after: index)
        }
        return lineStart + line.utf16.distance(from: line.utf16.startIndex, to: index)
    }
}
