// iPad only: the teaser is shot on the iPad simulator, and orientation,
// `XCUIDevice.system` and the keyboard keys this leans on do not exist on a
// Mac, which builds this target too (for `ScreenshotTests`).
#if os(iOS)

    import XCTest

    /// Performs the teaser video's script on an iPad, slowly enough to watch.
    ///
    /// The driver records the simulator's screen while this runs and cuts the
    /// recording into the video; this does the pressing, and writes down when and
    /// where each press happened, when each caption belongs and where the camera
    /// should look, so the driver can draw the touches, lay the captions over the
    /// right moments and zoom in on the part of the screen that matters.
    ///
    /// Everything is addressed in points on the landscape screen, which is what
    /// both `XCUIElement.frame` and the log use; the driver maps them onto the
    /// recording.
    final class TeaserTests: XCTestCase {
        private var events: FileHandle?
        private var app: XCUIApplication!

        override func setUp() {
            continueAfterFailure = false
        }

        @MainActor
        func testTeaser() throws {
            let documents = try environment("TB_DOCUMENTS")
            let log = try environment("TB_EVENTS")
            FileManager.default.createFile(atPath: log, contents: nil)
            events = FileHandle(forWritingAtPath: log)
            defer { try? events?.close() }

            app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            XCUIDevice.shared.orientation = .landscapeLeft

            let document = URL(fileURLWithPath: documents)
                .appendingPathComponent("My Drawing.tortoise")
            XCUIDevice.shared.system.open(document)

            let play = app.buttons["play.fill"]
            XCTAssertTrue(play.waitForExistence(timeout: 30), "the document never opened")
            record(["type": "screen", "w": app.frame.width, "h": app.frame.height])
            pause(2)
            record(["type": "start"])

            // A run that stops half-way leaves the screen as it last saw it
            // beside the log, so it says what *was* there and not only what was
            // missing.
            do {
                try firstSteps()
                try repeating()
                try findingTheStar()
                try addingColour()
                try growingTheLine()
                try showingTheCode()
            }
            catch {
                try? app.debugDescription.write(
                    toFile: log + ".failure.txt", atomically: true, encoding: .utf8)
                throw error
            }

            record(["type": "end"])
            pause(1)
        }

        // MARK: - The script

        /// A line, then a corner: tap, play, change, play again.
        @MainActor
        private func firstSteps() throws {
            camera(.all)
            pause(1)
            caption("Tap a block.")
            camera(.blocks)
            pause(1.4)
            try tap(palette("Forward"))
            pause(1.3)

            caption("Press play.")
            camera(.all)
            pause(1.2)
            try playDrawing()
            pause(0.8)

            caption("Try, look, change.")
            camera(.blocks)
            pause(1.3)
            try tap(palette("Turn Right"))
            pause(0.7)
            try tap(palette("Forward"))
            pause(0.9)
            camera(.all)
            pause(1)
            try playDrawing()
            pause(1.2)
        }

        /// The square the long way, then the same square with a repeat.
        @MainActor
        private func repeating() throws {
            caption("Again and again?")
            camera(.blocks)
            pause(1.3)
            for title in ["Turn Right", "Forward", "Turn Right", "Forward"] {
                try tap(palette(title))
                pause(0.55)
            }
            pause(0.4)
            camera(.all)
            pause(1)
            try playDrawing()
            pause(1.2)

            caption("Repeat it.")
            pause(1)
            try tap(button("Delete All"))
            pause(0.9)
            // The alert's button, not the can: the can is labelled the same.
            try tap(frame(of: app.alerts.buttons["Delete All"]))
            pause(0.9)
            camera(.blocks)
            pause(1)
            // A new container becomes the palette's target, so the next two land
            // inside it.
            try tap(palette("Repeat"))
            pause(0.8)
            try tap(palette("Forward"))
            pause(0.6)
            try tap(palette("Turn Right"))
            pause(0.9)
            camera(.all)
            pause(1)
            try playDrawing()
            pause(1.2)
        }

        /// 90° makes a square; the star is found by trying other angles.
        @MainActor
        private func findingTheStar() throws {
            caption("What if we turn 120°?")
            camera(.program)
            pause(1.3)
            try setNumber("Number 90", to: "120")
            camera(.all)
            pause(1)
            try playDrawing()
            pause(1.5)

            caption("Not quite… 144!")
            camera(.program)
            pause(1.3)
            try setNumber("Number 120", to: "144")
            try setNumber("Number 4", to: "5")
            camera(.all)
            pause(1)
            try playDrawing()
            pause(1.5)
        }

        /// A pen colour and a thicker line, dragged in above the repeat.
        @MainActor
        private func addingColour() throws {
            caption("Add some color.")
            camera(.blocks)
            pause(1.3)
            try drag("Pen Color", above: "Number 5", bringing: "Color blue")
            pause(0.8)
            try tap(button("Color blue"))
            pause(0.8)
            try tap(button("orange"))
            pause(0.8)
            try drag("Pen Width", above: "Number 5", bringing: "Number 2")
            pause(0.8)
            try setNumber("Number 2", to: "6", camera: nil)
            camera(.all)
            pause(1)
            try playDrawing()
            pause(1.5)
        }

        /// A box that grows every time round turns the star into a spiral.
        @MainActor
        private func growingTheLine() throws {
            caption("Let the line grow.")
            camera(.blocks)
            pause(1.3)
            try drag("Put in Box", above: "Number 5", bringing: "Number 10")
            pause(0.8)
            // The forward inside the repeat: from a number to the box.
            try tap(button("Number 100"))
            pause(0.8)
            try tap(button("Box"))
            pause(0.9)
            dismissPopover()
            pause(0.6)
            // Still the palette's target, so this goes inside the repeat too.
            try tap(palette("Add to Box"))
            pause(0.8)
            try setNumber("Number 5", to: "30", camera: nil)
            camera(.all)
            pause(1)
            try playDrawing()
            pause(1.2)
            camera(.canvas)
            linger(2.5)
            pause(2.5)
        }

        /// The same program as Swift.
        @MainActor
        private func showingTheCode() throws {
            caption("It's real Swift.")
            camera(.all)
            pause(1)
            try tap(frame(of: app.segmentedControls.firstMatch.buttons.element(boundBy: 1)))
            pause(0.8)
            camera(.code)
            linger(4)
            pause(5)
        }

        // MARK: - Where the camera looks

        /// Regions of the landscape screen, in points. The iPad this is shot on
        /// is fixed by the driver, so these are measured rather than derived.
        private enum Shot {
            case all
            /// The palette and the program.
            case blocks
            /// The program, closer.
            case program
            /// The drawing.
            case canvas
            /// The code pane's text.
            case code

            func rect(on screen: CGRect) -> CGRect {
                switch self {
                case .all: screen
                case .blocks: CGRect(x: 0, y: 40, width: 730, height: 503)
                case .program: CGRect(x: 200, y: 110, width: 620, height: 427)
                case .canvas: CGRect(x: 690, y: 140, width: 520, height: 358)
                case .code: CGRect(x: 586, y: 90, width: 624, height: 430)
                }
            }
        }

        @MainActor
        private func camera(_ shot: Shot) {
            let rect = shot.rect(on: app.frame)
            record([
                "type": "camera",
                "rect": [rect.minX, rect.minY, rect.width, rect.height],
            ])
        }

        // MARK: - The hands

        /// A palette entry by its title, scrolled on screen first if it is not.
        ///
        /// The title is not unique: the transport's step button is "Forward" too.
        /// Of every button with that label this is the one furthest left, since
        /// the palette is the first column — read from one snapshot, because
        /// walking a query's matches one by one raced the UI and lost an element
        /// between counting and fetching it.
        ///
        /// **Taps here are coordinates, so nothing scrolls for them.** An element's
        /// own `tap()` scrolls it into view; a coordinate below the fold is simply
        /// pressed, and on the 11-inch iPad that is where Repeat is — the first run
        /// put a Start Fill where the repeat should have been.
        @MainActor
        private func palette(_ title: String) throws -> CGRect {
            let top: CGFloat = 150
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
        private func button(_ label: String) throws -> CGRect {
            try find(label, type: .button) { $0.minY < $1.minY }
        }

        @MainActor
        private func find(
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
            throw TeaserError.missing(label)
        }

        @MainActor
        private func frame(of element: XCUIElement) throws -> CGRect {
            guard element.waitForExistence(timeout: 10) else {
                throw TeaserError.missing(element.description)
            }
            return element.frame
        }

        @MainActor
        private func coordinate(_ point: CGPoint) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x, dy: point.y))
        }

        @MainActor
        private func tap(_ frame: CGRect) throws {
            let point = CGPoint(x: frame.midX, y: frame.midY)
            coordinate(point).tap()
            record(["type": "tap", "x": point.x, "y": point.y])
        }

        /// Drags a palette entry into the program, dropping it in the gap above
        /// the row the button `row` sits on, and makes sure it arrived: a block
        /// wearing `bringing` has to turn up.
        ///
        /// Aimed a little *above* the gap's line: a gap is hit-tested over a whole
        /// row's pitch, but the row below it paints later and wins right at its
        /// own top edge — and a container's header is a drop target of its own
        /// that puts the block inside.
        ///
        /// **A drop in the simulator does not always land.** The rows part, the
        /// finger lets go, and nothing is inserted — seen once in five runs, with
        /// the same gesture that works every other time. So a drag that brought
        /// nothing is tried again, and the failed one is logged as a `cut`: the
        /// driver takes it out of the film, so what is seen is the take that
        /// worked. (The retry has not been needed since it was written, so the
        /// cut has only been checked by reading.)
        @MainActor
        private func drag(_ title: String, above row: String, bringing label: String) throws {
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
            throw TeaserError.missing("\(label) after dragging \(title) in")
        }

        /// Scrolls with a finger: pressed only briefly, so it is a scroll and not
        /// the long press that lifts a block, and held at the end so it does not
        /// fling on past where it was aimed.
        @MainActor
        private func swipe(from start: CGPoint, to end: CGPoint) {
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

        /// Opens a number chip, types the new value and closes it again.
        ///
        /// Typed on the hardware keyboard the driver attaches, so no on-screen
        /// keyboard comes up — the way the maintainer's own recording was made,
        /// with a pointer and a keyboard. The field is tapped in the middle, which
        /// puts the caret after the digits, so the old value goes by backspace;
        /// `⌘A` is not used, because selecting brought iPadOS 27's number keypad
        /// up over the field and, now and then, the full keyboard under it.
        @MainActor
        private func setNumber(_ chip: String, to value: String, camera shot: Shot? = .program)
            throws
        {
            if let shot { camera(shot) }
            try tap(button(chip))
            pause(0.8)
            try tap(frame(of: app.popovers.textFields.firstMatch))
            let editing = Date()
            pause(0.6)
            let digits = chip.split(separator: " ").last.map(\.count) ?? 0
            app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: digits))
            record(["type": "key"])
            pause(0.3)
            for character in value {
                app.typeText(String(character))
                record(["type": "key"])
                pause(0.2)
            }
            pause(0.5)
            // While the field has focus its caret blinks, and a blink is a new
            // frame: without this the driver would keep every one of them.
            record(["type": "typing", "from": editing.timeIntervalSince1970])
            dismissPopover()
            pause(0.7)
        }

        /// Closes a popover by tapping outside it — not drawn as a touch: it is
        /// the tap nobody watching needs to see.
        @MainActor
        private func dismissPopover() {
            let region = app.otherElements["PopoverDismissRegion"]
            if region.exists {
                region.tap()
            }
            else {
                coordinate(CGPoint(x: 400, y: 740)).tap()
            }
        }

        /// Presses play and waits for the drawing to finish: the scrubber's value
        /// has settled, and it either moved or had time to.
        ///
        /// Moving is not required, because a short drawing can be over before the
        /// press returns — XCUITest waits for the app to go idle, which took nine
        /// seconds once, and an eight-step triangle takes 0.8. Nor is ending
        /// somewhere new: changing an angle leaves the step count alone, so the
        /// run ends on exactly the value the last one did.
        @MainActor
        private func playDrawing() throws {
            let scrubber = app.sliders.firstMatch
            var last = scrubber.value.map { String(describing: $0) }
            let pressed = Date()
            try tap(frame(of: app.buttons["play.fill"]))
            var moved = false
            var settled = 0
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
                let now = scrubber.value.map { String(describing: $0) }
                if now == last {
                    settled += 1
                }
                else {
                    settled = 0
                    moved = true
                }
                last = now
                if settled >= 4, moved || Date().timeIntervalSince(pressed) > 3 {
                    linger(1.1)
                    return
                }
            }
            throw TeaserError.stalled
        }

        // MARK: - The log

        private func caption(_ text: String) {
            record(["type": "caption", "text": text])
        }

        /// Asks the driver to keep this moment on screen for `seconds` even though
        /// nothing moves: the driver cuts every still stretch short otherwise, and
        /// a finished drawing is the one thing worth looking at for a while.
        private func linger(_ seconds: TimeInterval) {
            record(["type": "linger", "seconds": seconds])
        }

        private func pause(_ seconds: TimeInterval) {
            Thread.sleep(forTimeInterval: seconds)
        }

        private func record(_ event: [String: Any]) {
            var event = event
            event["t"] = Date().timeIntervalSince1970
            guard let data = try? JSONSerialization.data(withJSONObject: event) else { return }
            events?.write(data + Data("\n".utf8))
        }

        private func environment(_ name: String) throws -> String {
            guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
                throw XCTSkip("\(name) is not set — run this through Tools/teaser/teaser.rb")
            }
            return value
        }

        private enum TeaserError: Error, CustomStringConvertible {
            case missing(String)
            case stalled

            var description: String {
                switch self {
                case .missing(let what): "nothing on screen matches \(what)"
                case .stalled: "the drawing never finished"
                }
            }
        }
    }

#endif
