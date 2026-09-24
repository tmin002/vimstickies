import AppKit

enum CalendarSettings {
    static let visibleKey = "calendarVisible"
    static let weekModeKey = "calendarWeekMode"
    static let weekendsKey = "calendarWeekends"

    static func stored() -> CalendarView.Preferences {
        let defaults = UserDefaults.standard
        let visible = defaults.object(forKey: visibleKey) as? Bool ?? true
        let modeRaw = defaults.string(forKey: weekModeKey)
            ?? CalendarView.WeekMode.week.rawValue
        let mode = CalendarView.WeekMode(rawValue: modeRaw) ?? .week
        let weekends = defaults.object(forKey: weekendsKey) as? Bool ?? true
        return CalendarView.Preferences(
            isVisible: visible,
            weekMode: mode,
            colorWeekends: weekends
        )
    }

    static func persist(_ preferences: CalendarView.Preferences) {
        let defaults = UserDefaults.standard
        defaults.set(preferences.isVisible, forKey: visibleKey)
        defaults.set(preferences.weekMode.rawValue, forKey: weekModeKey)
        defaults.set(preferences.colorWeekends, forKey: weekendsKey)
    }
}

@MainActor
final class CalendarView: NSView {
    enum WeekMode: String, CaseIterable {
        case week
        case month
        case off

        var displayName: String {
            switch self {
            case .week: "@N"
            case .month: "9-1"
            case .off: "Off"
            }
        }
    }

    struct Preferences {
        var isVisible = true
        var weekMode: WeekMode = .week
        var colorWeekends = true
    }

    override var isFlipped: Bool { true }

    private static let leftInset: CGFloat = 7
    private static let headerHeight: CGFloat = 18
    private static let inputFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold)
    private static let inputFontWidth = inputFont.maximumAdvancement.width
    private static let lineHeight = ceil(inputFont.ascender - inputFont.descender + inputFont.leading)
    private static let dayWidth: CGFloat = inputFontWidth * 3
    private static let weekWidth: CGFloat = inputFontWidth * 3
    private static let buttonFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
    private static let titleFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .bold)
    private static let weekendBlue = NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1)
    private static let weekendRed = NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1)
    private static let isoWeekCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    private let calendar = Calendar.current
    private var background = NSColor.white
    private var ink = NSColor.black
    private var preferences = Preferences()

    private var year: Int
    private var month: Int
    private var weekdayOfFirst = 0
    private var daysInMonth = 0
    private var rows = 0
    private var todayDay = 0
    private var weekLabels: [String] = []
    private var isHovering = false
    private var trackingArea: NSTrackingArea?

    private let prevButton: NSButton
    private let nextButton: NSButton
    private let yearMonthButton: NSButton
    private let todayButton: NSButton

    var onGeometryChange: (() -> Void)?

    override init(frame frameRect: NSRect) {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        year = now.year ?? 2026
        month = now.month ?? 1

        let make = { (title: String, action: Selector) -> NSButton in
            let button = NSButton(title: title, target: nil, action: action)
            button.isBordered = false
            button.font = CalendarView.buttonFont
            return button
        }
        prevButton = make("▲", #selector(showPreviousMonth(_:)))
        nextButton = make("▼", #selector(showNextMonth(_:)))
        yearMonthButton = make("2026-09", #selector(showYearMonthMenu(_:)))
        todayButton = make("Today", #selector(showToday(_:)))

        super.init(frame: frameRect)

        configure()
        recomputeMonth()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var neededHeight: CGFloat {
        Self.headerHeight + Self.lineHeight + CGFloat(rows) * Self.lineHeight
    }

    func applyColors(background: NSColor, ink: NSColor) {
        self.background = background
        self.ink = ink
        styleButtons()
        needsDisplay = true
    }

    func applyPreferences(_ newPreferences: Preferences) {
        preferences = newPreferences
        recomputeMonth()
        onGeometryChange?()
        needsDisplay = true
    }

    func clockTick() {
        recomputeMonth()
        needsDisplay = true
    }

    @objc private func showPreviousMonth(_ sender: Any?) {
        shiftMonth(by: -1)
    }

    @objc private func showNextMonth(_ sender: Any?) {
        shiftMonth(by: 1)
    }

    @objc private func showToday(_ sender: Any?) {
        let now = calendar.dateComponents([.year, .month], from: Date())
        year = now.year ?? year
        month = now.month ?? month
        recomputeMonth()
        onGeometryChange?()
        needsDisplay = true
    }

    @objc private func chooseYear(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? Int else {
            return
        }
        year = selection
        recomputeMonth()
        onGeometryChange?()
        needsDisplay = true
    }

    @objc private func chooseMonth(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? Int else {
            return
        }
        month = selection
        recomputeMonth()
        onGeometryChange?()
        needsDisplay = true
    }

    @objc private func showYearMonthMenu(_ sender: Any?) {
        let menu = NSMenu()
        let yearHeader = menu.addItem(withTitle: "Year", action: nil, keyEquivalent: "")
        yearHeader.isEnabled = false
        for candidate in (year - 5)...(year + 5) {
            let item = menu.addItem(
                withTitle: "\(candidate)",
                action: #selector(chooseYear(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = candidate
            item.state = candidate == year ? .on : .off
        }
        menu.addItem(.separator())
        let monthHeader = menu.addItem(withTitle: "Month", action: nil, keyEquivalent: "")
        monthHeader.isEnabled = false
        for candidate in 1...12 {
            let item = menu.addItem(
                withTitle: "\(candidate)월",
                action: #selector(chooseMonth(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = candidate
            item.state = candidate == month ? .on : .off
        }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: yearMonthButton.frame.minX, y: yearMonthButton.frame.maxY),
            in: self
        )
    }

    override func layout() {
        super.layout()
        positionHeaderButtons()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        syncHover()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        syncHover()
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        if event.scrollingDeltaY < 0 {
            shiftMonth(by: 1)
        } else if event.scrollingDeltaY > 0 {
            shiftMonth(by: -1)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawWeekdaysAndDays()
    }

    private func configure() {
        prevButton.target = self
        nextButton.target = self
        yearMonthButton.target = self
        todayButton.target = self
        prevButton.isHidden = true
        nextButton.isHidden = true
        yearMonthButton.isHidden = true
        todayButton.isHidden = true
        addSubview(prevButton)
        addSubview(nextButton)
        addSubview(yearMonthButton)
        addSubview(todayButton)
        styleButtons()
    }

    private func styleButtons() {
        let black: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.black,
            .font: Self.buttonFont
        ]
        prevButton.attributedTitle = NSAttributedString(string: "▲", attributes: black)
        nextButton.attributedTitle = NSAttributedString(string: "▼", attributes: black)
        yearMonthButton.attributedTitle = NSAttributedString(
            string: yearMonthButton.title,
            attributes: [
                .foregroundColor: NSColor.black,
                .font: Self.titleFont
            ]
        )
        todayButton.attributedTitle = NSAttributedString(
            string: "Today",
            attributes: [
                .foregroundColor: NSColor.black,
                .font: Self.buttonFont,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )
    }

    private func positionHeaderButtons() {
        let headerTop: CGFloat = 1
        let height = Self.headerHeight - 2
        prevButton.frame = NSRect(x: 6, y: headerTop, width: 16, height: height)
        nextButton.frame = NSRect(x: 24, y: headerTop, width: 16, height: height)

        yearMonthButton.title = String(format: "%d-%02d", year, month)
        styleButtons()
        yearMonthButton.sizeToFit()
        var titleFrame = yearMonthButton.frame
        titleFrame.size.height = height
        titleFrame.origin = NSPoint(
            x: 46,
            y: headerTop + (height - titleFrame.height) / 2
        )
        yearMonthButton.frame = titleFrame

        todayButton.sizeToFit()
        var todayFrame = todayButton.frame
        todayFrame.size.height = height
        todayFrame.origin = NSPoint(
            x: titleFrame.maxX + 8,
            y: headerTop + (height - todayFrame.height) / 2
        )
        todayButton.frame = todayFrame

        syncHover()
    }

    private func syncHover() {
        prevButton.isHidden = !isHovering
        nextButton.isHidden = !isHovering
        yearMonthButton.isHidden = !isHovering
        todayButton.isHidden = !isHovering || isViewingCurrentMonth
    }

    private var isViewingCurrentMonth: Bool {
        let now = calendar.dateComponents([.year, .month], from: Date())
        return now.year == year && now.month == month
    }

    private func shiftMonth(by delta: Int) {
        var newMonth = month + delta
        var newYear = year
        while newMonth > 12 {
            newMonth -= 12
            newYear += 1
        }
        while newMonth < 1 {
            newMonth += 12
            newYear -= 1
        }
        year = newYear
        month = newMonth
        recomputeMonth()
        onGeometryChange?()
        needsDisplay = true
    }

    private func recomputeMonth() {
        guard
            let first = calendar.date(
                from: DateComponents(year: year, month: month, day: 1)
            )
        else {
            return
        }

        weekdayOfFirst = (calendar.component(.weekday, from: first) + 5) % 7
        daysInMonth = calendar.range(of: .day, in: .month, for: first)?.count ?? 0
        rows = (weekdayOfFirst + daysInMonth + 6) / 7
        weekLabels = (0..<rows).map { rowIndex in
            switch preferences.weekMode {
            case .off:
                return ""
            case .week:
                let offset = rowIndex * 7 - weekdayOfFirst
                guard let monday = calendar.date(byAdding: .day, value: offset, to: first) else {
                    return ""
                }
                return "@\(Self.isoWeekCalendar.component(.weekOfYear, from: monday))"
            case .month:
                let offset = rowIndex * 7 - weekdayOfFirst
                guard let monday = calendar.date(byAdding: .day, value: offset, to: first) else {
                    return ""
                }
                let parts = calendar.dateComponents([.month, .weekOfMonth], from: monday)
                return "\(parts.month ?? 0)-\(parts.weekOfMonth ?? 0)"
            }
        }
        todayDay = calendar.component(.day, from: Date())
        positionHeaderButtons()
    }

    private var weekLabelWidth: CGFloat {
        preferences.weekMode == .off ? 0 : Self.weekWidth
    }

    private func gridStartX() -> CGFloat {
        Self.leftInset
    }

    private func drawWeekdaysAndDays() {
        let startX = gridStartX()
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        let lettersY = Self.headerHeight

        for column in 0..<7 {
            let rect = NSRect(
                x: startX + CGFloat(column) * Self.dayWidth,
                y: lettersY,
                width: Self.dayWidth,
                height: Self.lineHeight
            )
            let color: NSColor
            if preferences.colorWeekends {
                color = Self.colorForColumn(column) ?? .black
            } else {
                color = .black
            }
            drawText(
                letters[column],
                in: rect,
                font: Self.inputFont,
                color: color,
                alignRight: true
            )
        }

        var day = 1
        while day <= daysInMonth {
            let index = weekdayOfFirst + day - 1
            let rect = NSRect(
                x: startX + CGFloat(index % 7) * Self.dayWidth,
                y: lettersY + Self.lineHeight + CGFloat(index / 7) * Self.lineHeight,
                width: Self.dayWidth,
                height: Self.lineHeight
            )
            drawDay(day, in: rect, column: index % 7)
            day += 1
        }

        if weekLabelWidth > 0 {
            for rowIndex in 0..<rows {
                let label = weekLabels[rowIndex]
                guard !label.isEmpty else {
                    continue
                }
                let rect = NSRect(
                    x: startX + Self.dayWidth * 7,
                    y: lettersY + Self.lineHeight + CGFloat(rowIndex) * Self.lineHeight,
                    width: Self.weekWidth,
                    height: Self.lineHeight
                )
                drawText(
                    " \(label)",
                    in: rect,
                    font: Self.inputFont,
                    color: .black,
                    alignRight: true
                )
            }
        }
    }

    private func drawDay(_ day: Int, in rect: NSRect, column: Int) {
        let isToday = isViewingCurrentMonth && day == todayDay
        let text = String(format: "%02d", day)

        if isToday {
            let fill = Self.colorForColumn(column) ?? .black
            let path = NSBezierPath(
                roundedRect: rect.insetBy(dx: 1, dy: 1),
                xRadius: 3,
                yRadius: 3
            )
            fill.setFill()
            path.fill()
            drawText(
                text,
                in: rect,
                font: Self.inputFont,
                color: background,
                alignRight: true
            )
            return
        }

        let color = preferences.colorWeekends
            ? (Self.colorForColumn(column) ?? .black)
            : .black
        drawText(text, in: rect, font: Self.inputFont, color: color, alignRight: true)
    }

    private static func colorForColumn(_ column: Int) -> NSColor? {
        switch column {
        case 5: weekendBlue
        case 6: weekendRed
        default: nil
        }
    }

    private func drawText(
        _ string: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignRight: Bool = false
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let size = (string as NSString).size(withAttributes: attributes)
        var target = rect
        if alignRight {
            target.origin.x = rect.maxX - size.width
            target.size.width = size.width
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        NSAttributedString(
            string: string,
            attributes: attributes.merging(
                [.paragraphStyle: paragraph],
                uniquingKeysWith: { first, _ in first }
            )
        ).draw(in: target)
    }
}