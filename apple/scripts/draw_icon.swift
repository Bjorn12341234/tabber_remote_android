// Tabber Spak's icon: a spak (a lever) in Tabber Studio's design language:
// a stick with a long grip, no ball on top; Tabber Studio's dark tokens and its
// teal accent at the grip band and the gate.
// Run: swift apple/scripts/draw_icon.swift apple/TabberSpak/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((value >> 16) & 0xFF) / 255, CGFloat((value >> 8) & 0xFF) / 255,
                                            CGFloat(value & 0xFF) / 255, alpha])!
}
func gradient(_ a: CGColor, _ b: CGColor) -> CGGradient { CGGradient(colorsSpace: space, colors: [a, b] as CFArray, locations: [0, 1])! }

// Background: Tabber Studio's dark tokens, bg_2 down to bg_0.
ctx.drawLinearGradient(gradient(hex(0x2B2B42), hex(0x121219)), start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 0), options: [])

// The base, a rounded slab seen from slightly above, with its gate.
ctx.setFillColor(hex(0x08080D, 0.55))
ctx.fillEllipse(in: CGRect(x: 236, y: 156, width: 552, height: 120))
ctx.setFillColor(hex(0x1D1D2B))
ctx.addPath(CGPath(roundedRect: CGRect(x: 252, y: 196, width: 520, height: 112), cornerWidth: 56, cornerHeight: 56, transform: nil))
ctx.fillPath()
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: CGRect(x: 252, y: 216, width: 520, height: 112), cornerWidth: 56, cornerHeight: 56, transform: nil))
ctx.clip()
ctx.drawLinearGradient(gradient(hex(0x3A3A57), hex(0x2A2A40)), start: CGPoint(x: 0, y: 328), end: CGPoint(x: 0, y: 216), options: [])
ctx.restoreGState()
ctx.setFillColor(hex(0x101017))
ctx.addPath(CGPath(roundedRect: CGRect(x: 350, y: 256, width: 324, height: 34), cornerWidth: 17, cornerHeight: 17, transform: nil))
ctx.fillPath()
ctx.setFillColor(hex(0x00D4AA, 0.9))
ctx.addPath(CGPath(roundedRect: CGRect(x: 364, y: 262, width: 296, height: 5), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil))
ctx.fillPath()

// The lever: a stick from the gate, tilted, and a long grip on it.
let pivot = CGPoint(x: 470, y: 276)
let angle: CGFloat = -0.30                     // leaning right
ctx.saveGState()
ctx.translateBy(x: pivot.x, y: pivot.y)
ctx.rotate(by: angle)
// shadow
ctx.setFillColor(hex(0x05050A, 0.42))
ctx.addPath(CGPath(roundedRect: CGRect(x: -10, y: -18, width: 56, height: 400), cornerWidth: 28, cornerHeight: 28, transform: nil))
ctx.addPath(CGPath(roundedRect: CGRect(x: -44, y: 350, width: 124, height: 232), cornerWidth: 62, cornerHeight: 62, transform: nil))
ctx.fillPath()
ctx.translateBy(x: -16, y: 0)
// the stick
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: CGRect(x: -28, y: -10, width: 56, height: 400), cornerWidth: 28, cornerHeight: 28, transform: nil))
ctx.clip()
ctx.drawLinearGradient(gradient(hex(0xC2C2D2), hex(0x8E8EA6)), start: CGPoint(x: -28, y: 0), end: CGPoint(x: 28, y: 0), options: [])
ctx.restoreGState()
// the teal band where grip meets stick
ctx.setFillColor(hex(0x00D4AA))
ctx.addPath(CGPath(roundedRect: CGRect(x: -44, y: 352, width: 88, height: 28), cornerWidth: 11, cornerHeight: 10, transform: nil))
ctx.fillPath()
// the grip
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: CGRect(x: -62, y: 372, width: 124, height: 214), cornerWidth: 62, cornerHeight: 62, transform: nil))
ctx.clip()
ctx.drawLinearGradient(gradient(hex(0xFAFAFF), hex(0xC9C9DA)), start: CGPoint(x: -62, y: 0), end: CGPoint(x: 62, y: 0), options: [])
ctx.restoreGState()
ctx.setFillColor(hex(0xFFFFFF, 0.65))
ctx.addPath(CGPath(roundedRect: CGRect(x: -40, y: 410, width: 18, height: 140), cornerWidth: 9, cornerHeight: 8, transform: nil))
ctx.fillPath()
ctx.restoreGState()

// The boot where the stick enters the gate.
ctx.setFillColor(hex(0x101017))
ctx.fillEllipse(in: CGRect(x: pivot.x - 64, y: pivot.y - 24, width: 128, height: 52))
ctx.setFillColor(hex(0x1D1D2B))
ctx.fillEllipse(in: CGRect(x: pivot.x - 50, y: pivot.y - 6, width: 100, height: 34))

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("wrote", url.path)
