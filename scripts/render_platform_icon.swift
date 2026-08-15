#!/usr/bin/env swift

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum IconStyle: String {
    case opaque
    case transparent
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    fail("Usage: render_platform_icon.swift <source.png> <output.png> <pixels> <opaque|transparent>")
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
guard let pixels = Int(arguments[3]), pixels > 0 else {
    fail("The output size must be a positive integer.")
}
guard let style = IconStyle(rawValue: arguments[4]) else {
    fail("The icon style must be opaque or transparent.")
}
guard let sourceImage = NSImage(contentsOf: sourceURL),
      let sourceCGImage = sourceImage.cgImage(
          forProposedRect: nil,
          context: nil,
          hints: nil
      ) else {
    fail("Could not read \(sourceURL.path).")
}

let sourceWidth = sourceCGImage.width
let sourceHeight = sourceCGImage.height
let colorSpace = CGColorSpaceCreateDeviceRGB()
var sourcePixels = [UInt8](
    repeating: 0,
    count: sourceWidth * sourceHeight * 4
)

guard let sourceContext = CGContext(
    data: &sourcePixels,
    width: sourceWidth,
    height: sourceHeight,
    bitsPerComponent: 8,
    bytesPerRow: sourceWidth * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fail("Could not inspect the source icon.")
}

sourceContext.draw(
    sourceCGImage,
    in: CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)
)

var minimumX = sourceWidth
var minimumY = sourceHeight
var maximumX = -1
var maximumY = -1

for y in 0..<sourceHeight {
    for x in 0..<sourceWidth {
        let alpha = sourcePixels[((y * sourceWidth) + x) * 4 + 3]
        if alpha > 2 {
            minimumX = min(minimumX, x)
            minimumY = min(minimumY, y)
            maximumX = max(maximumX, x)
            maximumY = max(maximumY, y)
        }
    }
}

guard maximumX >= minimumX, maximumY >= minimumY else {
    fail("The source icon has no visible pixels.")
}

let visibleWidth = Double(maximumX - minimumX + 1)
let visibleHeight = Double(maximumY - minimumY + 1)
let visibleCenterX = Double(minimumX) + visibleWidth / 2
let visibleCenterY = Double(minimumY) + visibleHeight / 2

// The source artwork already contains its own rounded silhouette and shadow.
// Cropping slightly inside the visible bounds removes the transparent gutter
// that platform icon masks otherwise render as a black or white outer plate.
let cropSide = max(visibleWidth, visibleHeight) * 0.94
let cropOriginX = max(
    0,
    min(Double(sourceWidth) - cropSide, visibleCenterX - cropSide / 2)
)
let cropOriginY = max(
    0,
    min(Double(sourceHeight) - cropSide, visibleCenterY - cropSide / 2)
)

let hasAlpha = style == .transparent
var outputPixels = [UInt8](repeating: 0, count: pixels * pixels * 4)
let outputAlphaInfo: CGImageAlphaInfo = hasAlpha
    ? .premultipliedLast
    : .noneSkipLast
guard let outputContext = CGContext(
    data: &outputPixels,
    width: pixels,
    height: pixels,
    bitsPerComponent: 8,
    bytesPerRow: pixels * 4,
    space: colorSpace,
    bitmapInfo: outputAlphaInfo.rawValue
) else {
    fail("Could not create the output icon.")
}

sourceImage.size = NSSize(width: sourceWidth, height: sourceHeight)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(
    cgContext: outputContext,
    flipped: false
)
outputContext.interpolationQuality = .high

if style == .opaque {
    outputContext.setFillColor(
        red: CGFloat(0x38) / 255,
        green: CGFloat(0x18) / 255,
        blue: CGFloat(0x0F) / 255,
        alpha: 1
    )
    outputContext.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
}

sourceImage.draw(
    in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
    from: NSRect(
        x: cropOriginX,
        y: cropOriginY,
        width: cropSide,
        height: cropSide
    ),
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: true,
    hints: [.interpolation: NSImageInterpolation.high]
)

outputContext.flush()
NSGraphicsContext.restoreGraphicsState()

do {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
} catch {
    fail("Could not write \(outputURL.path): \(error.localizedDescription)")
}

guard let outputCGImage = outputContext.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          outputURL as CFURL,
          UTType.png.identifier as CFString,
          1,
          nil
      ) else {
    fail("Could not encode the output icon.")
}

CGImageDestinationAddImage(destination, outputCGImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fail("Could not write \(outputURL.path).")
}
