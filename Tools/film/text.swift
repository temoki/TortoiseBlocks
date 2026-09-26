// Renders one line of text to a transparent PNG, in SF Pro Rounded — the
// face the app's own titles use. `teaser.rb` compiles and runs it.
//
//   text <out.png> <text> <point size> <bold|semibold|heavy> <hex colour>
//
// A Swift script rather than ImageMagick's `-annotate`, because the system
// font is a variable font and only AppKit can ask it for a weight and the
// rounded design; ImageMagick draws whatever instance FreeType hands it.
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 6, let size = Double(arguments[3]), let hex = Int(arguments[5], radix: 16)
else {
    FileHandle.standardError.write(
        Data("usage: text <out.png> <text> <size> <weight> <hex>\n".utf8))
    exit(64)
}
let weight: NSFont.Weight =
    switch arguments[4] {
    case "heavy": .heavy
    case "semibold": .semibold
    default: .bold
    }
let colour = NSColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)

let system = NSFont.systemFont(ofSize: size, weight: weight)
let font =
    system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) }
    ?? system
let string = NSAttributedString(
    string: arguments[2], attributes: [.font: font, .foregroundColor: colour])
let bounds = string.boundingRect(with: .zero, options: [.usesLineFragmentOrigin])
let pad = size * 0.4

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(ceil(bounds.width + pad * 2)),
    pixelsHigh: Int(ceil(bounds.height + pad * 2)), bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
string.draw(at: NSPoint(x: pad, y: pad))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(
    to: URL(fileURLWithPath: arguments[1]))
