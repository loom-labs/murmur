#!/usr/bin/env swift
//
// Render Resources/AppIcon.icns.
//
// The icon is generated rather than checked in as a pile of PNGs: it is a set
// of shapes, and generating it means a change to the mark is a readable diff
// instead of an opaque binary blob.
//
// The mark is Hugo: tricolour head, white blaze, floppy ears, and the red
// thread he wears. Drawn flat, with a brow ridge and almond eyes rather than
// saucer eyes, so he reads as a grown dog and not a cartoon puppy — and so the
// silhouette still holds at 16 points, where any more detail turns to mud.
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

    let inset = d * 0.06
    let rect = CGRect(x: inset, y: inset, width: d - inset * 2, height: d - inset * 2)
    let radius = rect.width * 0.225

    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()

    // Blue. Warm tan against cool blue is the strongest contrast available for
    // a tricolour dog, and it keeps the mark readable at menu-bar sizes.
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [color(126, 200, 227), color(64, 134, 190)] as CFArray,
                             locations: [0, 1]) {
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    }

    let w = rect.width
    let cream = color(255, 252, 247)
    let tan = color(186, 118, 58)
    let tanDark = color(150, 90, 42)
    let ink = color(48, 34, 28)
    let thread = color(207, 46, 46)

    let headW = w * 0.615
    let headH = w * 0.585
    let headC = CGPoint(x: rect.midX, y: rect.midY + w * 0.045)

    // Red thread, just under the chin. There is no torso in the mark — the
    // face is the whole of it — so the thread sits at the base of the head
    // rather than on a neck.
    ctx.setStrokeColor(thread)
    ctx.setLineWidth(max(1.6, w * 0.030))
    ctx.setLineCap(.round)
    let threadY = headC.y - headH * 0.605
    ctx.move(to: CGPoint(x: rect.midX - headW * 0.36, y: threadY + w * 0.036))
    ctx.addQuadCurve(to: CGPoint(x: rect.midX + headW * 0.36, y: threadY + w * 0.036),
                     control: CGPoint(x: rect.midX, y: threadY - w * 0.070))
    ctx.strokePath()

    // Ears, behind the head
    let earSize = CGSize(width: w * 0.275, height: w * 0.60)
    let earDX = headW * 0.505
    let earY = headC.y - w * 0.135
    fillRotatedEllipse(ctx, center: CGPoint(x: headC.x - earDX, y: earY), size: earSize, degrees: 17, color: tan)
    fillRotatedEllipse(ctx, center: CGPoint(x: headC.x + earDX, y: earY), size: earSize, degrees: -17, color: tan)
    let earInner = CGSize(width: earSize.width * 0.54, height: earSize.height * 0.68)
    fillRotatedEllipse(ctx, center: CGPoint(x: headC.x - earDX - w * 0.010, y: earY - w * 0.030),
                       size: earInner, degrees: 17, color: tanDark)
    fillRotatedEllipse(ctx, center: CGPoint(x: headC.x + earDX + w * 0.010, y: earY - w * 0.030),
                       size: earInner, degrees: -17, color: tanDark)

    // Head
    ctx.setFillColor(tan)
    ctx.fillEllipse(in: CGRect(x: headC.x - headW / 2, y: headC.y - headH / 2, width: headW, height: headH))

    // White blaze down the centre of the face, into the muzzle
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: headC.x - headW / 2, y: headC.y - headH / 2, width: headW, height: headH))
    ctx.clip()
    ctx.setFillColor(cream)
    let blazeW = headW * 0.225
    ctx.fillEllipse(in: CGRect(x: headC.x - blazeW / 2, y: headC.y - headH * 0.30,
                               width: blazeW, height: headH * 0.86))
    // Muzzle
    ctx.fillEllipse(in: CGRect(x: headC.x - headW * 0.335, y: headC.y - headH * 0.70,
                               width: headW * 0.67, height: headH * 0.66))
    ctx.restoreGState()

    // Eyes, either side of the blaze
    let eyeDX = headW * 0.245
    let eyeY = headC.y + headH * 0.075
    let eyeW = headW * 0.175
    let eyeH = headH * 0.150
    for sign in [CGFloat(-1), 1] {
        let ec = CGPoint(x: headC.x + sign * eyeDX, y: eyeY)
        ctx.setFillColor(ink)
        ctx.fillEllipse(in: CGRect(x: ec.x - eyeW / 2, y: ec.y - eyeH / 2, width: eyeW, height: eyeH))
        // One restrained catchlight. Two big ones read as a cartoon puppy.
        ctx.setFillColor(color(255, 255, 255, 0.85))
        let hl = eyeW * 0.24
        ctx.fillEllipse(in: CGRect(x: ec.x + eyeW * 0.06, y: ec.y + eyeH * 0.10, width: hl, height: hl))

        // Brow ridge above each eye — where Hugo's expression actually lives.
        ctx.setStrokeColor(color(126, 74, 34, 0.75))
        ctx.setLineWidth(max(1, w * 0.016))
        ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: ec.x - eyeW * 0.62, y: ec.y + eyeH * 0.95))
        ctx.addQuadCurve(to: CGPoint(x: ec.x + eyeW * 0.62, y: ec.y + eyeH * 0.80),
                         control: CGPoint(x: ec.x, y: ec.y + eyeH * 1.45))
        ctx.strokePath()
    }

    // Nose
    let noseW = headW * 0.235
    let noseH = headH * 0.140
    let noseC = CGPoint(x: headC.x, y: headC.y - headH * 0.325)
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: noseC.x - noseW / 2, y: noseC.y - noseH / 2, width: noseW, height: noseH))

    // Smile
    ctx.setStrokeColor(color(72, 52, 42))
    ctx.setLineWidth(max(1, w * 0.017))
    ctx.setLineJoin(.round)
    let jaw = noseC.y - noseH * 0.55 - headH * 0.055
    ctx.move(to: CGPoint(x: noseC.x, y: noseC.y - noseH * 0.55))
    ctx.addLine(to: CGPoint(x: noseC.x, y: jaw))
    ctx.strokePath()
    let lobe = headW * 0.130
    let depth = headH * 0.040
    for sign in [CGFloat(-1), 1] {
        ctx.move(to: CGPoint(x: noseC.x, y: jaw))
        ctx.addQuadCurve(to: CGPoint(x: noseC.x + sign * lobe * 1.6, y: jaw + depth * 0.35),
                         control: CGPoint(x: noseC.x + sign * lobe, y: jaw - depth))
        ctx.strokePath()
    }

    ctx.restoreGState()
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
    .appendingPathComponent("Beagle-\(UUID().uuidString).iconset")

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
