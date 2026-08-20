import UIKit
import XCTest

/// Produces the iPad App Store captures. Driven by `Tools/ipad-shots.rb`,
/// which is where the shot list lives; this is only the hands.
///
/// **Why a UI test and not launch arguments**, which is how the visionOS
/// captures are made: those need the app to open a drawing and put it down,
/// and nothing else. These need the iPad rotated into landscape, a document
/// opened, a program run to its end, and a pane switched — and `simctl` can do
/// exactly one of those. Rotation is the deciding one: there is no `simctl`
/// command for it, and driving the Simulator's own menu means granting
/// keystroke permission to whatever runs the script. `XCUIDevice` rotates in a
/// line, so the whole set comes from one mechanism and the app keeps no
/// screenshot-only code at all.
///
/// **Nothing here is matched by its label.** Both languages are shot from the
/// same code, so a label is whatever the app happens to be speaking; what is
/// stable is an element's *type*, its *position*, and — for the transport —
/// its SF Symbol name, which SwiftUI passes through as the accessibility
/// identifier.
final class ScreenshotTests: XCTestCase {
    /// One capture: which sample to open, and which pane to end up on.
    private struct Shot {
        let name: String
        let sample: String
        let pane: Pane
    }

    private enum Pane: String {
        case canvas
        case code
    }

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptures() throws {
        let documents = try environment("TB_DOCUMENTS")
        let shots = try environment("TB_SHOTS").split(separator: ",").map { entry -> Shot in
            let fields = entry.split(separator: ":")
            return Shot(
                name: String(fields[0]), sample: String(fields[1]),
                pane: Pane(rawValue: String(fields[2])) ?? .canvas)
        }
        // **One locale per run, on purpose.** Opening a document that is not
        // in the app's own folder imports a copy, and the name is
        // deduplicated — `star-2` — which then shows in the capture's title
        // bar. The driver uninstalls the app before each run, which resets
        // that history; two languages in one run would spend it.
        let locale = try environment("TB_LOCALE")
        let language = try environment("TB_LANGUAGE")

        for shot in shots {
            capture(shot, documents: documents, locale: locale, language: language)
        }
    }

    @MainActor
    private func capture(_ shot: Shot, documents: String, locale: String, language: String) {
        let app = XCUIApplication()
        // The app's own language, for this launch only — so nothing is left
        // switched on the device afterwards.
        app.launchArguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "ja" ? "ja_JP" : "en_US",
        ]
        app.launch()

        // **After the launch, not before.** A device rotated while no app is
        // in front comes back portrait when one arrives, so an orientation set
        // first is silently undone and every capture lands 2064×2752 — the
        // wrong way round for a listing whose other captures are landscape.
        XCUIDevice.shared.orientation = .landscapeLeft

        // Straight to the drawing, rather than tapping through the document
        // browser: the browser's own layout is not ours to depend on, and it
        // is one more thing that differs between languages.
        //
        // The documents sit in the *device's* tmp, not in the app's container,
        // and that is not a shortcut: preparing the run reinstalls the app, and
        // a reinstall gives it a new data container — so anything seeded there
        // beforehand is gone by the time this opens it. Outside the container
        // the files survive, and LaunchServices grants the app access to what
        // it is handed, exactly as it does for a file opened from Files.
        let document = URL(fileURLWithPath: documents)
            .appendingPathComponent("\(shot.sample).tortoise")
        XCUIDevice.shared.system.open(document)

        let scrubber = app.sliders.firstMatch
        XCTAssertTrue(
            scrubber.waitForExistence(timeout: 30),
            "\(locale)/\(shot.name): the document never opened")

        // **The drawing has to be run; there is no shortcut to the end.** The
        // scrubber is `Disabled` until something has been run — its value
        // reads 「まだ なにも うごかしていません」 — so dragging it there does
        // nothing at all, silently, and produces a capture that looks
        // perfectly well made of an empty canvas. So does
        // `adjust(toNormalizedSliderPosition:)`, and so does `⌘R`
        // (`AppCommands`), the simulator having no hardware keyboard attached.
        //
        // The button is addressed as `play.fill`, the SF Symbol's own name:
        // SwiftUI hands it through as the accessibility identifier, so it is
        // the same in both languages while the label ("うごかす") is not.
        let play = app.buttons["play.fill"]
        XCTAssertTrue(
            play.waitForExistence(timeout: 15), "\(locale)/\(shot.name): no play button")
        play.tap()

        // Then wait for the drawing to stop growing, by watching the
        // scrubber's own accessibility value. Better than sleeping for a
        // guessed duration: the tree is twice the spiral, so a fixed wait is
        // either wrong for one of them or wasteful for all of them.
        let idle = scrubber.value as? String
        var last = idle
        var settled = 0
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            let now = scrubber.value as? String
            settled = (now == last) ? settled + 1 : 0
            last = now
            // Four quiet polls, and not still the value it had before the run
            // started — otherwise "nothing has happened yet" reads as "done".
            if settled >= 4, now != idle { break }
        }

        if shot.pane == .code {
            // Canvas is the first segment and Code the second
            // (`CanvasViewToggle`) — an order, not a label.
            let toggle = app.segmentedControls.firstMatch
            XCTAssertTrue(
                toggle.waitForExistence(timeout: 10), "\(locale)/\(shot.name): no pane toggle")
            toggle.buttons.element(boundBy: 1).tap()
        }

        // The canvas flushes its frames on the next redraw; a capture taken in
        // the same runloop turn catches the drawing half-made.
        Thread.sleep(forTimeInterval: 2)

        let screenshot = XCUIScreen.main.screenshot()
        // Cheap, and it has already caught the one failure that produces a
        // perfectly good picture of the wrong thing.
        XCTAssertGreaterThan(
            screenshot.image.size.width, screenshot.image.size.height,
            "\(locale)/\(shot.name): the device did not rotate")

        let attachment = XCTAttachment(
            data: Self.png(of: screenshot), uniformTypeIdentifier: "public.png")
        attachment.name = "\(locale)|\(shot.name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.terminate()
    }

    /// The screenshot as a PNG the right way up.
    ///
    /// `XCTAttachment(screenshot:)` writes the framebuffer as it is held —
    /// portrait — and leaves the rotation to a flag on the image, so a
    /// landscape capture arrives 2064×2752 with the content on its side. The
    /// rotation is baked in here instead, by drawing the image once: `UIImage`
    /// reports the *displayed* size, so the redraw comes out 2752×2064 with
    /// the pixels to match.
    private static func png(of screenshot: XCUIScreenshot) -> Data {
        let image = screenshot.image
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }.pngData()!
    }

    /// Passed in by the driver as `TEST_RUNNER_<name>` — **set on xcodebuild's
    /// own environment, not as a build setting after the command**, which is
    /// accepted, ignored, and arrives nowhere.
    private func environment(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw XCTSkip("\(name) is not set — run this through Tools/ipad-shots.rb")
        }
        return value
    }
}
