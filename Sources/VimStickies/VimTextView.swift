import AppKit

@MainActor
protocol VimTextViewEventHandler: AnyObject {
    func vimTextView(_ textView: VimTextView, handle event: NSEvent) -> Bool
    func vimTextViewDidMoveSelection(_ textView: VimTextView)
}

@MainActor
final class VimTextView: NSTextView {
    weak var eventHandler: VimTextViewEventHandler?
    var acceptsNativeEdits = false
    var drawsBlockCursor = false {
        didSet {
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if eventHandler?.vimTextView(self, handle: event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        eventHandler?.vimTextViewDidMoveSelection(self)
    }

    override func shouldChangeText(
        in affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        acceptsNativeEdits && super.shouldChangeText(
            in: affectedCharRange,
            replacementString: replacementString
        )
    }

    override func drawInsertionPoint(
        in rect: NSRect,
        color: NSColor,
        turnedOn flag: Bool
    ) {
        guard drawsBlockCursor else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
            return
        }

        var blockRect = rect
        blockRect.size.width = max(font?.maximumAdvancement.width ?? 5.5, 5.5)
        super.drawInsertionPoint(
            in: blockRect,
            color: NSColor.black.withAlphaComponent(0.58),
            turnedOn: true
        )
    }
}
