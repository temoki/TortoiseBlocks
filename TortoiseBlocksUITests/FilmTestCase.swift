// iPhone and iPad only: the films are shot on the simulators, and orientation,
// `XCUIDevice.system` and the keyboard keys this leans on do not exist on a
// Mac, which builds this target too (for `ScreenshotTests`).
#if os(iOS)

    import XCTest

    /// What the films' scripts are made of — the teaser (`TeaserTests`) and the
    /// App Store previews (`AppPreviewTests`), which `Tools/film/` records and
    /// cuts.
    ///
    /// A script presses, and writes down when and where each press happened,
    /// when each caption belongs, where the camera should look and which
    /// moments are worth holding, so the driver can draw the touches and cut
    /// the recording from the log. It decides nothing about the film itself.
    ///
    /// Everything is addressed in points on the screen as the app is held,
    /// which is what both `XCUIElement.frame` and the log use; the driver maps
    /// them onto the recording.
    class FilmTestCase: XCTestCase {
        var app: XCUIApplication!
        private var events: FileHandle?

        override func setUp() {
            continueAfterFailure = false
        }

        /// Opens `document` and runs `script` over it, logging as it goes.
        ///
        /// On an iPad the document is handed over by URL from the device's
        /// tmp, which survives the reinstall a test run does. A phone cannot be
        /// handed one at all (see `ScreenshotTests.openFromBrowser`), so there
        /// the driver seeds the app's own folder and this walks the document
        /// browser to it.
        @MainActor
        func film(_ document: String, landscape: Bool, script: () throws -> Void) throws {
            let documents = try environment("TB_DOCUMENTS")
            let log = try environment("TB_EVENTS")
            FileManager.default.createFile(atPath: log, contents: nil)
            events = FileHandle(forWritingAtPath: log)
            defer { try? events?.close() }

            app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            // After the launch, not before: a device turned while no app is in
            // front comes back portrait when one arrives.
            if landscape { XCUIDevice.shared.orientation = .landscapeLeft }

            if UIDevice.current.userInterfaceIdiom == .phone {
                try openFromBrowser("\(document).tortoise")
            }
            else {
                XCUIDevice.shared.system.open(
                    URL(fileURLWithPath: documents).appendingPathComponent("\(document).tortoise"))
            }

            let play = app.buttons["play.fill"].firstMatch
            XCTAssertTrue(play.waitForExistence(timeout: 30), "the document never opened")
            record(["type": "screen", "w": app.frame.width, "h": app.frame.height])
            pause(2)
            record(["type": "start"])

            // A run that stops half-way leaves the screen as it last saw it
            // beside the log, so it says what *was* there and not only what was
            // missing.
            do {
                try script()
            }
            catch {
                try? app.debugDescription.write(
                    toFile: log + ".failure.txt", atomically: true, encoding: .utf8)
                throw error
            }

            record(["type": "end"])
            pause(1)
        }

        /// Browse → the locations → the app's folder → the file, climbing only
        /// the rungs still ahead: the browser remembers where it was left.
        @MainActor
        private func openFromBrowser(_ file: String) throws {
            let tabs = app.tabBars.firstMatch
            guard tabs.waitForExistence(timeout: 30) else { throw FilmError.missing("the browser") }
            tabs.buttons.element(boundBy: 2).tap()
            if tapCell(file) { return }
            if !tapCell("Tortoise Blocks") {
                // By index: the locations' identifiers carry their localized
                // names, so nothing about them is language-stable.
                let location = app.cells.matching(
                    NSPredicate(format: "identifier BEGINSWITH 'DOC.sidebar.item.'")
                ).element(boundBy: 1)
                guard location.waitForExistence(timeout: 15) else {
                    throw FilmError.missing("On My iPhone")
                }
                location.tap()
                guard tapCell("Tortoise Blocks", timeout: 15) else {
                    throw FilmError.missing("the app's folder")
                }
            }
            guard tapCell(file, timeout: 15) else { throw FilmError.missing(file) }
        }

        @MainActor
        private func tapCell(_ prefix: String, timeout: TimeInterval = 5) -> Bool {
            let cell = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
                .firstMatch
            guard cell.waitForExistence(timeout: timeout) else { return false }
            cell.tap()
            return true
        }

        // MARK: - The hands

        /// A palette entry by its title, scrolled on screen first if it is not.
        ///
        /// The title is not unique: the transport's step button is "Forward"
        /// too. Of every button with that label this is the one furthest left,
        /// since the palette is the first column — read from one snapshot,
        /// because walking a query's matches one by one raced the UI and lost an
        /// element between counting and fetching it.
        ///
        /// **Taps here are coordinates, so nothing scrolls for them.** An
        /// element's own `tap()` scrolls it into view; a coordinate below the
        /// fold is simply pressed, and on the 11-inch iPad that is where Repeat
        /// is — the first run put a Start Fill where the repeat should have
        /// been. `top` is where the list starts: under the toolbar on an iPad,
        /// under the sheet's grabber on a phone.
        @MainActor
        func palette(_ title: String, top: CGFloat = 150) throws -> CGRect {
            let bottom = app.frame.height - 40
            var frame = try find(title, type: .button) { $0.minX < $1.minX }
            for _ in 0..<4 where frame.minY < top || frame.maxY > bottom {
                let distance = min(max(frame.midY - (top + bottom) / 2, -420), 420)
                let from = CGPoint(x: frame.midX, y: distance > 0 ? bottom - 60 : top + 60)
                swipe(from: from, to: CGPoint(x: from.x, y: from.y - distance))
                pause(0.5)
                frame = try find(title, type: .button) { $0.minX < $1.minX }
            }
            return frame
        }

        /// A button anywhere, by its accessibility label; the topmost if there
        /// are several.
        @MainActor
        func button(_ label: String) throws -> CGRect {
            try find(label, type: .button) { $0.minY < $1.minY }
        }

        @MainActor
        func find(
            _ label: String, type: XCUIElement.ElementType, within timeout: TimeInterval = 10,
            preferring order: (CGRect, CGRect) -> Bool
        ) throws -> CGRect {
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                var found: [CGRect] = []
                func walk(_ node: XCUIElementSnapshot) {
                    if node.elementType == type, node.label == label, !node.frame.isEmpty {
                        found.append(node.frame)
                    }
                    node.children.forEach(walk)
                }
                walk(try app.snapshot())
                if let best = found.min(by: order) { return best }
                Thread.sleep(forTimeInterval: 0.3)
            } while Date() < deadline
            throw FilmError.missing(label)
        }

        @MainActor
        func frame(of element: XCUIElement) throws -> CGRect {
            guard element.waitForExistence(timeout: 10) else {
                throw FilmError.missing(element.description)
            }
            return element.frame
        }

        @MainActor
        func coordinate(_ point: CGPoint) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x, dy: point.y))
        }

        /// Taps the middle of `frame`. The log gets the moment the call began as
        /// well as when it returned: the touch lands somewhere between, after
        /// the app has gone idle, and the driver finds it in the recording.
        @MainActor
        func tap(_ frame: CGRect) throws {
            let point = CGPoint(x: frame.midX, y: frame.midY)
            let started = Date()
            coordinate(point).tap()
            record([
                "type": "tap", "x": point.x, "y": point.y, "t0": started.timeIntervalSince1970,
            ])
        }

        /// Drags a palette entry into the program, dropping it in the gap above
        /// the row the button `row` sits on, and makes sure it arrived: a block
        /// wearing `bringing` has to turn up.
        ///
        /// Aimed a little *above* the gap's line: a gap is hit-tested over a
        /// whole row's pitch, but the row below it paints later and wins right
        /// at its own top edge — and a container's header is a drop target of
        /// its own that puts the block inside.
        ///
        /// **A drop in the simulator does not always land.** The rows part, the
        /// finger lets go, and nothing is inserted — seen once in five runs,
        /// with the same gesture that works every other time. So a drag that
        /// brought nothing is tried again, and the failed one is logged as a
        /// `cut`: the driver takes it out of the film, so what is seen is the
        /// take that worked.
        @MainActor
        func drag(_ title: String, above row: String, bringing label: String) throws {
            for _ in 0..<3 {
                let from = try palette(title)
                let target = try button(row)
                let start = CGPoint(x: from.midX, y: from.midY)
                let end = CGPoint(x: target.minX + 60, y: target.minY - 22)
                let hold = 0.7
                let velocity: CGFloat = 500
                let linger = 0.5
                let started = Date()
                coordinate(start).press(
                    forDuration: hold, thenDragTo: coordinate(end),
                    withVelocity: XCUIGestureVelocity(velocity), thenHoldForDuration: linger)
                if (try? find(label, type: .button, within: 3) { $0.minY < $1.minY }) != nil {
                    record([
                        "type": "drag", "x": start.x, "y": start.y, "x2": end.x, "y2": end.y,
                        "t0": started.timeIntervalSince1970, "hold": hold, "linger": linger,
                        "velocity": velocity,
                    ])
                    return
                }
                record(["type": "cut", "from": started.timeIntervalSince1970])
                pause(0.5)
            }
            throw FilmError.missing("\(label) after dragging \(title) in")
        }

        /// Scrolls with a finger: pressed only briefly, so it is a scroll and
        /// not the long press that lifts a block, and held at the end so it does
        /// not fling on past where it was aimed.
        @MainActor
        func swipe(from start: CGPoint, to end: CGPoint) {
            let velocity: CGFloat = 900
            let started = Date()
            coordinate(start).press(
                forDuration: 0.05, thenDragTo: coordinate(end),
                withVelocity: XCUIGestureVelocity(velocity), thenHoldForDuration: 0.15)
            record([
                "type": "drag", "x": start.x, "y": start.y, "x2": end.x, "y2": end.y,
                "t0": started.timeIntervalSince1970, "hold": 0.05, "linger": 0.15,
                "velocity": velocity,
            ])
        }

        /// Opens a number chip, puts in the new value and closes it again.
        ///
        /// **Pressed on the number pad when one comes up, typed when none
        /// does.** A pad is what a phone is used with, so the touches drawn over
        /// its keys are the real ones. On an iPad the driver attaches a hardware
        /// keyboard, because otherwise a number field raises half a screen of
        /// keys — the maintainer's own recording was made with a pointer and a
        /// keyboard. Whether a phone shows its pad under the same preference
        /// was not settled: one run did and the next did not, so this looks
        /// rather than assumes. `⌘A` is not used for typing: selecting brought
        /// iPadOS 27's number keypad up over the field and, now and then, the
        /// full keyboard under it.
        ///
        /// Either way the field is tapped in the middle, which puts the caret
        /// after the digits, so the old value goes by backspace.
        @MainActor
        func setNumber(_ chip: String, to value: String) throws {
            try tap(button(chip))
            pause(0.8)
            try tap(frame(of: app.popovers.textFields.firstMatch))
            let editing = Date()
            pause(0.6)
            let digits = chip.split(separator: " ").last.map(\.count) ?? 0
            let pad =
                UIDevice.current.userInterfaceIdiom == .phone
                && (try? key("delete", within: 2)) != nil
            if pad {
                for _ in 0..<digits {
                    try tap(key("delete"))
                    pause(0.25)
                }
                for character in value {
                    try tap(key(String(character)))
                    pause(0.25)
                }
            }
            else {
                app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: digits))
                record(["type": "key"])
                pause(0.3)
                for character in value {
                    app.typeText(String(character))
                    record(["type": "key"])
                    pause(0.2)
                }
            }
            pause(0.5)
            // While the field has focus its caret blinks, and a blink is a new
            // frame: without this the driver would keep every one of them.
            record(["type": "typing", "from": editing.timeIntervalSince1970])
            dismissPopover()
            pause(0.7)
        }

        /// A key on the on-screen number pad, by its label or its identifier,
        /// either case: delete is `delete` by identifier on one keyboard and
        /// `Delete` on the next, and its label is in the system's language.
        @MainActor
        func key(_ name: String, within timeout: TimeInterval = 10) throws -> CGRect {
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                var found: CGRect?
                func walk(_ node: XCUIElementSnapshot) {
                    if found == nil, node.elementType == .key,
                        [node.label, node.identifier].contains(where: {
                            $0.caseInsensitiveCompare(name) == .orderedSame
                        }),
                        !node.frame.isEmpty
                    {
                        found = node.frame
                    }
                    node.children.forEach(walk)
                }
                walk(try app.snapshot())
                if let found { return found }
                Thread.sleep(forTimeInterval: 0.3)
            } while Date() < deadline
            throw FilmError.missing("the \(name) key")
        }

        /// Closes a popover by tapping outside it — not drawn as a touch: it is
        /// the tap nobody watching needs to see.
        @MainActor
        func dismissPopover() {
            let region = app.otherElements["PopoverDismissRegion"]
            if region.exists {
                region.tap()
            }
            else {
                coordinate(CGPoint(x: 400, y: 740)).tap()
            }
        }

        /// Presses play and waits for the drawing to finish: the scrubber's
        /// value has settled, and it either moved or had time to.
        ///
        /// Moving is not required, because a short drawing can be over before
        /// the press returns — XCUITest waits for the app to go idle, which took
        /// nine seconds once, and an eight-step triangle takes 0.8. Nor is
        /// ending somewhere new: changing an angle leaves the step count alone,
        /// so the run ends on exactly the value the last one did.
        @MainActor
        func playDrawing(holding seconds: TimeInterval = 1.1) throws {
            // A phone's transport is in the sheet the press raises, so there
            // is no scrubber to read until the run is under way.
            let scrubber = app.sliders.firstMatch
            var last = scrubber.exists ? scrubber.value.map { String(describing: $0) } : nil
            let pressed = Date()
            try tap(frame(of: app.buttons["play.fill"].firstMatch))
            var moved = false
            var settled = 0
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
                let now = scrubber.exists ? scrubber.value.map { String(describing: $0) } : nil
                if now == last {
                    settled += 1
                }
                else {
                    settled = 0
                    moved = true
                }
                last = now
                if settled >= 4, moved || Date().timeIntervalSince(pressed) > 3 {
                    linger(seconds)
                    return
                }
            }
            throw FilmError.stalled
        }

        // MARK: - The log

        func caption(_ text: String) {
            record(["type": "caption", "text": text])
        }

        /// Where the camera should be looking from here on, in screen points.
        /// Only the teaser has a camera; an App Store preview may not zoom.
        func camera(_ rect: CGRect) {
            record(["type": "camera", "rect": [rect.minX, rect.minY, rect.width, rect.height]])
        }

        /// Asks the driver to keep this moment on screen for `seconds` even
        /// though nothing moves: the driver cuts every still stretch short
        /// otherwise, and a finished drawing is the one thing worth looking at
        /// for a while.
        func linger(_ seconds: TimeInterval) {
            record(["type": "linger", "seconds": seconds])
        }

        func pause(_ seconds: TimeInterval) {
            Thread.sleep(forTimeInterval: seconds)
        }

        func record(_ event: [String: Any]) {
            var event = event
            event["t"] = Date().timeIntervalSince1970
            guard let data = try? JSONSerialization.data(withJSONObject: event) else { return }
            events?.write(data + Data("\n".utf8))
        }

        private func environment(_ name: String) throws -> String {
            guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
                throw XCTSkip("\(name) is not set — run this through Tools/film/")
            }
            return value
        }
    }

    enum FilmError: Error, CustomStringConvertible {
        case missing(String)
        case stalled

        var description: String {
            switch self {
            case .missing(let what): "nothing on screen matches \(what)"
            case .stalled: "the drawing never finished"
            }
        }
    }

#endif
