#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct IconSlot {
    let filename: String
    let pixels: Int
}

private let slots = [
    IconSlot(filename: "icon_16x16.png", pixels: 16),
    IconSlot(filename: "icon_16x16@2x.png", pixels: 32),
    IconSlot(filename: "icon_32x32.png", pixels: 32),
    IconSlot(filename: "icon_32x32@2x.png", pixels: 64),
    IconSlot(filename: "icon_128x128.png", pixels: 128),
    IconSlot(filename: "icon_128x128@2x.png", pixels: 256),
    IconSlot(filename: "icon_256x256.png", pixels: 256),
    IconSlot(filename: "icon_256x256@2x.png", pixels: 512),
    IconSlot(filename: "icon_512x512.png", pixels: 512),
    IconSlot(filename: "icon_512x512@2x.png", pixels: 1024),
]

private enum GeneratorError: Error, CustomStringConvertible {
    case usage
    case unsafeOutput(String)
    case context(Int)
    case destination(String)

    var description: String {
        switch self {
        case .usage: "usage: swift Tools/generate_talkie_icon.swift --output <AppIcon.appiconset>"
        case .unsafeOutput(let path): "refusing output outside an existing AppIcon.appiconset: \(path)"
        case .context(let pixels): "could not create \(pixels)px bitmap context"
        case .destination(let filename): "could not write \(filename)"
        }
    }
}

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat,
                   _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            components: [red, green, blue, alpha])!
}

private func gradient(_ colors: [CGColor], locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
               colors: colors as CFArray,
               locations: locations)!
}

private func render(pixels: Int) throws -> CGImage {
    guard let context = CGContext(data: nil,
                                  width: pixels,
                                  height: pixels,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw GeneratorError.context(pixels) }

    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))

    // Native macOS tile with enough transparent margin for Dock depth and shadow.
    let tile = CGPath(roundedRect: CGRect(x: 82, y: 82, width: 860, height: 860),
                      cornerWidth: 206, cornerHeight: 206, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -26), blur: 38,
                      color: color(0.01, 0.015, 0.04, 0.62))
    context.addPath(tile)
    context.setFillColor(color(0.025, 0.04, 0.105))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tile)
    context.clip()
    context.drawLinearGradient(
        gradient([color(0.055, 0.105, 0.235), color(0.025, 0.035, 0.105),
                  color(0.10, 0.035, 0.19)], locations: [0, 0.58, 1]),
        start: CGPoint(x: 220, y: 910), end: CGPoint(x: 850, y: 100), options: [])
    context.drawRadialGradient(
        gradient([color(0.10, 0.74, 0.92, 0.18), color(0.05, 0.18, 0.38, 0)],
                 locations: [0, 1]),
        startCenter: CGPoint(x: 355, y: 690), startRadius: 0,
        endCenter: CGPoint(x: 355, y: 690), endRadius: 470,
        options: [.drawsAfterEndLocation])
    context.restoreGState()

    // Fine inset rim. It gives the tile definition without becoming skeuomorphic.
    context.addPath(tile)
    context.setStrokeColor(color(0.38, 0.62, 0.90, 0.22))
    context.setLineWidth(pixels <= 32 ? 10 : 4)
    context.strokePath()

    // Glass pill and its soft ambient cyan depth.
    let pillRect = CGRect(x: 224, y: 380, width: 576, height: 264)
    let pill = CGPath(roundedRect: pillRect, cornerWidth: 132, cornerHeight: 132, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 34,
                      color: color(0.02, 0.82, 1, 0.24))
    context.addPath(pill)
    context.setFillColor(color(0.02, 0.06, 0.14, 0.94))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(pill)
    context.clip()
    context.drawLinearGradient(
        gradient([color(0.22, 0.42, 0.62, 0.72), color(0.035, 0.07, 0.16, 0.92),
                  color(0.02, 0.035, 0.095, 0.98)], locations: [0, 0.33, 1]),
        start: CGPoint(x: 512, y: 644), end: CGPoint(x: 512, y: 380), options: [])
    context.restoreGState()

    context.addPath(pill)
    context.setStrokeColor(color(0.58, 0.88, 1, 0.34))
    context.setLineWidth(pixels <= 32 ? 13 : 5)
    context.strokePath()

    // A single restrained glass reflection follows the capsule curvature.
    if pixels >= 64 {
        let highlight = CGPath(roundedRect: CGRect(x: 260, y: 585, width: 504, height: 28),
                               cornerWidth: 14, cornerHeight: 14, transform: nil)
        context.addPath(highlight)
        context.setFillColor(color(0.75, 0.94, 1, 0.13))
        context.fillPath()
    }

    let centers: [CGFloat] = [372, 442, 512, 582, 652]
    let heights: [CGFloat] = pixels <= 32 ? [82, 128, 184, 128, 82]
                                          : [92, 148, 210, 148, 92]
    let widths: [CGFloat] = pixels <= 32 ? [42, 42, 48, 42, 42]
                                         : [34, 38, 44, 38, 34]
    for index in centers.indices {
        let rect = CGRect(x: centers[index] - widths[index] / 2,
                          y: 512 - heights[index] / 2,
                          width: widths[index], height: heights[index])
        let bar = CGPath(roundedRect: rect,
                         cornerWidth: widths[index] / 2,
                         cornerHeight: widths[index] / 2,
                         transform: nil)
        context.saveGState()
        context.setShadow(offset: .zero, blur: index == 2 ? 18 : 14,
                          color: index == 2 ? color(0.85, 0.98, 1, 0.48)
                                           : color(0.05, 0.86, 1, 0.48))
        context.addPath(bar)
        context.clip()
        let colors = index == 2
            ? [color(1, 1, 1), color(0.62, 0.94, 1)]
            : [color(0.18, 0.96, 1), color(0.08, 0.56, 0.98)]
        context.drawLinearGradient(gradient(colors, locations: [0, 1]),
                                   start: CGPoint(x: 512, y: rect.maxY),
                                   end: CGPoint(x: 512, y: rect.minY), options: [])
        context.restoreGState()
    }

    guard let image = context.makeImage() else { throw GeneratorError.context(pixels) }
    return image
}

private func write(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw GeneratorError.destination(url.lastPathComponent) }
    CGImageDestinationAddImage(destination, image, [
        kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGsRGBIntent: 0]
    ] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw GeneratorError.destination(url.lastPathComponent)
    }
}

do {
    guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--output" else {
        throw GeneratorError.usage
    }
    let output = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
    guard output.pathExtension == "appiconset",
          output.lastPathComponent == "AppIcon.appiconset",
          FileManager.default.fileExists(atPath: output.appendingPathComponent("Contents.json").path)
    else { throw GeneratorError.unsafeOutput(output.path) }

    for slot in slots {
        try write(render(pixels: slot.pixels), to: output.appendingPathComponent(slot.filename))
        print("generated \(slot.filename) (\(slot.pixels)×\(slot.pixels))")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
