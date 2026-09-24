import AppKit

let size = 1024

let bgTop = CGColor(red: 0.965, green: 0.953, blue: 0.933, alpha: 1)
let bgBottom = CGColor(red: 0.882, green: 0.859, blue: 0.824, alpha: 1)
let stickyTop = CGColor(red: 1.0, green: 0.976, blue: 0.706, alpha: 1)
let stickyBottom = CGColor(red: 1.0, green: 0.867, blue: 0.173, alpha: 1)
let foldColor = CGColor(red: 0.953, green: 0.722, blue: 0.118, alpha: 1)
let ink = CGColor(red: 0.16, green: 0.12, blue: 0.09, alpha: 1)

func makeContext() -> CGContext {
    let ctx = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return ctx
}

func fillBackground(_ ctx: CGContext) {
    let colors = [bgTop, bgBottom] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: size / 2, y: size), end: CGPoint(x: size / 2, y: 0), options: [])
}

func stickyPath(in rect: CGRect) -> CGPath {
    let r = min(rect.width, rect.height) * 0.03
    let path = CGMutablePath()
    path.addRoundedRect(in: rect, cornerWidth: r, cornerHeight: r)
    return path
}

func foldPath(in rect: CGRect) -> CGPath {
    let side = rect.width * 0.22
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX - side, y: rect.maxY - side))
    path.closeSubpath()
    return path
}

func drawSticky(_ ctx: CGContext, in rect: CGRect, rotation: CGFloat, fold: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: rect.midX, y: rect.midY)
    ctx.rotate(by: rotation * .pi / 180)
    ctx.translateBy(x: -rect.midX, y: -rect.midY)

    ctx.setShadow(offset: CGSize(width: 0, height: -34), blur: 60, color: ink.withAlphaComponent(0.35))
    ctx.setFillColor(stickyBottom)
    ctx.addPath(stickyPath(in: rect))
    ctx.fillPath()

    let colors = [stickyTop, stickyBottom] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.setShadow(offset: .zero, blur: 0)
    ctx.saveGState()
    ctx.addPath(stickyPath(in: rect))
    ctx.clip()

    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.minX, y: rect.minY),
        options: []
    )

    if fold {
        ctx.setFillColor(foldColor)
        ctx.addPath(foldPath(in: rect))
        ctx.fillPath()
    }

    ctx.setStrokeColor(ink.withAlphaComponent(0.10))
    ctx.setLineWidth(3)
    ctx.addPath(foldPath(in: rect))
    ctx.strokePath()

    ctx.restoreGState()

    ctx.setStrokeColor(ink.withAlphaComponent(0.16))
    ctx.setLineWidth(2.5)
    ctx.addPath(stickyPath(in: rect))
    ctx.strokePath()

    ctx.restoreGState()
}

func drawText(_ ctx: CGContext, string: String, fontSize: CGFloat, weight: NSFont.Weight, at center: CGPoint, color: CGColor) {
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color)!,
    ]
    let text = NSAttributedString(string: string, attributes: attrs)
    let bounds = text.boundingRect(with: NSSize(width: 10000, height: 10000), options: [.usesLineFragmentOrigin])
    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.translateBy(x: center.x - bounds.midX, y: center.y - bounds.midY)
    text.draw(at: .zero)
    ctx.restoreGState()
}

extension CGColor {
    func withAlphaComponent(_ value: CGFloat) -> CGColor {
        copy(alpha: value) ?? self
    }
}

func renderPNG(_ ctx: CGContext, name: String) {
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    let url = URL(fileURLWithPath: "Tools/IconCandidates/\(name).png")
    try! data.write(to: url)
    print("wrote \(url.path)")
}

func renderIcon(_ name: String, rotation: CGFloat, fold: Bool, cursor: Bool, letter: String) -> CGImage {
    let ctx = makeContext()
    let graphicsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.current = previous }
    fillBackground(ctx)

    let noteRect = CGRect(x: 172, y: 168, width: 680, height: 680)

    if name == "icon_d_stack" {
        drawSticky(ctx, in: noteRect.offsetBy(dx: 70, dy: 60), rotation: 7, fold: false)
    }

    drawSticky(ctx, in: noteRect, rotation: rotation, fold: fold)

    let center = CGPoint(x: noteRect.midX, y: noteRect.midY)

    if cursor {
        let barW: CGFloat = 46
        let cursorRect = CGRect(
            x: center.x - 185,
            y: center.y - 225,
            width: barW,
            height: 450
        )
        ctx.setFillColor(ink)
        ctx.fill(cursorRect)
        drawText(ctx, string: letter, fontSize: 430, weight: .black, at: CGPoint(x: center.x + 16, y: center.y + 2), color: ink)
    } else {
        drawText(ctx, string: letter, fontSize: 440, weight: .black, at: center, color: ink)
    }

    return ctx.makeImage()!
}

let candidates: [(String, CGFloat, Bool, Bool, String)] = [
    ("icon_a_classic", 0, true, false, "N"),
    ("icon_b_cursor", 4, true, true, "N"),
    ("icon_c_flat", 0, false, false, "N"),
    ("icon_d_stack", 0, true, false, "N"),
]

for (name, rotation, fold, cursor, letter) in candidates {
    let image = renderIcon(name, rotation: rotation, fold: fold, cursor: cursor, letter: letter)
    let ctx = makeContext()
    let graphicsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = graphicsContext
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    renderPNG(ctx, name: name)
    NSGraphicsContext.current = previous
}

func resized(_ image: CGImage, to dimension: Int) -> CGImage {
    let ctx = CGContext(
        data: nil,
        width: dimension,
        height: dimension,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

let buildDir = "Tools/build"
try! FileManager.default.createDirectory(atPath: "\(buildDir)/VimStickies.iconset", withIntermediateDirectories: true)
let master = renderIcon("icon_d_stack", rotation: 0, fold: true, cursor: false, letter: "N")
let slots: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
for (dimension, name) in slots {
    writePNG(resized(master, to: dimension), to: "\(buildDir)/VimStickies.iconset/\(name)")
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "\(buildDir)/VimStickies.iconset", "-o", "\(buildDir)/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print("iconutil exit=\(iconutil.terminationStatus) -> \(buildDir)/AppIcon.icns")