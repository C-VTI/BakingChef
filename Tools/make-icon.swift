// Renders the BakingChef app icon (1024×1024, no alpha).
// Usage: swiftc Tools/make-icon.swift -o /tmp/make-icon && /tmp/make-icon <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let cream = rgb(0xF4E4C4)
let creamDark = rgb(0xEBD3A8)
let crust = rgb(0xE2B77C)
let crumb = rgb(0xF8EBD0)
let ink = rgb(0x5A3A28)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Use a top-left origin like SVG.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Background: soft radial vignette.
let bg = CGGradient(colorsSpace: cs, colors: [cream, creamDark] as CFArray, locations: [0.55, 1])!
ctx.drawRadialGradient(bg, startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 512), endRadius: 760, options: [.drawsAfterEndLocation])

// Decorative tapered swooshes above the loaf.
func swoosh(from a: CGPoint, to b: CGPoint, control c: CGPoint, width: CGFloat) {
    let p = CGMutablePath()
    p.move(to: a)
    p.addQuadCurve(to: b, control: CGPoint(x: c.x, y: c.y - width / 2))
    p.addQuadCurve(to: a, control: CGPoint(x: c.x, y: c.y + width / 2))
    ctx.addPath(p)
    ctx.setFillColor(ink)
    ctx.fillPath()
}
swoosh(from: CGPoint(x: 250, y: 300), to: CGPoint(x: 470, y: 262), control: CGPoint(x: 380, y: 262), width: 30)
swoosh(from: CGPoint(x: 774, y: 300), to: CGPoint(x: 554, y: 262), control: CGPoint(x: 644, y: 262), width: 30)
// Small wheat-ear diamond between the swooshes.
let d = CGMutablePath()
d.move(to: CGPoint(x: 512, y: 236)); d.addLine(to: CGPoint(x: 534, y: 262))
d.addLine(to: CGPoint(x: 512, y: 288)); d.addLine(to: CGPoint(x: 490, y: 262)); d.closeSubpath()
ctx.addPath(d); ctx.setFillColor(ink); ctx.fillPath()

// Ground shadow.
ctx.setFillColor(rgb(0xDCC092))
ctx.fillEllipse(in: CGRect(x: 200, y: 690, width: 640, height: 56))

// Loaf body (bâtard).
let loaf = CGMutablePath()
loaf.move(to: CGPoint(x: 150, y: 600))
loaf.addCurve(to: CGPoint(x: 874, y: 585), control1: CGPoint(x: 170, y: 330), control2: CGPoint(x: 850, y: 320))
loaf.addCurve(to: CGPoint(x: 150, y: 600), control1: CGPoint(x: 900, y: 760), control2: CGPoint(x: 130, y: 770))
loaf.closeSubpath()

ctx.saveGState()
ctx.addPath(loaf)
ctx.clip()
let crustGradient = CGGradient(colorsSpace: cs, colors: [rgb(0xEFCB93), crust, rgb(0xC9935A)] as CFArray,
                               locations: [0, 0.6, 1])!
ctx.drawLinearGradient(crustGradient, start: CGPoint(x: 512, y: 380), end: CGPoint(x: 512, y: 720), options: [])
// Layered crust lines on the left end, echoing the bottom curve.
ctx.setStrokeColor(ink)
ctx.setLineWidth(14)
for (i, inset) in [CGFloat(40), 85, 130].enumerated() {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 150 + inset * 0.6, y: 560 - CGFloat(i) * 6))
    p.addCurve(to: CGPoint(x: 330 + inset * 1.2, y: 700 - inset * 0.25),
               control1: CGPoint(x: 160 + inset, y: 650), control2: CGPoint(x: 230 + inset, y: 690 - inset * 0.2))
    ctx.addPath(p)
}
ctx.strokePath()
ctx.restoreGState()

// Scores: lens shapes slanting across the top.
func score(center c: CGPoint, length: CGFloat, width: CGFloat, angle: CGFloat) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle)
    let p = CGMutablePath()
    p.move(to: CGPoint(x: -length / 2, y: 0))
    p.addQuadCurve(to: CGPoint(x: length / 2, y: 0), control: CGPoint(x: 0, y: -width))
    p.addQuadCurve(to: CGPoint(x: -length / 2, y: 0), control: CGPoint(x: 0, y: width))
    ctx.addPath(p)
    ctx.setFillColor(crumb)
    ctx.fillPath()
    // Crumb texture dots.
    ctx.setFillColor(rgb(0xC9935A))
    for (x, y) in [(-0.22, -0.1), (0.05, 0.12), (0.2, -0.05), (-0.05, -0.15), (0.12, 0.2), (-0.15, 0.15)] {
        ctx.fillEllipse(in: CGRect(x: length * x - 5, y: width * y - 5, width: 10, height: 10))
    }
    ctx.addPath(p)
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(14)
    ctx.strokePath()
    ctx.restoreGState()
}
let angle: CGFloat = .pi / 3.2
score(center: CGPoint(x: 400, y: 470), length: 170, width: 52, angle: angle)
score(center: CGPoint(x: 540, y: 455), length: 170, width: 52, angle: angle)
score(center: CGPoint(x: 680, y: 475), length: 150, width: 46, angle: angle)

// Loaf outline.
ctx.addPath(loaf)
ctx.setStrokeColor(ink)
ctx.setLineWidth(22)
ctx.strokePath()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
precondition(CGImageDestinationFinalize(dest), "could not write \(out)")
print("wrote \(out)")
