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

    /// Where a shot ends up. `canvas` and `code` are the two panes every
    /// platform has; `blocks` and `palette` are screens only a phone has, the
    /// program on its own and the palette sheet over it (#114).
    private enum Pane: String {
        case canvas
        case code
        case blocks
        case palette
    }

    /// Whether this run is on a phone, which is a different set of screens
    /// rather than the same ones laid out narrower (#113): the transport and
    /// the code pane live in a sheet that has to be raised, and the palette is
    /// a sheet of its own. Read from the device rather than passed in, so the
    /// driver's shot list stays a list of pictures.
    @MainActor
    private static var isPhone: Bool {
        #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .phone
        #else
            false
        #endif
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
            // The phone is portrait only (#113), and its captures are
            // portrait; there is nothing to turn and the setting would be
            // refused in silence.
            if !Self.isPhone {
                XCUIDevice.shared.orientation = .landscapeLeft
            }
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
        if Self.isPhone {
            openFromBrowser(app, sample: shot.sample, locale: locale, name: shot.name)
        }
        else {
            let document = URL(fileURLWithPath: documents)
                .appendingPathComponent("\(shot.sample).tortoise")
            XCUIDevice.shared.system.open(document)
        }

        // **A phone raises the transport in a sheet, so it is not on screen
        // yet** (#113). On iPad and Mac the scrubber is the sign that the
        // document opened; on a phone that sign is the run button in the
        // bottom bar, which is also what raises the canvas over the program.
        if Self.isPhone {
            // Addressed by SF Symbol for the same reason as everything else
            // here: the label is 「うごかす」 in one language and "Run" in the
            // other, and SwiftUI passes the symbol through as the identifier.
            let run = app.buttons["play.fill"].firstMatch
            XCTAssertTrue(
                run.waitForExistence(timeout: 30),
                "\(locale)/\(shot.name): the document never opened")

            switch shot.pane {
            case .blocks:
                break  // The program on its own; this screen is already it.
            case .palette:
                let palette = app.buttons["square.grid.2x2"].firstMatch
                XCTAssertTrue(
                    palette.waitForExistence(timeout: 15),
                    "\(locale)/\(shot.name): no palette button")
                palette.tap()
            case .canvas, .code:
                run.tap()
                let scrubber = app.sliders.firstMatch
                XCTAssertTrue(
                    scrubber.waitForExistence(timeout: 30),
                    "\(locale)/\(shot.name): the canvas sheet never opened")
                // No "before" value to compare against: the run starts with
                // the sheet, so the transport does not exist until it is
                // already under way. Nothing is in doubt about whether it
                // started.
                waitForDrawing(scrubber, startedBefore: nil)
                if shot.pane == .code { showCode(app, locale: locale, name: shot.name) }
            }
        }
        else {
            let scrubber = app.sliders.firstMatch
            XCTAssertTrue(
                scrubber.waitForExistence(timeout: 30),
                "\(locale)/\(shot.name): the document never opened")

            // **The drawing has to be run; there is no shortcut to the end.**
            // The scrubber is `Disabled` until something has been run — its
            // value reads 「まだ なにも うごかしていません」 — so dragging it
            // there does nothing at all, silently, and produces a capture that
            // looks perfectly well made of an empty canvas. So does
            // `adjust(toNormalizedSliderPosition:)`, and so does `⌘R`
            // (`AppCommands`), the simulator having no hardware keyboard
            // attached.
            //
            // The button is addressed as `play.fill`, the SF Symbol's own
            // name: SwiftUI hands it through as the accessibility identifier,
            // so it is the same in both languages while the label
            // ("うごかす") is not.
            let play = app.buttons["play.fill"]
            XCTAssertTrue(
                play.waitForExistence(timeout: 15), "\(locale)/\(shot.name): no play button")
            play.tap()

            waitForDrawing(scrubber, startedBefore: scrubber.value as? String)

            if shot.pane == .code { showCode(app, locale: locale, name: shot.name) }
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
            // perfectly good picture of the wrong thing. A phone is the other
            // way round: portrait is what it is locked to, so a landscape
            // capture there means the lock stopped working, not that a
            // rotation was missed.
            if Self.isPhone {
                XCTAssertGreaterThan(
                    screenshot.image.size.height, screenshot.image.size.width,
                    "\(locale)/\(shot.name): the phone is not portrait")
            }
            else {
                XCTAssertGreaterThan(
                    screenshot.image.size.width, screenshot.image.size.height,
                    "\(locale)/\(shot.name): the device did not rotate")
            }
        #endif

        let attachment = Self.attachment(for: screenshot)
        attachment.name = "\(locale)|\(shot.name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.terminate()
    }

    /// Opens the sample's document from the app's own document browser (#114).
    ///
    /// **A phone cannot be handed a document by URL at all.** Measured every
    /// way round: `XCUIDevice.system.open` raises a *save* panel rather than
    /// opening the file, wherever the file sits — the device's tmp, the app's
    /// own Documents, either. `simctl openurl` does open it, but only into a
    /// cold launch and only from the driver, whose open the following
    /// `xcodebuild test` then kills by installing. And an iOS app cannot open
    /// one of its own documents in code: `openDocument` is macOS-only.
    /// Tapping is what is left, so the driver seeds the app's *own* folder and
    /// this walks to it. An iPad is handed the URL as before.
    ///
    /// **Two of the four steps are by index, and both have to be.** The tab
    /// bar reads Recents / Shared / Browse, and the locations read iCloud
    /// Drive / On My iPhone / Recently Deleted — system labels, and their
    /// accessibility identifiers carry the *localized* name
    /// (`DOC.sidebar.item.このiPhone内`), so there is nothing language-stable
    /// to match on. From there the names are ours and the same in every
    /// language: the folder is the app's, and the file is the file.
    @MainActor
    private func openFromBrowser(
        _ app: XCUIApplication, sample: String, locale: String, name: String
    ) {
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(
            tabs.waitForExistence(timeout: 30), "\(locale)/\(name): no document browser")
        tabs.buttons.element(boundBy: 2).tap()

        // **A ladder, not a walk, because the browser remembers where it was.**
        // A second run in the same session opened Browse *inside* the app's
        // folder rather than at the list of locations, and a fixed four-step
        // walk then failed on a step that was already behind it (measured: the
        // second locale of a reshoot, every time). So each rung is tried from
        // the bottom up, and only the ones still ahead are climbed.
        if tap(app, cell: "\(sample).tortoise") { return }

        if !tap(app, cell: "Tortoise Blocks") {
            // The locations: iCloud Drive, On My iPhone, Recently Deleted.
            // By index like the tab bar, and for the same reason — their
            // accessibility identifiers carry the *localized* name
            // (`DOC.sidebar.item.このiPhone内`), so there is nothing
            // language-stable to match on.
            let location = app.cells.matching(
                NSPredicate(format: "identifier BEGINSWITH 'DOC.sidebar.item.'")
            ).element(boundBy: 1)
            XCTAssertTrue(
                location.waitForExistence(timeout: 15),
                "\(locale)/\(name): no On My iPhone")
            location.tap()
            XCTAssertTrue(
                tap(app, cell: "Tortoise Blocks", timeout: 15),
                "\(locale)/\(name): no app folder")
        }

        XCTAssertTrue(
            tap(app, cell: "\(sample).tortoise", timeout: 15),
            "\(locale)/\(name): no \(sample).tortoise")
    }

    /// Taps the first cell whose identifier starts with `prefix`, if there is
    /// one. A file's reads "star.tortoise, tortoise" and a folder's
    /// "Tortoise Blocks, Container", so the prefix is the name itself — ours
    /// in both cases, and so the same in every language.
    @MainActor
    private func tap(_ app: XCUIApplication, cell prefix: String, timeout: TimeInterval = 5)
        -> Bool
    {
        let cell = app.cells.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        ).firstMatch
        guard cell.waitForExistence(timeout: timeout) else { return false }

        cell.tap()
        return true
    }

    /// Waits for the drawing to stop growing, by watching the scrubber's own
    /// accessibility value. Better than sleeping for a guessed duration: the
    /// tree is twice the spiral, so a fixed wait is either wrong for one of
    /// them or wasteful for all of them.
    ///
    /// `startedBefore` is the value the scrubber held *before* the run was
    /// started, where the caller had one to read. Quiet polls that still hold
    /// that value mean "nothing has happened yet", not "done" — which is a
    /// real failure on iPad and Mac, where the transport is on screen before
    /// anything runs. A phone has no such value: its transport arrives with
    /// the sheet the run opened.
    @MainActor
    private func waitForDrawing(_ scrubber: XCUIElement, startedBefore idle: String?) {
        var last = scrubber.value as? String
        var settled = 0
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            let now = scrubber.value as? String
            settled = (now == last) ? settled + 1 : 0
            last = now
            // Four quiet polls, and not still the value it had before the run
            // started — otherwise "nothing has happened yet" reads as "done".
            if settled >= 4, idle == nil || now != idle { break }
        }
    }

    /// Switches the pane to the generated Swift.
    ///
    /// Canvas is the first choice and Code the second (`CanvasViewToggle`) —
    /// an order, not a label.
    ///
    /// **The same `Picker(.segmented)` is a different element on each
    /// platform**: a `SegmentedControl` of buttons on iOS, a `RadioGroup` of
    /// radio buttons in the toolbar on macOS. Looking for the iOS one on a Mac
    /// finds nothing and times out saying only that there is no toggle.
    @MainActor
    private func showCode(_ app: XCUIApplication, locale: String, name: String) {
        #if os(macOS)
            let toggle = app.radioGroups.firstMatch
            XCTAssertTrue(
                toggle.waitForExistence(timeout: 10), "\(locale)/\(name): no pane toggle")
            toggle.radioButtons.element(boundBy: 1).click()
        #else
            let toggle = app.segmentedControls.firstMatch
            XCTAssertTrue(
                toggle.waitForExistence(timeout: 10), "\(locale)/\(name): no pane toggle")
            toggle.buttons.element(boundBy: 1).tap()
        #endif
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
