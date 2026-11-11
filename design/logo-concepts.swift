// Logo concepts for S1 Reader: "stage" + "1" + a forum's own furniture.
// Renders 1024×1024 PNGs so the ideas can be compared before one is wired
// into the asset catalog.
//
//   swift design/logo-concepts.swift <output directory>
import AppKit

let size: CGFloat = 1024
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/logo"

// MARK: - Pieces

func makeContext() -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Flip so y grows downwards, like the numbers below read.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    return ctx
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// The app's red, warmed up: the icons sit next to S1's own orange-red.
func paintField(_ ctx: CGContext, top: UInt32, bottom: UInt32) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(top), color(bottom)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 180, y: 0),
        end: CGPoint(x: size - 120, y: size),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
}

func radialGlow(_ ctx: CGContext, center: CGPoint, radius: CGFloat, alpha: CGFloat) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0xFFFFFF, alpha), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        gradient, startCenter: center, startRadius: 0,
        endCenter: center, endRadius: radius, options: []
    )
}

func polygon(_ ctx: CGContext, _ points: [CGPoint]) {
    ctx.beginPath()
    ctx.move(to: points[0])
    for point in points.dropFirst() { ctx.addLine(to: point) }
    ctx.closePath()
    ctx.fillPath()
}

func numeral(_ ctx: CGContext, _ text: String, fontSize: CGFloat, centerX: CGFloat, baseline: CGFloat, color fill: CGColor) {
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: fill)!])
    let bounds = attributed.size()
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.current = graphics
    attributed.draw(at: NSPoint(x: centerX - bounds.width / 2, y: size - baseline))
    NSGraphicsContext.restoreGraphicsState()
}

func write(_ ctx: CGContext, name: String) {
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    let data = rep.representation(using: .png, properties: [:])!
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
    do {
        try data.write(to: url)
        print(url.path)
    } catch {
        print("could not write \(url.path): \(error)")
        exit(1)
    }
}

// MARK: - A. 聚光灯下的一楼
// A light cone from the flies, the numeral standing on the floor rule that
// separates two posts. Reads as "stage" and as "floor 1" at once.

func conceptSpotlight() -> CGContext {
    let ctx = makeContext()
    paintField(ctx, top: 0xE4644E, bottom: 0xA6241D)
    radialGlow(ctx, center: CGPoint(x: 470, y: 300), radius: 620, alpha: 0.18)

    // The beam: widest at the stage floor, narrow where the lamp hangs.
    ctx.setFillColor(color(0xFFFFFF, 0.13))
    polygon(ctx, [CGPoint(x: 452, y: 60), CGPoint(x: 572, y: 60), CGPoint(x: 806, y: 900), CGPoint(x: 218, y: 900)])
    ctx.setFillColor(color(0xFFFFFF, 0.10))
    polygon(ctx, [CGPoint(x: 486, y: 60), CGPoint(x: 538, y: 60), CGPoint(x: 660, y: 900), CGPoint(x: 364, y: 900)])

    // Curtain slivers framing the proscenium.
    ctx.setFillColor(color(0x7A1512, 0.35))
    for originX in [96.0, 892.0] as [CGFloat] {
        let rect = CGRect(x: originX, y: 120, width: 36, height: 760)
        let path = CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)
        ctx.addPath(path); ctx.fillPath()
    }

    numeral(ctx, "1", fontSize: 560, centerX: 512, baseline: 790, color: color(0xFFFFFF))

    // The floor rule, with the small gaps a floor separator has.
    ctx.setFillColor(color(0xFFFFFF, 0.92))
    ctx.fill(CGRect(x: 306, y: 806, width: 412, height: 26))
    ctx.setFillColor(color(0xFFFFFF, 0.35))
    ctx.fill(CGRect(x: 306, y: 862, width: 148, height: 14))
    ctx.fill(CGRect(x: 570, y: 862, width: 148, height: 14))
    return ctx
}

// MARK: - B. 幕布
// Two drapes pulled aside, the 1 standing between them on the stage.

func conceptCurtain() -> CGContext {
    let ctx = makeContext()
    paintField(ctx, top: 0x5B1218, bottom: 0x2A0A0E)
    radialGlow(ctx, center: CGPoint(x: 512, y: 560), radius: 520, alpha: 0.20)

    // Drapes: quarter arcs from each top corner.
    ctx.setFillColor(color(0x8E1F22, 1))
    ctx.move(to: CGPoint(x: 0, y: 0))
    ctx.addLine(to: CGPoint(x: 300, y: 0))
    ctx.addQuadCurve(to: CGPoint(x: 150, y: 640), control: CGPoint(x: 300, y: 470))
    ctx.addLine(to: CGPoint(x: 0, y: 700))
    ctx.closePath()
    ctx.fillPath()
    ctx.move(to: CGPoint(x: size, y: 0))
    ctx.addLine(to: CGPoint(x: size - 300, y: 0))
    ctx.addQuadCurve(to: CGPoint(x: size - 150, y: 640), control: CGPoint(x: size - 300, y: 470))
    ctx.addLine(to: CGPoint(x: size, y: 700))
    ctx.closePath()
    ctx.fillPath()
    // Fold shadow.
    ctx.setFillColor(color(0xFFFFFF, 0.06))
    ctx.move(to: CGPoint(x: 250, y: 0))
    ctx.addQuadCurve(to: CGPoint(x: 120, y: 560), control: CGPoint(x: 236, y: 400))
    ctx.addLine(to: CGPoint(x: 170, y: 560))
    ctx.addQuadCurve(to: CGPoint(x: 300, y: 0), control: CGPoint(x: 286, y: 380))
    ctx.closePath()
    ctx.fillPath()

    numeral(ctx, "1", fontSize: 600, centerX: 512, baseline: 800, color: color(0xFFF3E9))

    // Stage floor: a thin lit edge.
    ctx.setFillColor(color(0xFFD9A0, 0.9))
    ctx.fill(CGRect(x: 320, y: 820, width: 384, height: 18))
    return ctx
}

// MARK: - C. 帖子气泡
// The forum's unit is a post: a bubble whose tail is also the 1's serif.

func conceptBubble() -> CGContext {
    let ctx = makeContext()
    paintField(ctx, top: 0xD9523D, bottom: 0x8E1B16)
    radialGlow(ctx, center: CGPoint(x: 512, y: 430), radius: 560, alpha: 0.14)

    let bubble = CGRect(x: 176, y: 196, width: 672, height: 560)
    let path = CGMutablePath()
    path.addRoundedRect(in: bubble, cornerWidth: 132, cornerHeight: 132)
    ctx.addPath(path)
    ctx.setFillColor(color(0xFFFFFF, 0.16))
    ctx.fillPath()
    ctx.addPath(path)
    ctx.setStrokeColor(color(0xFFFFFF, 0.55))
    ctx.setLineWidth(18)
    ctx.strokePath()

    // Tail, pointing down-left like a reply arrow.
    ctx.setFillColor(color(0xFFFFFF, 0.16))
    polygon(ctx, [CGPoint(x: 330, y: 740), CGPoint(x: 470, y: 740), CGPoint(x: 300, y: 878)])

    numeral(ctx, "1", fontSize: 520, centerX: 512, baseline: 690, color: color(0xFFFFFF))
    return ctx
}

// MARK: - D. 台阶 / 楼层
// The forum's furniture is the floor list: three post rows, each shorter than
// the one below, climbing like a stage staircase. The 1 stands on the top step.

func conceptSteps(flip: Bool) -> CGContext {
    let ctx = makeContext()
    paintField(ctx, top: 0xE4644E, bottom: 0x9C1F1A)
    radialGlow(ctx, center: CGPoint(x: flip ? 680 : 344, y: 300), radius: 620, alpha: 0.16)

    // Bottom to top: the row gets shorter as you climb.
    let rows: [(y: CGFloat, left: CGFloat, right: CGFloat, alpha: CGFloat)] = [
        (760, 96, 928, 0.30),
        (628, 200, 928, 0.55),
        (496, 304, 928, 0.95),
    ]
    for row in rows {
        let left = flip ? size - row.right : row.left
        let width = row.right - row.left
        let rect = CGRect(x: left, y: row.y, width: width, height: 92)
        let path = CGPath(roundedRect: rect, cornerWidth: 30, cornerHeight: 30, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(color(0xFFFFFF, row.alpha))
        ctx.fillPath()

        // The two lines of type every post row has.
        let contentLeft = left + 44
        ctx.setFillColor(color(0x9C1F1A, 0.55 * row.alpha))
        ctx.fill(CGRect(x: contentLeft, y: row.y + 22, width: 224, height: 16))
        ctx.fill(CGRect(x: contentLeft, y: row.y + 54, width: 132, height: 12))
    }

    let centerX: CGFloat = flip ? 300 : 724
    numeral(ctx, "1", fontSize: 420, centerX: centerX, baseline: 470, color: color(0xFFFFFF))
    return ctx
}

// MARK: - E. 一楼立在楼层堆上
// The stage beam behind, the 1 standing on the floor rule, and two more rows
// beneath it: the mark is a thread seen from the top floor.

func conceptFloors() -> CGContext {
    let ctx = makeContext()
    paintField(ctx, top: 0xE2624C, bottom: 0x9B1D18)
    radialGlow(ctx, center: CGPoint(x: 500, y: 300), radius: 640, alpha: 0.20)

    // Lamp beam, wide enough to read as light and not as a triangle.
    ctx.setFillColor(color(0xFFFFFF, 0.08))
    polygon(ctx, [CGPoint(x: 470, y: 0), CGPoint(x: 554, y: 0), CGPoint(x: 742, y: 700), CGPoint(x: 282, y: 700)])

    numeral(ctx, "1", fontSize: 500, centerX: 512, baseline: 636, color: color(0xFFFFFF))

    // Floor 1, then the two rows under it, each a little narrower.
    let bars: [(y: CGFloat, width: CGFloat, alpha: CGFloat, height: CGFloat)] = [
        (664, 560, 0.96, 62),
        (752, 464, 0.52, 54),
        (830, 368, 0.28, 46),
    ]
    for bar in bars {
        let rect = CGRect(x: 512 - bar.width / 2, y: bar.y, width: bar.width, height: bar.height)
        let path = CGPath(roundedRect: rect, cornerWidth: bar.height / 2, cornerHeight: bar.height / 2, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(color(0xFFFFFF, bar.alpha))
        ctx.fillPath()
    }
    return ctx
}

// MARK: - 麻将脸瓦片
// S1's own visual language is the 麻将脸 smiley set: a pale tile standing at a
// slight angle, thick dark outline, a thin top face catching the light. The app
// icon borrows the tile and puts the floor number on it.

let tileInk = 0x2A1714 as UInt32
let tileFace = 0xEBDCD3 as UInt32
let tileTop = 0xF7EDE7 as UInt32
let tileSide = 0xC9AFA2 as UInt32

/// A glyph drawn once into a bitmap, so it can be skewed with the tile face.
func glyphImage(_ text: String, fontSize: CGFloat, color hex: UInt32) -> CGImage? {
    let box = CGSize(width: fontSize * 1.6, height: fontSize * 1.6)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil, width: Int(box.width), height: Int(box.height),
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let attributed = NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: NSColor(cgColor: color(hex))!,
    ])
    let bounds = attributed.size()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    attributed.draw(at: NSPoint(x: (box.width - bounds.width) / 2, y: (box.height - bounds.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()
}

/// Draws the tile in its own space, and lays the glyph on its front face with
/// the same tilt.
func drawTile(_ ctx: CGContext, center: CGPoint, side: CGFloat, depth: CGFloat, face: CGImage?) {
    // The smileys all lean back a little to the right.
    let tilt = CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: -7 * .pi / 180)

    let half = side / 2
    let radius = side * 0.16
    let front = CGRect(x: -half, y: -half, width: side, height: side)
    let shiftX = depth * 0.55
    let frontPath = CGMutablePath()
    frontPath.addRoundedRect(in: front, cornerWidth: radius, cornerHeight: radius)

    ctx.saveGState()
    ctx.concatenate(tilt)

    // Shadow on the stage floor.
    ctx.setFillColor(color(0x000000, 0.18))
    let shadow = CGMutablePath()
    shadow.addRoundedRect(
        in: front.offsetBy(dx: shiftX * 0.6, dy: depth * 1.1),
        cornerWidth: radius, cornerHeight: radius
    )
    ctx.addPath(shadow)
    ctx.fillPath()

    // Thickness: the same rounded silhouette, nudged up-right and drawn
    // underneath. What shows is a rim that follows the corners, which is how the
    // pixel smileys read as slabs rather than as cards.
    let backPath = CGMutablePath()
    backPath.addRoundedRect(
        in: front.offsetBy(dx: shiftX, dy: -depth),
        cornerWidth: radius, cornerHeight: radius
    )
    ctx.setFillColor(color(tileSide, 1))
    ctx.addPath(backPath)
    ctx.fillPath()
    ctx.setStrokeColor(color(tileInk, 1))
    ctx.setLineWidth(side * 0.03)
    ctx.setLineJoin(.round)
    ctx.addPath(backPath)
    ctx.strokePath()

    // Front face, then the number on it.
    ctx.setFillColor(color(tileFace, 1))
    ctx.addPath(frontPath)
    ctx.fillPath()

    if let face {
        ctx.saveGState()
        ctx.addPath(frontPath)
        ctx.clip()
        // The glyph was rendered by AppKit with its own origin, so it is drawn
        // back the right way up inside this flipped context.
        ctx.translateBy(x: front.minX, y: front.minY + front.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(face, in: CGRect(x: 0, y: 0, width: front.width, height: front.height))
        ctx.restoreGState()
    }

    // Outline over everything, the way the pixel smileys are drawn.
    ctx.setStrokeColor(color(tileInk, 1))
    ctx.setLineWidth(side * 0.04)
    ctx.setLineJoin(.round)
    ctx.addPath(frontPath)
    ctx.strokePath()

    // A single specular streak in the top-left corner, the way the pixel
    // smileys catch the light.
    ctx.saveGState()
    ctx.addPath(frontPath)
    ctx.clip()
    let streak = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(0xFFFFFF, 0.5), color(0xFFFFFF, 0)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        streak,
        start: CGPoint(x: -half, y: -half),
        end: CGPoint(x: -half + side * 0.55, y: -half + side * 0.5),
        options: []
    )
    ctx.restoreGState()
    ctx.restoreGState()
}

func conceptTile(withBubble: Bool) -> CGContext {
    let ctx = makeContext()
    paintField(ctx, top: 0xE0604A, bottom: 0x9A1C17)
    radialGlow(ctx, center: CGPoint(x: 460, y: 360), radius: 640, alpha: 0.22)

    let one = glyphImage("1", fontSize: 520, color: tileInk)
    drawTile(ctx, center: CGPoint(x: 492, y: 540), side: 452, depth: 28, face: one)

    if withBubble {
        ctx.setFillColor(color(0xFFFFFF, 1))
        ctx.setStrokeColor(color(tileInk, 1))
        ctx.setLineWidth(18)
        let bubble = CGMutablePath()
        bubble.addRoundedRect(in: CGRect(x: 640, y: 150, width: 240, height: 180), cornerWidth: 56, cornerHeight: 56)
        ctx.addPath(bubble)
        ctx.fillPath()
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: 700, y: 322))
        tail.addLine(to: CGPoint(x: 660, y: 400))
        tail.addLine(to: CGPoint(x: 760, y: 322))
        tail.closeSubpath()
        ctx.addPath(tail)
        ctx.fillPath()
        ctx.addPath(bubble)
        ctx.strokePath()
        numeral(ctx, "1", fontSize: 130, centerX: 760, baseline: 300, color: color(tileInk))
    }
    return ctx
}

// MARK: - H. 黑底版本
// The site's own touch icon is a black square with a white disc and a black 1.
// This keeps that contrast but puts the tile in the middle.

func conceptTileOnBlack() -> CGContext {
    let ctx = makeContext()
    paintField(ctx, top: 0x241A19, bottom: 0x0C0808)
    radialGlow(ctx, center: CGPoint(x: 400, y: 360), radius: 700, alpha: 0.20)

    // The disc from the site's touch icon, holding the tile like a stage.
    let disc = CGRect(x: 512 - 372, y: 512 - 372, width: 744, height: 744)
    ctx.setFillColor(color(0x2E2120, 1))
    ctx.fillEllipse(in: disc)
    ctx.setStrokeColor(color(0xD9523D, 0.75))
    ctx.setLineWidth(8)
    ctx.strokeEllipse(in: disc.insetBy(dx: 4, dy: 4))

    let one = glyphImage("1", fontSize: 640, color: tileInk)
    drawTile(ctx, center: CGPoint(x: 492, y: 540), side: 452, depth: 28, face: one)
    return ctx
}

/// Contact sheet: the mark at the sizes a phone actually shows it.
func contactSheet(_ source: CGImage, name: String) {
    let sizes: [CGFloat] = [180, 120, 87, 60, 40]
    let padding: CGFloat = 28
    let width = sizes.reduce(0) { $0 + $1 + padding } + padding
    let height = sizes.max()! + padding * 2
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: Int(width), height: Int(height),
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setFillColor(color(0xF2F2F7))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.interpolationQuality = .high
    var x = padding
    for side in sizes {
        let rect = CGRect(x: x, y: (height - side) / 2, width: side, height: side)
        ctx.saveGState()
        let radius = side * 0.2237
        let mask = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(mask)
        ctx.clip()
        ctx.draw(source, in: rect)
        ctx.restoreGState()
        x += side + padding
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    do {
        try rep.representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png"))
    } catch {
        print("could not write contact sheet: \(error)")
    }
}

// MARK: - F2. 红底（延续现有图标配色）+ 麻将瓦片
// The app already shipped a red field, so the tile version keeps that identity
// and only replaces the white letters with the forum's own tile.

func conceptTileOnRed() -> CGContext {
    let ctx = makeContext()
    paintField(ctx, top: 0xD8574A, bottom: 0xA3251D)
    // The diagonal sweep the old icon had, kept faintly so the two read as a family.
    ctx.saveGState()
    ctx.setFillColor(color(0xFFFFFF, 0.06))
    let sweep = CGMutablePath()
    sweep.move(to: CGPoint(x: -200, y: 1024))
    sweep.addLine(to: CGPoint(x: 620, y: 1024))
    sweep.addLine(to: CGPoint(x: 1024, y: 640))
    sweep.addLine(to: CGPoint(x: 1024, y: 300))
    sweep.closeSubpath()
    ctx.addPath(sweep)
    ctx.fillPath()
    ctx.restoreGState()
    radialGlow(ctx, center: CGPoint(x: 380, y: 320), radius: 620, alpha: 0.16)

    let one = glyphImage("1", fontSize: 700, color: tileInk)
    drawTile(ctx, center: CGPoint(x: 512, y: 516), side: 500, depth: 30, face: one)
    return ctx
}

// MARK: - 输出 app 图标
// App Store rejects icons with an alpha channel, so the shipped copy is flattened
// onto the field colour.

func writeIcon(_ make: () -> CGContext, to path: String) {
    let source = make().makeImage()!
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let flat = CGContext(
        data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        print("could not allocate icon context")
        return
    }
    flat.draw(source, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
    let rep = NSBitmapImageRep(cgImage: flat.makeImage()!)
    do {
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    } catch {
        print("could not write icon: \(error)")
    }
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
write(conceptSpotlight(), name: "concept-a-spotlight")
write(conceptCurtain(), name: "concept-b-curtain")
write(conceptBubble(), name: "concept-c-bubble")
write(conceptTile(withBubble: false), name: "concept-f-tile")
write(conceptTile(withBubble: true), name: "concept-g-tile-bubble")
write(conceptTileOnBlack(), name: "concept-h-tile-black")

write(conceptTileOnRed(), name: "concept-f2-tile-red")

if let redSheet = NSImage(contentsOfFile: "\(outDir)/concept-f2-tile-red.png")?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    contactSheet(redSheet, name: "contact-f2-tile-red")
}

if CommandLine.arguments.count > 2, CommandLine.arguments[2] == "--icon" {
    writeIcon(conceptTileOnRed, to: "S1Reader/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
}

if let sheetSource = NSImage(contentsOfFile: "\(outDir)/concept-h-tile-black.png")?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    contactSheet(sheetSource, name: "contact-h-tile-black")
}
write(conceptSteps(flip: false), name: "concept-d-steps-right")
write(conceptSteps(flip: true), name: "concept-d-steps-left")
