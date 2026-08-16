// Ask the system to thumbnail the USDZ, which is the cheapest way to make
// Apple's own USD stack parse and render it end to end. `qlmanage -t` is the
// obvious alternative and tends to hang; QLThumbnailGenerator does not.
import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count > 2 else {
    FileHandle.standardError.write(Data("usage: qlcheck <in.usdz> <out.png>\n".utf8))
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])

let request = QLThumbnailGenerator.Request(
    fileAt: input, size: CGSize(width: 512, height: 512), scale: 1,
    representationTypes: .all)

let done = DispatchSemaphore(value: 0)
var failure: Error?

QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, error in
    defer { done.signal() }
    if let error { failure = error; return }
    guard let cg = rep?.cgImage else { return }
    guard
        let dest = CGImageDestinationCreateWithURL(
            output as CFURL, UTType.png.identifier as CFString, 1, nil as CFDictionary?)
    else { return }
    CGImageDestinationAddImage(dest, cg, nil as CFDictionary?)
    CGImageDestinationFinalize(dest)
    print("ok \(cg.width)x\(cg.height) -> \(output.path)")
}

if done.wait(timeout: .now() + 60) == .timedOut {
    print("TIMED OUT")
    exit(1)
}
if let failure {
    print("FAILED: \(failure)")
    exit(1)
}
