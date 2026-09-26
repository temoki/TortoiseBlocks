// Records one window with ScreenCaptureKit — the pointer and its clicks
// included — until its standard input closes. `previews.rb` compiles and runs
// it for the Mac's preview.
//
//   window-recorder <bundle id> <title fragment> <out.mov>
//
// It waits for the window to appear, then prints `started <unix time>` once
// the file is being written: the test's log is in wall time, and that line is
// what lines the two up.
//
// The window alone rather than the screen: nothing else on the machine reaches
// the picture, the window can sit behind another and still be recorded, and
// the desktop around it comes from the same drawn plate the screenshots use.
import AVFoundation
import AppKit
import ScreenCaptureKit

final class Recording: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var finishWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStart = false
    private var didFinish = false

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        print("started \(Date().timeIntervalSince1970)")
        fflush(stdout)
        resume(&startWaiters, flag: \.didStart)
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        resume(&finishWaiters, flag: \.didFinish)
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        FileHandle.standardError.write(Data("recording failed: \(error)\n".utf8))
        exit(1)
    }

    func started() async { await wait(on: \.startWaiters, flag: \.didStart) }
    func finished() async { await wait(on: \.finishWaiters, flag: \.didFinish) }

    private func resume(
        _ waiters: inout [CheckedContinuation<Void, Never>],
        flag: ReferenceWritableKeyPath<Recording, Bool>
    ) {
        lock.lock()
        self[keyPath: flag] = true
        let pending = waiters
        waiters = []
        lock.unlock()
        for waiter in pending { waiter.resume() }
    }

    private func wait(
        on waiters: ReferenceWritableKeyPath<Recording, [CheckedContinuation<Void, Never>]>,
        flag: KeyPath<Recording, Bool>
    ) async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if self[keyPath: flag] {
                lock.unlock()
                continuation.resume()
            }
            else {
                self[keyPath: waiters].append(continuation)
                lock.unlock()
            }
        }
    }
}

@main
struct WindowRecorder {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else {
            FileHandle.standardError.write(
                Data("usage: window-recorder <bundle id> <title fragment> <out.mov>\n".utf8))
            exit(64)
        }
        let (bundle, title, out) = (arguments[1], arguments[2], URL(fileURLWithPath: arguments[3]))
        // A command-line tool has no window-server connection until something
        // asks for one, and a stream started without it stops the process on
        // an assertion (`CGS_REQUIRE_INIT`).
        _ = await MainActor.run { NSApplication.shared }

        // Waits for the window: the driver starts this beside the test, and the
        // document it records is not open yet.
        var found: SCWindow?
        let deadline = Date().addingTimeInterval(180)
        while found == nil, Date() < deadline {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            found = content.windows.first(where: {
                $0.owningApplication?.bundleIdentifier == bundle
                    && ($0.title ?? "").contains(title)
            })
            if found == nil { try await Task.sleep(for: .milliseconds(250)) }
        }
        guard let window = found else {
            FileHandle.standardError.write(Data("no window of \(bundle) titled \(title)\n".utf8))
            exit(1)
        }

        // The display with every other application taken out — the wallpaper
        // included, so outside the window's corners is black — cropped to the
        // window. Not the window by name: a window that is shared as itself
        // wears macOS's purple "sharing this window" control where its close,
        // minimise and zoom buttons belong, in every frame.
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.frame.intersects(window.frame) })
        else {
            FileHandle.standardError.write(Data("no display shows the window\n".utf8))
            exit(1)
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: content.applications.filter { $0.bundleIdentifier != bundle },
            exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.sourceRect = CGRect(
            x: window.frame.minX - display.frame.minX, y: window.frame.minY - display.frame.minY,
            width: window.frame.width, height: window.frame.height)
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = true
        configuration.showMouseClicks = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)

        let settings = SCRecordingOutputConfiguration()
        settings.outputURL = out
        settings.outputFileType = .mov
        settings.videoCodecType = .h264
        let recording = Recording()
        let output = SCRecordingOutput(configuration: settings, delegate: recording)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        await recording.started()

        // Until the driver closes standard input.
        await Task.detached { _ = FileHandle.standardInput.readDataToEndOfFile() }.value
        // The stream may have stopped already: it ends with the window, and the
        // test quits the app before the driver says stop.
        try? await stream.stopCapture()
        await recording.finished()
    }
}
