import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("RunRat/Assets.xcassets")

struct RatFrame {
    let bodyYOffset: CGFloat
    let frontLeg: CGFloat
    let rearLeg: CGFloat
    let tailLift: CGFloat
}

let frames = [
    RatFrame(bodyYOffset: 3, frontLeg: -10, rearLeg: 8, tailLift: 4),
    RatFrame(bodyYOffset: 1, frontLeg: -4, rearLeg: 12, tailLift: 9),
    RatFrame(bodyYOffset: 0, frontLeg: 7, rearLeg: 2, tailLift: 13),
    RatFrame(bodyYOffset: 2, frontLeg: 12, rearLeg: -8, tailLift: 7),
    RatFrame(bodyYOffset: 4, frontLeg: 3, rearLeg: -12, tailLift: 1),
    RatFrame(bodyYOffset: 2, frontLeg: -8, rearLeg: -3, tailLift: -2),
]

func drawRat(in rect: CGRect, frame: RatFrame, color: NSColor) {
    let scale = min(rect.width / 178, rect.height / 137)
    let transform = NSAffineTransform()
    transform.translateX(by: rect.midX - 89 * scale, yBy: rect.midY - 68.5 * scale)
    transform.scale(by: scale)
    transform.concat()

    color.setFill()
    color.setStroke()

    let y = frame.bodyYOffset

    let tail = NSBezierPath()
    tail.lineWidth = 9
    tail.lineCapStyle = .round
    tail.move(to: NSPoint(x: 37, y: 70 + y))
    tail.curve(
        to: NSPoint(x: 7, y: 97 + frame.tailLift),
        controlPoint1: NSPoint(x: 21, y: 76 + frame.tailLift),
        controlPoint2: NSPoint(x: 11, y: 87 + frame.tailLift)
    )
    tail.stroke()

    NSBezierPath(ovalIn: NSRect(x: 38, y: 45 + y, width: 82, height: 43)).fill()
    NSBezierPath(ovalIn: NSRect(x: 101, y: 55 + y, width: 44, height: 31)).fill()
    NSBezierPath(ovalIn: NSRect(x: 108, y: 79 + y, width: 15, height: 15)).fill()
    NSBezierPath(ovalIn: NSRect(x: 133, y: 66 + y, width: 9, height: 8)).fill()

    let nose = NSBezierPath()
    nose.move(to: NSPoint(x: 145, y: 68 + y))
    nose.line(to: NSPoint(x: 158, y: 72 + y))
    nose.line(to: NSPoint(x: 145, y: 78 + y))
    nose.close()
    nose.fill()

    let frontLeg = NSBezierPath()
    frontLeg.lineWidth = 7
    frontLeg.lineCapStyle = .round
    frontLeg.move(to: NSPoint(x: 107, y: 52 + y))
    frontLeg.line(to: NSPoint(x: 114 + frame.frontLeg, y: 28))
    frontLeg.stroke()

    let rearLeg = NSBezierPath()
    rearLeg.lineWidth = 8
    rearLeg.lineCapStyle = .round
    rearLeg.move(to: NSPoint(x: 67, y: 51 + y))
    rearLeg.line(to: NSPoint(x: 55 + frame.rearLeg, y: 29))
    rearLeg.stroke()
}

func image(size: CGSize, background: NSColor? = nil, ratColor: NSColor, frame: RatFrame) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    if let background {
        background.setFill()
        NSBezierPath(roundedRect: CGRect(origin: .zero, size: size), xRadius: size.width * 0.18, yRadius: size.height * 0.18).fill()
    }

    drawRat(in: CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.08, dy: size.height * 0.18), frame: frame, color: ratColor)
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "RunRatAssetGeneration", code: 1)
    }

    try png.write(to: url, options: .atomic)
}

for (index, frame) in frames.enumerated() {
    let directory = assets.appendingPathComponent("runRat\(index).imageset")
    let path = directory.appendingPathComponent("runRat\(index).png")
    try writePNG(image(size: CGSize(width: 178, height: 137), ratColor: .black, frame: frame), to: path)
}

let iconDirectory = assets.appendingPathComponent("AppIcon.appiconset")
let iconSizes = [16, 32, 128, 256, 512]
let background = NSColor(red: 0.91, green: 0.96, blue: 0.92, alpha: 1)
let rat = NSColor(red: 0.13, green: 0.12, blue: 0.11, alpha: 1)

for size in iconSizes {
    try writePNG(
        image(size: CGSize(width: size, height: size), background: background, ratColor: rat, frame: frames[2]),
        to: iconDirectory.appendingPathComponent("\(size)x\(size).png")
    )
    try writePNG(
        image(size: CGSize(width: size * 2, height: size * 2), background: background, ratColor: rat, frame: frames[2]),
        to: iconDirectory.appendingPathComponent("\(size)x\(size)@2x.png")
    )
}
