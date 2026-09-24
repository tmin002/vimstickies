import AppKit

struct StickyColors {
    let body: NSColor
    let bar: NSColor
    let ink: NSColor
}

enum Colorscheme: String, CaseIterable {
    case yellow
    case green
    case blue
    case pink
    case orange
    case purple
    case gray

    static let storageKey = "colorscheme"

    var displayName: String {
        switch self {
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .pink: "Pink"
        case .orange: "Orange"
        case .purple: "Purple"
        case .gray: "Gray"
        }
    }

    var colors: StickyColors {
        switch self {
        case .yellow:
            StickyColors(
                body: NSColor(calibratedRed: 1.00, green: 0.96, blue: 0.60, alpha: 1),
                bar: NSColor(calibratedRed: 1.00, green: 0.90, blue: 0.08, alpha: 1),
                ink: NSColor(calibratedRed: 0.28, green: 0.21, blue: 0.10, alpha: 1)
            )
        case .green:
            StickyColors(
                body: NSColor(calibratedRed: 0.78, green: 0.90, blue: 0.79, alpha: 1),
                bar: NSColor(calibratedRed: 0.65, green: 0.84, blue: 0.65, alpha: 1),
                ink: NSColor(calibratedRed: 0.09, green: 0.27, blue: 0.14, alpha: 1)
            )
        case .blue:
            StickyColors(
                body: NSColor(calibratedRed: 0.73, green: 0.87, blue: 0.98, alpha: 1),
                bar: NSColor(calibratedRed: 0.56, green: 0.79, blue: 0.98, alpha: 1),
                ink: NSColor(calibratedRed: 0.07, green: 0.22, blue: 0.40, alpha: 1)
            )
        case .pink:
            StickyColors(
                body: NSColor(calibratedRed: 0.97, green: 0.73, blue: 0.82, alpha: 1),
                bar: NSColor(calibratedRed: 0.96, green: 0.56, blue: 0.69, alpha: 1),
                ink: NSColor(calibratedRed: 0.42, green: 0.12, blue: 0.25, alpha: 1)
            )
        case .orange:
            StickyColors(
                body: NSColor(calibratedRed: 1.00, green: 0.88, blue: 0.70, alpha: 1),
                bar: NSColor(calibratedRed: 1.00, green: 0.80, blue: 0.50, alpha: 1),
                ink: NSColor(calibratedRed: 0.45, green: 0.26, blue: 0.08, alpha: 1)
            )
        case .purple:
            StickyColors(
                body: NSColor(calibratedRed: 0.88, green: 0.75, blue: 0.91, alpha: 1),
                bar: NSColor(calibratedRed: 0.81, green: 0.58, blue: 0.85, alpha: 1),
                ink: NSColor(calibratedRed: 0.30, green: 0.14, blue: 0.40, alpha: 1)
            )
        case .gray:
            StickyColors(
                body: NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.93, alpha: 1),
                bar: NSColor(calibratedRed: 0.88, green: 0.88, blue: 0.88, alpha: 1),
                ink: NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.22, alpha: 1)
            )
        }
    }

    static func stored() -> Colorscheme {
        guard
            let raw = UserDefaults.standard.string(forKey: storageKey),
            let scheme = Colorscheme(rawValue: raw)
        else {
            return .yellow
        }
        return scheme
    }

    func persist() {
        UserDefaults.standard.set(rawValue, forKey: Colorscheme.storageKey)
    }
}