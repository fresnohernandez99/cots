// Renders the app icon: build/AppIcon.iconset (turn into apps/macos/Resources/AppIcon.icns with
// `iconutil -c icns`) and assets/AppIcon-1024.png, the source for the Windows icons.
// Run from the repo root: swift apps/macos/scripts/make-icon.swift
import AppKit
import CoreGraphics
import CoreText

func render(_ size: CGFloat) -> CGImage {
    let s = size / 1024
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)

    // Squircle-ish tile inside the standard macOS icon margins.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(CGColor(red: 0.31, green: 0.27, blue: 0.9, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        CGColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1),
        CGColor(red: 0.02, green: 0.71, blue: 0.83, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 100, y: 924), end: CGPoint(x: 924, y: 100), options: [])
    ctx.restoreGState()

    // Note card with a folded corner.
    let card = CGRect(x: 262, y: 210, width: 500, height: 604)
    let fold: CGFloat = 120
    let cardPath = CGMutablePath()
    cardPath.move(to: CGPoint(x: card.minX + 40, y: card.minY))
    cardPath.addLine(to: CGPoint(x: card.maxX - 40, y: card.minY))
    cardPath.addQuadCurve(to: CGPoint(x: card.maxX, y: card.minY + 40), control: CGPoint(x: card.maxX, y: card.minY))
    cardPath.addLine(to: CGPoint(x: card.maxX, y: card.maxY - fold))
    cardPath.addLine(to: CGPoint(x: card.maxX - fold, y: card.maxY))
    cardPath.addLine(to: CGPoint(x: card.minX + 40, y: card.maxY))
    cardPath.addQuadCurve(to: CGPoint(x: card.minX, y: card.maxY - 40), control: CGPoint(x: card.minX, y: card.maxY))
    cardPath.addLine(to: CGPoint(x: card.minX, y: card.minY + 40))
    cardPath.addQuadCurve(to: CGPoint(x: card.minX + 40, y: card.minY), control: CGPoint(x: card.minX, y: card.minY))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.25))
    ctx.addPath(cardPath)
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    let foldPath = CGMutablePath()
    foldPath.move(to: CGPoint(x: card.maxX, y: card.maxY - fold))
    foldPath.addLine(to: CGPoint(x: card.maxX - fold, y: card.maxY - fold))
    foldPath.addLine(to: CGPoint(x: card.maxX - fold, y: card.maxY))
    foldPath.closeSubpath()
    ctx.addPath(foldPath)
    ctx.setFillColor(CGColor(red: 0.85, green: 0.87, blue: 0.95, alpha: 1))
    ctx.fillPath()

    // "{ }" in the brand color, centered on the card.
    let font = CTFontCreateWithName("Menlo-Bold" as CFString, 230, nil)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(red: 0.31, green: 0.27, blue: 0.9, alpha: 1),
                                                .kern: -30]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "{ }", attributes: attrs))
    let bounds = CTLineGetImageBounds(line, ctx)
    ctx.textPosition = CGPoint(x: card.midX - bounds.width / 2 - bounds.minX, y: card.midY - bounds.height / 2 - bounds.minY - 20)
    CTLineDraw(line, ctx)

    return ctx.makeImage()!
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let rep = NSBitmapImageRep(cgImage: render(CGFloat(base * scale)))
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try NSBitmapImageRep(cgImage: render(1024)).representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("assets/AppIcon-1024.png"))
print(iconset.path)
