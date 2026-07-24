#!/usr/bin/env swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Study: String, CaseIterable {
    case notchVoice = "notch-voice"
    case inkWave = "ink-wave"
    case glassSlit = "glass-slit"
    case orbit = "orbit"
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func c(_ white: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [white, white, white, alpha])!
}
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r, g, b, a])!
}
func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func baseContext() -> CGContext {
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                            bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setAllowsAntialiasing(true)
    let tile = rounded(CGRect(x: 82, y: 82, width: 860, height: 860), 206)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 36,
                      color: rgb(0, 0, 0, 0.55))
    context.addPath(tile); context.setFillColor(rgb(0.025, 0.028, 0.038)); context.fillPath()
    context.restoreGState()
    context.saveGState(); context.addPath(tile); context.clip()
    let gradient = CGGradient(colorsSpace: colorSpace,
                              colors: [rgb(0.16, 0.17, 0.20), rgb(0.025, 0.028, 0.038)] as CFArray,
                              locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 180, y: 900),
                               end: CGPoint(x: 850, y: 120), options: [])
    context.restoreGState()
    context.addPath(tile); context.setStrokeColor(c(1, 0.14)); context.setLineWidth(3); context.strokePath()
    return context
}

func drawBars(_ context: CGContext, centers: [CGFloat], baseline: CGFloat,
              heights: [CGFloat], width: CGFloat, brightCenter: Bool = true) {
    for index in centers.indices {
        let rect = CGRect(x: centers[index] - width / 2, y: baseline - heights[index] / 2,
                          width: width, height: heights[index])
        context.addPath(rounded(rect, width / 2))
        context.setFillColor(brightCenter && index == centers.count / 2 ? c(0.98) : c(0.62))
        context.fillPath()
    }
}

func render(_ study: Study) -> CGImage {
    let context = baseContext()
    switch study {
    case .notchVoice:
        let notch = rounded(CGRect(x: 330, y: 726, width: 364, height: 216), 74)
        context.addPath(notch); context.setFillColor(c(0)); context.fillPath()
        context.setShadow(offset: .zero, blur: 20, color: c(1, 0.12))
        drawBars(context, centers: [407, 459, 512, 565, 617], baseline: 696,
                 heights: [70, 112, 164, 112, 70], width: 26)
        context.setShadow(offset: .zero, blur: 0)
        context.addPath(rounded(CGRect(x: 360, y: 640, width: 304, height: 126), 63))
        context.setStrokeColor(c(1, 0.20)); context.setLineWidth(4); context.strokePath()
    case .inkWave:
        let path = CGMutablePath()
        for x in stride(from: 228.0, through: 796.0, by: 3) {
            let n = (x - 228) / 568
            let y = 512 + sin(n * .pi * 5.5) * 92 * pow(sin(n * .pi), 1.7)
            x == 228 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        context.setShadow(offset: .zero, blur: 26, color: c(1, 0.26))
        context.addPath(path); context.setStrokeColor(c(0.94)); context.setLineWidth(13)
        context.setLineCap(.round); context.setLineJoin(.round); context.strokePath()
        context.setShadow(offset: .zero, blur: 0)
        context.addEllipse(in: CGRect(x: 500, y: 500, width: 24, height: 24))
        context.setFillColor(c(1)); context.fillPath()
    case .glassSlit:
        let glass = rounded(CGRect(x: 210, y: 418, width: 604, height: 188), 94)
        context.saveGState(); context.addPath(glass); context.clip()
        let g = CGGradient(colorsSpace: colorSpace,
                           colors: [c(0.9, 0.30), c(0.16, 0.56), c(0.04, 0.82)] as CFArray,
                           locations: [0, 0.42, 1])!
        context.drawLinearGradient(g, start: CGPoint(x: 512, y: 606),
                                   end: CGPoint(x: 512, y: 418), options: [])
        context.restoreGState()
        context.addPath(glass); context.setStrokeColor(c(1, 0.28)); context.setLineWidth(4); context.strokePath()
        context.setShadow(offset: .zero, blur: 20, color: c(1, 0.22))
        context.addPath(rounded(CGRect(x: 288, y: 499, width: 448, height: 26), 13))
        context.setFillColor(c(0.92)); context.fillPath()
        context.setShadow(offset: .zero, blur: 0)
    case .orbit:
        context.addEllipse(in: CGRect(x: 292, y: 292, width: 440, height: 440))
        context.setStrokeColor(c(1, 0.17)); context.setLineWidth(5); context.strokePath()
        context.addEllipse(in: CGRect(x: 422, y: 422, width: 180, height: 180))
        context.setShadow(offset: .zero, blur: 34, color: c(1, 0.30))
        context.setFillColor(c(0.93)); context.fillPath()
        context.setShadow(offset: .zero, blur: 0)
        context.addEllipse(in: CGRect(x: 687, y: 492, width: 40, height: 40))
        context.setFillColor(c(0.62)); context.fillPath()
    }
    return context.makeImage()!
}

func write(_ image: CGImage, _ url: URL) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--output" else {
    fputs("usage: swift tools/generate_icon_studies.swift --output design-studies/icons\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
guard output.lastPathComponent == "icons",
      output.deletingLastPathComponent().lastPathComponent == "design-studies" else {
    fputs("error: output must be design-studies/icons\n", stderr)
    exit(1)
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for study in Study.allCases {
    let target = output.appendingPathComponent("\(study.rawValue).png")
    guard write(render(study), target) else { fatalError("could not write \(target.path)") }
    print("generated \(target.lastPathComponent)")
}
