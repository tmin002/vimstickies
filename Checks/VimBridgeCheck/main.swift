import CVimBridge

var testGetLines: [String] = []
var testGetBlockType: Int32 = 0

let testClipboardGet: VSClipboardGetCallback = { _, numLinesPtr, linesPtr, blockTypePtr in
    guard !testGetLines.isEmpty, let numLinesPtr, let linesPtr, let blockTypePtr else {
        return 0
    }
    let buffer = UnsafeMutablePointer<UnsafeMutablePointer<CUnsignedChar>?>.allocate(
        capacity: testGetLines.count
    )
    for (index, line) in testGetLines.enumerated() {
        let bytes = Array(line.utf8) + [0]
        let pointer = UnsafeMutablePointer<CUnsignedChar>.allocate(capacity: bytes.count)
        let destBuffer = UnsafeMutableBufferPointer(start: pointer, count: bytes.count)
        _ = bytes.withUnsafeBufferPointer { destBuffer.initialize(from: $0) }
        buffer[index] = pointer
    }
    numLinesPtr.pointee = Int32(testGetLines.count)
    blockTypePtr.pointee = testGetBlockType
    linesPtr.pointee = buffer
    return 1
}

var lastYankOpChar: Int32 = -1
var lastYankText = ""

let testYank: VSYankCallback = { info in
    guard let info = info?.pointee else {
        return
    }
    lastYankOpChar = info.opChar
    var parts: [String] = []
    for index in 0..<Int(info.numLines) {
        guard let line = info.lines?[index] else {
            parts.append("")
            continue
        }
        var bytes: [UInt8] = []
        var cursor = line
        while cursor.pointee != 0 {
            bytes.append(cursor.pointee)
            cursor = cursor.advanced(by: 1)
        }
        parts.append(String(decoding: bytes, as: UTF8.self))
    }
    lastYankText = parts.joined(separator: "\n")
}

VSInitialize()
let buffer = "one two\nthree".withCString { VSCreateBuffer($0) }
precondition(buffer != nil)
VSActivateBuffer(buffer)

sendInput("w")
precondition(VSGetCursor().column == 4)

sendInput("i")
precondition(VSGetMode() == VSModeInsert)
sendInput("big ")
sendKey("<esc>")
precondition(copyText(buffer) == "one big two\nthree")

sendInput("0")
sendInput("v")
sendInput("w")
precondition(VSGetMode() == VSModeVisual)

var range = VSVisualRange()
precondition(VSGetVisualRange(&range))
precondition(range.startLine == 1)
precondition(range.startColumn == 0)
precondition(range.endColumn == 4)
sendKey("<esc>")

sendInput("G")
sendInput("0")
sendInput("v")
sendInput("k")
precondition(VSGetVisualRange(&range))
precondition(range.startLine == 2)
precondition(range.endLine == 1)
sendKey("<esc>")

let secondBuffer = "".withCString { VSCreateBuffer($0) }
precondition(secondBuffer != nil)
VSActivateBuffer(secondBuffer)
sendInput("i")
"한글 memo".withCString { VSSetText(secondBuffer, $0) }
VSSetCursor(1, Int32("한글 memo".utf8.count))
sendKey("<esc>")
precondition(copyText(secondBuffer) == "한글 memo")

VSActivateBuffer(buffer)
precondition(copyText(buffer) == "one big two\nthree")

let clipBuffer = "line1\nline2".withCString { VSCreateBuffer($0) }
precondition(clipBuffer != nil)
VSActivateBuffer(clipBuffer)
testGetLines = ["Hello, World"]
testGetBlockType = 1
VSSetClipboardGetCallback(testClipboardGet)
sendKey("<esc>")
sendInput("g")
sendInput("g")
sendInput("y")
sendInput("y")
sendInput("P")
precondition(copyText(clipBuffer) == "Hello, World\nline1\nline2")

let charClipBuffer = "line1\nline2".withCString { VSCreateBuffer($0) }
precondition(charClipBuffer != nil)
VSActivateBuffer(charClipBuffer)
testGetLines = ["abc"]
testGetBlockType = 0
sendKey("<esc>")
sendInput("g")
sendInput("g")
sendInput("y")
sendInput("y")
sendInput("P")
precondition(copyText(charClipBuffer) == "abcline1\nline2")

let multilineTest = "xxx".withCString { VSCreateBuffer($0) }
precondition(multilineTest != nil)
VSActivateBuffer(multilineTest)
testGetLines = ["A", "B"]
testGetBlockType = 1
sendKey("<esc>")
sendInput("y")
sendInput("y")
sendInput("P")
precondition(copyText(multilineTest) == "A\nB\nxxx")

VSSetYankCallback(testYank)
let yankBuffer = "alpha\nbeta".withCString { VSCreateBuffer($0) }
precondition(yankBuffer != nil)
VSActivateBuffer(yankBuffer)
sendKey("<esc>")
lastYankOpChar = -1
sendInput("g")
sendInput("g")
sendInput("y")
sendInput("y")
precondition(lastYankOpChar == Int32(UInt8(ascii: "y")))
precondition(lastYankText == "alpha")
lastYankOpChar = -1
sendInput("g")
sendInput("g")
sendInput("d")
sendInput("d")
precondition(lastYankOpChar == Int32(UInt8(ascii: "d")))
precondition(lastYankText == "alpha")
precondition(copyText(yankBuffer) == "beta")

print("VimBridgeCheck passed")

func sendInput(_ input: String) {
    input.withCString { VSInput($0) }
}

func sendKey(_ key: String) {
    key.withCString { VSKey($0) }
}

func copyText(_ buffer: VSBufferRef?) -> String {
    guard let pointer = VSCopyText(buffer) else {
        return ""
    }
    defer { VSFree(pointer) }
    return String(cString: pointer)
}
