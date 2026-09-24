import AppKit

let alwaysOnTopDefaultsKey = "alwaysOnTop"

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var stickyWindows: [StickyWindowController] = []
    private let noteStore = NoteStore()
    private var colorscheme: Colorscheme = .stored()
    private var calendarPreferences = CalendarSettings.stored()
    private var colorMenuItems: [NSMenuItem] = []
    private var showCalendarItem: NSMenuItem?
    private var weekNumberItems: [NSMenuItem] = []
    private var colorWeekendsItem: NSMenuItem?
    private var alwaysOnTopItem: NSMenuItem?
    private var alwaysOnTop: Bool = UserDefaults.standard.bool(forKey: alwaysOnTopDefaultsKey)

    func applicationDidFinishLaunching(_ notification: Notification) {
        VimClipboard.loadDefaults()
        VimClipboard.install()
        installMainMenu()
        if noteStore.notes.isEmpty {
            newSticky(nil)
        } else {
            noteStore.notes.forEach { openSticky($0) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stickyWindows.first { $0.window?.isKeyWindow == true }?.prepareForDeactivation()
        noteStore.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func newSticky(_ sender: Any?) {
        stickyWindows.first { $0.window?.isKeyWindow == true }?.prepareForDeactivation()
        openSticky(noteStore.createNote(), sender: sender)
    }

    private func openSticky(_ note: StickyNote, sender: Any? = nil) {
        let controller = StickyWindowController(
            initialText: note.text,
            colorscheme: colorscheme,
            calendarPreferences: calendarPreferences,
            restoredFrame: note.frame?.rect,
            onTextChange: { [weak self] text in
                self?.noteStore.updateText(text, for: note.id)
            },
            onFrameChange: { [weak self] frame in
                self?.noteStore.updateFrame(frame, for: note.id)
            },
            onClose: { [weak self] controller in
                self?.noteStore.removeNote(withID: note.id)
                self?.stickyWindows.removeAll { $0 === controller }
            }
        )

        stickyWindows.append(controller)
        controller.showWindow(sender)
        controller.setAlwaysOnTop(alwaysOnTop)
        controller.captureFrame()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "VimStickies")
        applicationMenu.addItem(
            withTitle: "About VimStickies",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "Quit VimStickies",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let newItem = fileMenu.addItem(
            withTitle: "New Sticky",
            action: #selector(newSticky(_:)),
            keyEquivalent: "n"
        )
        newItem.target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let clipboardSyncItem = editMenu.addItem(
            withTitle: "Overwrite Clipboard on Delete/Change",
            action: #selector(toggleClipboardSync(_:)),
            keyEquivalent: ""
        )
        clipboardSyncItem.target = self
        clipboardSyncItem.state = VimClipboardState.syncDeletesToClipboard ? .on : .off
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let colorItem = NSMenuItem()
        let colorMenu = NSMenu(title: "Color")
        colorMenuItems = Colorscheme.allCases.map { scheme in
            let item = colorMenu.addItem(
                withTitle: scheme.displayName,
                action: #selector(chooseColorscheme(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = scheme.rawValue
            item.state = scheme == colorscheme ? .on : .off
            return item
        }
        colorItem.submenu = colorMenu
        mainMenu.addItem(colorItem)

        let calendarItem = NSMenuItem()
        let calendarMenu = NSMenu(title: "Calendar")
        let showCalendarItem = calendarMenu.addItem(
            withTitle: "Show Calendar",
            action: #selector(toggleCalendarVisibility(_:)),
            keyEquivalent: ""
        )
        showCalendarItem.target = self
        showCalendarItem.state = calendarPreferences.isVisible ? .on : .off
        self.showCalendarItem = showCalendarItem

        let weekNumberHeader = calendarMenu.addItem(
            withTitle: "Week Numbers",
            action: nil,
            keyEquivalent: ""
        )
        weekNumberHeader.isEnabled = false
        weekNumberItems = CalendarView.WeekMode.allCases.map { mode in
            let item = calendarMenu.addItem(
                withTitle: mode.displayName,
                action: #selector(chooseWeekMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == calendarPreferences.weekMode ? .on : .off
            return item
        }
        calendarMenu.addItem(.separator())
        let colorWeekendsItem = calendarMenu.addItem(
            withTitle: "Color Weekends (Sat Blue / Sun Red)",
            action: #selector(toggleColorWeekends(_:)),
            keyEquivalent: ""
        )
        colorWeekendsItem.target = self
        colorWeekendsItem.state = calendarPreferences.colorWeekends ? .on : .off
        self.colorWeekendsItem = colorWeekendsItem

        calendarItem.submenu = calendarMenu
        mainMenu.addItem(calendarItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let alwaysOnTopItem = windowMenu.addItem(
            withTitle: "Always on Top",
            action: #selector(toggleAlwaysOnTop(_:)),
            keyEquivalent: "f"
        )
        alwaysOnTopItem.keyEquivalentModifierMask = [.command, .option]
        alwaysOnTopItem.target = self
        alwaysOnTopItem.state = alwaysOnTop ? .on : .off
        self.alwaysOnTopItem = alwaysOnTopItem
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func toggleAlwaysOnTop(_ sender: NSMenuItem) {
        alwaysOnTop.toggle()
        UserDefaults.standard.set(alwaysOnTop, forKey: alwaysOnTopDefaultsKey)
        alwaysOnTopItem?.state = alwaysOnTop ? .on : .off
        stickyWindows.forEach { $0.setAlwaysOnTop(alwaysOnTop) }
    }

    @objc private func toggleClipboardSync(_ sender: NSMenuItem) {
        VimClipboardState.syncDeletesToClipboard.toggle()
        UserDefaults.standard.set(
            VimClipboardState.syncDeletesToClipboard,
            forKey: clipboardSyncDefaultsKey
        )
        sender.state = VimClipboardState.syncDeletesToClipboard ? .on : .off
    }

    @objc private func toggleCalendarVisibility(_ sender: NSMenuItem) {
        calendarPreferences.isVisible.toggle()
        showCalendarItem?.state = calendarPreferences.isVisible ? .on : .off
        CalendarSettings.persist(calendarPreferences)
        stickyWindows.forEach { $0.applyCalendarPreferences(calendarPreferences) }
    }

    @objc private func chooseWeekMode(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let mode = CalendarView.WeekMode(rawValue: raw)
        else {
            return
        }
        calendarPreferences.weekMode = mode
        weekNumberItems.forEach {
            $0.state = $0.representedObject as? String == raw ? .on : .off
        }
        CalendarSettings.persist(calendarPreferences)
        stickyWindows.forEach { $0.applyCalendarPreferences(calendarPreferences) }
    }

    @objc private func toggleColorWeekends(_ sender: NSMenuItem) {
        calendarPreferences.colorWeekends.toggle()
        colorWeekendsItem?.state = calendarPreferences.colorWeekends ? .on : .off
        CalendarSettings.persist(calendarPreferences)
        stickyWindows.forEach { $0.applyCalendarPreferences(calendarPreferences) }
    }

    @objc private func chooseColorscheme(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let scheme = Colorscheme(rawValue: raw)
        else {
            return
        }

        colorscheme = scheme
        scheme.persist()
        stickyWindows.forEach { $0.applyColorscheme(scheme) }
        colorMenuItems.forEach { $0.state = $0.representedObject as? String == raw ? .on : .off }
    }
}
