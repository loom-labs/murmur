#!/usr/bin/env swift
//
// Render Resources/AppIcon.icns.
//
// The icon is generated rather than checked in as a pile of PNGs: it is a set
// of shapes, and generating it means a change to the mark is a readable diff
// instead of an opaque binary blob.
//
// The mark is Hugo himself — a beagle, drawn flat and wide-eyed so the
// silhouette still reads at 16 points where any more detail turns to mud.
//
// Usage:
//   swift Scripts/make-icon.swift [output.icns]
//
import AppKit
import CoreGraphics
import Foundation

/// Sizes macOS expects in an iconset, as (pixel size, filename).
let iconSizes: [(pixels: Int, name: String)] = [
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

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// Draw an ellipse rotated about its own centre.
func addRotatedEllipse(_ ctx: CGContext, center: CGPoint, size: CGSize, degrees: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: degrees * .pi / 180)
    ctx.addEllipse(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
    ctx.restoreGState()
}

func fillRotatedEllipse(_ ctx: CGContext, center: CGPoint, size: CGSize, degrees: CGFloat, color fill: CGColor) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: degrees * .pi / 180)
    ctx.setFillColor(fill)
    ctx.fillEllipse(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
    ctx.restoreGState()
}

func drawIcon(size: Int) -> CGImage? {
    let d = CGFloat(size)
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Squircle background
    let inset = d * 0.06
    let rect = CGRect(x: inset, y: inset, width: d - inset * 2, height: d - inset * 2)
    let radius = rect.width * 0.225
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [color(126, 200, 227), color(72, 146, 199)] as CFArray,
                             locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    }
    ctx.restoreGState()

    // Geometry anchored to the squircle
    let cx = rect.midX
    let cy = rect.midY
    let w = rect.width

    let headW = w * 0.60
    let headH = w * 0.56
    let headC = CGPoint(x: cx, y: cy + w * 0.045)

    let brown = color(150, 92, 46)
    let brownDark = color(118, 70, 34)
    let cream = color(255, 250, 243)

    // Ears — drawn first so they sit behind the head
    let earSize = CGSize(width: w * 0.215, height: w * 0.46)
    let earDX = headW * 0.455
    let earY = headC.y - w * 0.115
    fillRotatedEllipse(ctx, center: CGPoint(x: headC.x - earDX, y: earY),
                       size: earSize, degrees: 20, color: brown)
    fillRotatedEllipse(ctx, center: CGPoint(x: headC.x + earDX, y: earY),
                       size: earSize, degrees: -20, color: brown)
    // Inner shading, offset down the ear so it reads as depth not a stripe
    let earInner = CGSize(width: earSize.width * 0.52, height: earSize.height * 0.66)
    fillRotatedEllipse(ctx, center: CGPoint(x: headC.x - earDX - w * 0.012, y: earY - w * 0.035),
                       size: earInner, degrees: 20, color: brownDark)
    fillRotatedEllipse(ctx, center: CGPoint(x: headC.x + earDX + w * 0.012, y: earY - w * 0.035),
                       size: earInner, degrees: -20, color: brownDark)

    // Head
    ctx.setFillColor(cream)
    ctx.fillEllipse(in: CGRect(x: headC.x - headW / 2, y: headC.y - headH / 2, width: headW, height: headH))

    // Brown cap over the top of the head
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: headC.x - headW / 2, y: headC.y - headH / 2, width: headW, height: headH))
    ctx.clip()
    ctx.setFillColor(brown)
    // Ellipse rather than a rectangle so the marking's lower edge follows a
    // curve, the way a beagle's cap actually sits.
    ctx.fillEllipse(in: CGRect(x: headC.x - headW * 0.56, y: headC.y - headH * 0.10,
                               width: headW * 1.12, height: headH * 0.95))
    ctx.restoreGState()

    // Head outline for definition at small sizes
    ctx.setStrokeColor(color(96, 56, 28, 0.35))
    ctx.setLineWidth(max(1, w * 0.010))
    ctx.strokeEllipse(in: CGRect(x: headC.x - headW / 2, y: headC.y - headH / 2, width: headW, height: headH))

    // Eyes
    let eyeDX = headW * 0.225
    let eyeY = headC.y + headH * 0.045
    let eyeW = headW * 0.175
    let eyeH = headH * 0.225
    for sign in [CGFloat(-1), 1] {
        let ec = CGPoint(x: headC.x + sign * eyeDX, y: eyeY)
        ctx.setFillColor(color(28, 22, 20))
        ctx.fillEllipse(in: CGRect(x: ec.x - eyeW / 2, y: ec.y - eyeH / 2, width: eyeW, height: eyeH))
        // anime highlights
        ctx.setFillColor(color(255, 255, 255, 0.95))
        let hl = eyeW * 0.36
        ctx.fillEllipse(in: CGRect(x: ec.x - eyeW * 0.06, y: ec.y + eyeH * 0.10, width: hl, height: hl))
        let hl2 = eyeW * 0.20
        ctx.fillEllipse(in: CGRect(x: ec.x - eyeW * 0.34, y: ec.y - eyeH * 0.24, width: hl2, height: hl2))
    }

    // Muzzle
    let muzW = headW * 0.52
    let muzH = headH * 0.36
    let muzC = CGPoint(x: headC.x, y: headC.y - headH * 0.26)
    ctx.setFillColor(cream)
    ctx.fillEllipse(in: CGRect(x: muzC.x - muzW / 2, y: muzC.y - muzH / 2, width: muzW, height: muzH))

    // Nose
    let noseW = headW * 0.20
    let noseH = headH * 0.135
    let noseC = CGPoint(x: headC.x, y: muzC.y + muzH * 0.30)
    ctx.setFillColor(color(30, 24, 22))
    ctx.fillEllipse(in: CGRect(x: noseC.x - noseW / 2, y: noseC.y - noseH / 2, width: noseW, height: noseH))

    // Smile: two quad curves rather than arcs, which are far easier to aim.
    ctx.setStrokeColor(color(60, 44, 36))
    ctx.setLineWidth(max(1, w * 0.018))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let mouthTop = noseC.y - noseH * 0.55
    let mouthDrop = headH * 0.070
    ctx.move(to: CGPoint(x: noseC.x, y: mouthTop))
    ctx.addLine(to: CGPoint(x: noseC.x, y: mouthTop - mouthDrop))
    ctx.strokePath()

    let lobe = headW * 0.125
    let lobeDepth = headH * 0.075
    let jaw = mouthTop - mouthDrop
    ctx.move(to: CGPoint(x: noseC.x, y: jaw))
    ctx.addQuadCurve(to: CGPoint(x: noseC.x - lobe * 1.6, y: jaw + lobeDepth * 0.35),
                     control: CGPoint(x: noseC.x - lobe, y: jaw - lobeDepth))
    ctx.strokePath()
    ctx.move(to: CGPoint(x: noseC.x, y: jaw))
    ctx.addQuadCurve(to: CGPoint(x: noseC.x + lobe * 1.6, y: jaw + lobeDepth * 0.35),
                     control: CGPoint(x: noseC.x + lobe, y: jaw - lobeDepth))
    ctx.strokePath()

    return ctx.makeImage()
}

// MARK: - Entry point

let arguments = CommandLine.arguments
let outputPath =
    arguments.count > 1
    ? arguments[1]
    : FileManager.default.currentDirectoryPath + "/Resources/AppIcon.icns"

let outputURL = URL(fileURLWithPath: outputPath)
let iconsetURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("Hugo-\(UUID().uuidString).iconset")

do {
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    for (pixels, name) in iconSizes {
        guard let image = drawIcon(size: pixels) else {
            FileHandle.standardError.write(Data("error: could not render \(name)\n".utf8))
            exit(1)
        }
        let destination = iconsetURL.appendingPathComponent(name)
        guard
            let output = CGImageDestinationCreateWithURL(
                destination as CFURL,
                "public.png" as CFString,
                1,
                nil
            )
        else {
            FileHandle.standardError.write(Data("error: could not write \(name)\n".utf8))
            exit(1)
        }
        CGImageDestinationAddImage(output, image, nil)
        CGImageDestinationFinalize(output)
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["--convert", "icns", iconsetURL.path, "--output", outputURL.path]
    try iconutil.run()
    iconutil.waitUntilExit()

    guard iconutil.terminationStatus == 0 else {
        FileHandle.standardError.write(Data("error: iconutil failed\n".utf8))
        exit(1)
    }

    try? FileManager.default.removeItem(at: iconsetURL)
    print("Wrote \(outputURL.path)")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
