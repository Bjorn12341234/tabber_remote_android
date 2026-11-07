import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Tabber Spak's icon: a spak, a lever, whose knob is the record button's red.
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: space, components: [r, g, b, a])! }
func gradient(_ a: CGColor, _ b: CGColor) -> CGGradient { CGGradient(colorsSpace: space, colors: [a, b] as CFArray, locations: [0, 1])! }

// Background
ctx.drawLinearGradient(gradient(color(0.15, 0.16, 0.19), color(0.06, 0.065, 0.08)),
                       start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 0, y: 0), options: [])

// Base plate, seen from slightly above
ctx.setFillColor(color(0.03, 0.035, 0.045, 0.6))
ctx.fillEllipse(in: CGRect(x: 262, y: 150, width: 500, height: 150))         // shadow
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: 272, y: 180, width: 480, height: 150))
ctx.clip()
ctx.drawLinearGradient(gradient(color(0.30, 0.32, 0.37), color(0.16, 0.17, 0.20)),
                       start: CGPoint(x: 0, y: 330), end: CGPoint(x: 0, y: 180), options: [])
ctx.restoreGState()
// The rubber boot around the pivot
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: 402, y: 225, width: 220, height: 110))
ctx.clip()
ctx.drawLinearGradient(gradient(color(0.09, 0.095, 0.11), color(0.04, 0.045, 0.055)),
                       start: CGPoint(x: 0, y: 335), end: CGPoint(x: 0, y: 225), options: [])
ctx.restoreGState()

// The stick, tilted forward and to the right
let pivot = CGPoint(x: 512, y: 282)
let top = CGPoint(x: 648, y: 690)
ctx.setLineCap(.round)
ctx.setStrokeColor(color(0.20, 0.21, 0.24))
ctx.setLineWidth(70)
ctx.move(to: pivot); ctx.addLine(to: top); ctx.strokePath()
ctx.setStrokeColor(color(0.78, 0.80, 0.84))
ctx.setLineWidth(52)
ctx.move(to: pivot); ctx.addLine(to: top); ctx.strokePath()
ctx.setStrokeColor(color(0.95, 0.96, 0.98, 0.85))
ctx.setLineWidth(14)
ctx.move(to: CGPoint(x: pivot.x - 12, y: pivot.y + 30)); ctx.addLine(to: CGPoint(x: top.x - 14, y: top.y - 10)); ctx.strokePath()

// The knob: the record button's red, with light on it
let knob = CGRect(x: top.x - 132, y: top.y - 110, width: 264, height: 264)
ctx.setFillColor(color(0.03, 0.035, 0.045, 0.45))
ctx.fillEllipse(in: knob.offsetBy(dx: 10, dy: -16))
ctx.saveGState()
ctx.addEllipse(in: knob)
ctx.clip()
ctx.drawRadialGradient(gradient(color(0.98, 0.42, 0.44), color(0.72, 0.16, 0.19)),
                       startCenter: CGPoint(x: knob.midX - 50, y: knob.midY + 60), startRadius: 10,
                       endCenter: CGPoint(x: knob.midX, y: knob.midY), endRadius: 150, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()
ctx.setFillColor(color(1, 1, 1, 0.30))
ctx.fillEllipse(in: CGRect(x: knob.minX + 58, y: knob.midY + 38, width: 92, height: 62))

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote", url.path)
