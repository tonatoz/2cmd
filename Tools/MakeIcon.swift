import AppKit

// Renders the app icon. No external tooling: AppKit draws the artwork, `iconutil`
// (Command Line Tools) packs the PNGs into an .icns.
//
//   swiftc Tools/MakeIcon.swift -o .build/make-icon
//   .build/make-icon --iconset .build/AppIcon.iconset
//   .build/make-icon --size 512 --out preview.png
//
// The artwork mirrors what the app does: the canvas is split left/right, blue for the
// left ⌘ and red for the right ⌘, with a white ⌘ sitting on the seam.

struct Palette {
    /// Left ⌘.
    static let left = NSColor(srgbRed: 0.12, green: 0.42, blue: 0.95, alpha: 1)
    static let leftDeep = NSColor(srgbRed: 0.06, green: 0.26, blue: 0.72, alpha: 1)
    /// Right ⌘.
    static let right = NSColor(srgbRed: 0.91, green: 0.24, blue: 0.31, alpha: 1)
    static let rightDeep = NSColor(srgbRed: 0.68, green: 0.10, blue: 0.20, alpha: 1)
}

enum IconRenderer {
    static func render(size: CGFloat) -> NSBitmapImageRep {
        let pixels = Int(size)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            fatalError("cannot allocate bitmap")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.setShouldAntialias(true)
        draw(canvas: size)
        NSGraphicsContext.current?.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func draw(canvas: CGFloat) {
        // macOS app icons leave a margin around the body and use a large corner radius.
        let inset = canvas * 0.0977
        let body = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
        let radius = body.width * 0.2237

        drawSplitBackground(body: body, radius: radius)
        drawCommand(in: body, scale: 0.52)
        drawGloss(body: body, radius: radius)
    }

    private static func drawSplitBackground(body: CGRect, radius: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).addClip()

        let half = CGRect(x: body.minX, y: body.minY, width: body.width / 2, height: body.height)
        NSGradient(starting: Palette.left, ending: Palette.leftDeep)?.draw(in: half, angle: -90)
        NSGradient(starting: Palette.right, ending: Palette.rightDeep)?
            .draw(in: half.offsetBy(dx: body.width / 2, dy: 0), angle: -90)

        NSGraphicsContext.restoreGraphicsState()
    }

    /// Subtle top highlight, the way macOS icons catch light.
    private static func drawGloss(body: CGRect, radius: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius).addClip()
        NSGradient(
            starting: NSColor(white: 1, alpha: 0.20),
            ending: NSColor(white: 1, alpha: 0)
        )?.draw(
            in: CGRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2),
            angle: -90
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The ⌘ glyph, drawn as text so no image asset is needed at build time.
    private static func drawCommand(in rect: CGRect, scale: CGFloat) {
        draw("⌘", attributes: [
            .font: NSFont.systemFont(ofSize: rect.height * scale, weight: .medium),
            .foregroundColor: NSColor.white,
        ], centeredIn: rect)
    }

    private static func draw(
        _ string: String,
        attributes: [NSAttributedString.Key: Any],
        centeredIn rect: CGRect
    ) {
        let text = NSAttributedString(string: string, attributes: attributes)
        let bounds = text.boundingRect(with: .zero, options: .usesLineFragmentOrigin)
        text.draw(at: CGPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
    }
}

// MARK: - Command line

func value(for flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag),
          CommandLine.arguments.index(after: index) < CommandLine.arguments.endIndex
    else { return nil }
    return CommandLine.arguments[CommandLine.arguments.index(after: index)]
}

func writePNG(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("cannot encode png")
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
    } catch {
        fatalError("cannot write \(path): \(error)")
    }
}

if let iconset = value(for: "--iconset") {
    // The set of images iconutil expects for a complete .icns.
    let sizes: [(name: String, pixels: CGFloat)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
    for size in sizes {
        writePNG(IconRenderer.render(size: size.pixels), to: "\(iconset)/\(size.name).png")
    }
    print("wrote \(sizes.count) images to \(iconset)")
} else {
    let size = CGFloat(Int(value(for: "--size") ?? "512") ?? 512)
    let out = value(for: "--out") ?? "icon.png"
    writePNG(IconRenderer.render(size: size), to: out)
    print("wrote \(out)")
}
