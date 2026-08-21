import XCTest

#if canImport(UIKit)
    import UIKit
#endif

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
        // **macOS reopens the windows it had when it quit.** Each shot ends by
        // terminating the app, so without this the next launch restores the
        // previous drawing *and* then opens the new one — two windows, two
        // transports, and `play.fill` stops being a single element ("Multiple
        // matching elements found", which does not mention restoration at
        // all). iOS has no equivalent and needs no equivalent.
        #if os(macOS)
            app.launchArguments += ["-NSQuitAlwaysKeepsWindows", "NO"]
        #endif
        app.launch()

        // **Close whatever came back with it.** A shot ends by terminating the
        // app, and macOS reopens the windows it had when it quit — so the
        // second shot's launch restores the first shot's drawing and then
        // opens its own beside it. Two windows means two transports, and
        // `play.fill` stops being a single element; the failure says "Multiple
        // matching elements found" and nothing about restoration.
        #if os(macOS)
            for window in app.windows.allElementsBoundByIndex where window.exists {
                window.buttons[XCUIIdentifierCloseWindow].click()
            }
        #endif

        // **After the launch, not before.** A device rotated while no app is
        // in front comes back portrait when one arrives, so an orientation set
        // first is silently undone and every capture lands 2064×2752 — the
        // wrong way round for a listing whose other captures are landscape.
        //
        // A Mac has no orientation, and `XCUIDevice` has no such member there.
        #if os(iOS)
            XCUIDevice.shared.orientation = .landscapeLeft
        #endif

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
            // Canvas is the first choice and Code the second
            // (`CanvasViewToggle`) — an order, not a label.
            //
            // **The same `Picker(.segmented)` is a different element on each
            // platform**: a `SegmentedControl` of buttons on iOS, a
            // `RadioGroup` of radio buttons in the toolbar on macOS. Looking
            // for the iOS one on a Mac finds nothing and times out saying only
            // that there is no toggle.
            #if os(macOS)
                let toggle = app.radioGroups.firstMatch
                XCTAssertTrue(
                    toggle.waitForExistence(timeout: 10),
                    "\(locale)/\(shot.name): no pane toggle")
                toggle.radioButtons.element(boundBy: 1).click()
            #else
                let toggle = app.segmentedControls.firstMatch
                XCTAssertTrue(
                    toggle.waitForExistence(timeout: 10),
                    "\(locale)/\(shot.name): no pane toggle")
                toggle.buttons.element(boundBy: 1).tap()
            #endif
        }

        // The canvas flushes its frames on the next redraw; a capture taken in
        // the same runloop turn catches the drawing half-made.
        Thread.sleep(forTimeInterval: 2)

        // **The Mac captures the window, not the screen.** What is around it —
        // the desktop and the menu bar — is a plate prepared once per language
        // and composited under this by the driver, so the capture does not
        // depend on what the machine's own desktop happens to look like. On
        // iPad the screen *is* the picture.
        #if os(macOS)
            let screenshot = app.windows.firstMatch.screenshot()
        #else
            let screenshot = XCUIScreen.main.screenshot()
            // Cheap, and it has already caught the one failure that produces a
            // perfectly good picture of the wrong thing.
            XCTAssertGreaterThan(
                screenshot.image.size.width, screenshot.image.size.height,
                "\(locale)/\(shot.name): the device did not rotate")
        #endif

        let attachment = Self.attachment(for: screenshot)
        attachment.name = "\(locale)|\(shot.name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.terminate()
    }

    /// The screenshot as an attachment, the right way up.
    ///
    /// Only iOS needs the redraw below; a Mac window is never held sideways.
    private static func attachment(for screenshot: XCUIScreenshot) -> XCTAttachment {
        #if os(iOS)
            XCTAttachment(data: png(of: screenshot), uniformTypeIdentifier: "public.png")
        #else
            XCTAttachment(screenshot: screenshot)
        #endif
    }

    /// The screenshot as a PNG the right way up.
    ///
    /// `XCTAttachment(screenshot:)` writes the framebuffer as it is held —
    /// portrait — and leaves the rotation to a flag on the image, so a
    /// landscape capture arrives 2064×2752 with the content on its side. The
    /// rotation is baked in here instead, by drawing the image once: `UIImage`
    /// reports the *displayed* size, so the redraw comes out 2752×2064 with
    /// the pixels to match.
    #if os(iOS)
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
    #endif

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
