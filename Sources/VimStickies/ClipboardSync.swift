import AppKit
import CVimBridge

let clipboardSyncDefaultsKey = "clipboardSyncDeletes"

enum VimClipboardState {
    nonisolated(unsafe) static var syncDeletesToClipboard: Bool = false
}

enum VimClipboard {
    static func loadDefaults() {
        VimClipboardState.syncDeletesToClipboard =
            UserDefaults.standard.bool(forKey: clipboardSyncDefaultsKey)
    }

    static func install() {
        VSSetClipboardGetCallback(clipboardGetCallback)
        VSSetYankCallback(yankCallback)
    }

    nonisolated(unsafe) private static let clipboardGetCallback: VSClipboardGetCallback = {
        _, numLinesPtr, linesPtr, blockTypePtr in
        guard let numLinesPtr, let linesPtr, let blockTypePtr else {
            return 0
        }

        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.isEmpty else {
            return 0
        }

        let hasTrailingNewline = text.hasSuffix("\n")
        var parts = text.components(separatedBy: "\n")
        if hasTrailingNewline && !parts.isEmpty {
            parts.removeLast()
        }

        let buffer = UnsafeMutablePointer<UnsafeMutablePointer<CUnsignedChar>?>.allocate(
            capacity: parts.count
        )
        for (index, part) in parts.enumerated() {
            buffer[index] = allocateVimLine(part)
        }

        numLinesPtr.pointee = Int32(parts.count)
        blockTypePtr.pointee = hasTrailingNewline ? 1 : 0
        linesPtr.pointee = buffer
        return 1
    }

    nonisolated(unsafe) private static let yankCallback: VSYankCallback = { yankPtr in
        guard let yank = yankPtr?.pointee else {
            return
        }
        if yank.opChar != UInt8(ascii: "y") && !VimClipboardState.syncDeletesToClipboard {
            return
        }
        guard let text = yankedText(from: yank), !text.isEmpty else {
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func yankedText(from yank: VSYankInfo) -> String? {
        let count = Int(yank.numLines)
        guard count > 0, let lines = yank.lines else {
            return nil
        }

        var parts: [String] = []
        parts.reserveCapacity(count)
        for index in 0..<count {
            if let line = lines[index] {
                parts.append(readVimLine(line))
            } else {
                parts.append("")
            }
        }

        var text = parts.joined(separator: "\n")
        if yank.blockType == 1 {
            text.append("\n")
        }
        return text
    }

    private static func readVimLine(_ line: UnsafePointer<CUnsignedChar>) -> String {
        var bytes: [UInt8] = []
        var cursor = line
        while cursor.pointee != 0 {
            bytes.append(cursor.pointee)
            cursor = cursor.advanced(by: 1)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func allocateVimLine(_ string: String) -> UnsafeMutablePointer<CUnsignedChar> {
        let bytes = Array(string.utf8) + [0]
        let pointer = UnsafeMutablePointer<CUnsignedChar>.allocate(capacity: bytes.count)
        let buffer = UnsafeMutableBufferPointer(start: pointer, count: bytes.count)
        _ = bytes.withUnsafeBufferPointer { buffer.initialize(from: $0) }
        return pointer
    }
}