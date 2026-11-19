#!/usr/bin/env swift
// Regenerates both icon assets from one drawing:
//   Resources/AppIcon.icns     the app icon, which macOS shows in notifications
//   Resources/MenuBarIcon.pdf  a monochrome template for the menu bar
//
// Run after changing the design:  swift scripts/make-icon.swift
// The results are committed, so building the app does not need this script.
//
// The glyph is drawn by hand because SF Symbols may not be used in app icons.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources")
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

/// An open ring with a dot in the gap: a "C" with a status light.
/// Drawn in the unit square with y pointing up.
func drawGlyph(_ ctx: CGContext, ring: CGColor, dot: CGColor) {
    let center = CGPoint(x: 0.47, y: 0.5), radius: CGFloat = 0.33, dotRadius: CGFloat = 0.1
    ctx.setStrokeColor(ring)
    ctx.setLineWidth(0.13)
    ctx.setLineCap(.round)
    ctx.addArc(center: center, radius: radius, startAngle: 42 * .pi / 180, endAngle: 318 * .pi / 180, clockwise: false)
    ctx.strokePath()
    ctx.setFillColor(dot)
    ctx.fillEllipse(in: CGRect(
        x: center.x + radius - dotRadius, y: center.y - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius
    ))
}

/// The glyph on a dark rounded square, following the macOS icon grid (824 pt body on a 1024 pt canvas).
func drawAppIcon(_ ctx: CGContext, size: CGFloat) {
    let body = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 100 / 1024, dy: size * 100 / 1024)
    let shape = CGPath(roundedRect: body, cornerWidth: size * 185 / 1024, cornerHeight: size * 185 / 1024, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(30, 35, 50))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: sRGB, colors: [color(62, 70, 94), color(27, 31, 45)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    ctx.restoreGState()

    let glyph = body.insetBy(dx: body.width * 0.2, dy: body.height * 0.2)
    ctx.saveGState()
    ctx.translateBy(x: glyph.minX, y: glyph.minY)
    ctx.scaleBy(x: glyph.width, y: glyph.height)
    drawGlyph(ctx, ring: color(255, 255, 255), dot: color(255, 170, 60))
    ctx.restoreGState()
}

func writeAppIconPNG(pixels: Int, to url: URL) throws {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    drawAppIcon(ctx, size: CGFloat(pixels))
    let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    try png.write(to: url)
}

// MARK: App icon

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeStatus-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

for points in [16, 32, 128, 256, 512] {
    try writeAppIconPNG(pixels: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try writeAppIconPNG(pixels: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let icns = resources.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("wrote \(icns.path)")

// MARK: Menu bar template

let points: CGFloat = 18
var box = CGRect(x: 0, y: 0, width: points, height: points)
let pdfURL = resources.appendingPathComponent("MenuBarIcon.pdf")
let pdf = CGContext(pdfURL as CFURL, mediaBox: &box, nil)!
pdf.beginPDFPage(nil)
pdf.scaleBy(x: points, y: points)
// A template image only uses the alpha channel, so the dot is the same colour as the ring.
drawGlyph(pdf, ring: CGColor(gray: 0, alpha: 1), dot: CGColor(gray: 0, alpha: 1))
pdf.endPDFPage()
pdf.closePDF()
print("wrote \(pdfURL.path)")
