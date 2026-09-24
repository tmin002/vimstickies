import AppKit

struct StickyNote: Codable, Identifiable {
    let id: UUID
    var text: String
    var frame: StoredWindowFrame?
}

struct StoredWindowFrame: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(_ rect: NSRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var rect: NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }
}

@MainActor
final class NoteStore {
    private(set) var notes: [StickyNote] = []

    private let fileURL: URL
    private var pendingSave: DispatchWorkItem?

    init(fileManager: FileManager = .default) {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let directory = applicationSupport.appendingPathComponent(
            "VimStickies",
            isDirectory: true
        )
        fileURL = directory.appendingPathComponent("notes.json")

        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        load()
    }

    func createNote() -> StickyNote {
        let note = StickyNote(id: UUID(), text: "", frame: nil)
        notes.append(note)
        scheduleSave()
        return note
    }

    func updateText(_ text: String, for id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else {
            return
        }
        notes[index].text = text
        scheduleSave()
    }

    func updateFrame(_ frame: NSRect, for id: UUID) {
        let storedFrame = StoredWindowFrame(frame)
        guard let index = notes.firstIndex(where: { $0.id == id }),
              notes[index].frame != storedFrame else {
            return
        }
        notes[index].frame = storedFrame
        scheduleSave()
    }

    func removeNote(withID id: UUID) {
        notes.removeAll { $0.id == id }
        scheduleSave()
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(notes) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([StickyNote].self, from: data) else {
            return
        }
        notes = decoded
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }
}
