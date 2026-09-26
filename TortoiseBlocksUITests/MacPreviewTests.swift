// The Mac only: the iPhone and iPad previews are `AppPreviewTests`, on top of
// `FilmTestCase`, which leans on things a Mac does not have.
#if os(macOS)

    import XCTest

    /// The Mac's App Store preview: the iPad's story — a square becomes a star,
    /// the star turns orange — then the same program as Swift.
    ///
    /// `ruby Tools/film/previews.rb mac` records the window with
    /// ScreenCaptureKit while this runs, pointer and clicks included, so
    /// nothing is drawn over it afterwards: on a Mac the pointer *is* the touch.
    /// The log is the same as the other films' (`FilmTestCase`), in screen
    /// points, which is what `XCUIElement.frame` is on a Mac.
    ///
    /// **The runner is sandboxed**, so nothing here touches a file the driver
    /// can see: the log goes back as an attachment in the result bundle, and
    /// instead of waiting for a signal the test gives the recorder — which is
    /// watching for the window to appear — a few seconds' start once the
    /// document is open.
    final class MacPreviewTests: XCTestCase {
        private var app: XCUIApplication!
        private var window: XCUIElement!
        private var events = Data()

        override func setUp() {
            continueAfterFailure = false
        }

        /// The document is `Pen Width 6`, then `Repeat 5 { Forward 150,
        /// Turn Right 90 }` — the iPad's.
        @MainActor
        func testMac() throws {
            let documents = try environment("TB_DOCUMENTS")
            defer {
                let attachment = XCTAttachment(
                    data: events, uniformTypeIdentifier: "public.plain-text")
                attachment.name = "events.jsonl"
                attachment.lifetime = .keepAlways
                add(attachment)
            }

            app = XCUIApplication()
            app.launchArguments = [
                "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                "-NSQuitAlwaysKeepsWindows", "NO",
            ]
            app.launch()
            // Whatever macOS restored is closed, so the one window is ours.
            for restored in app.windows.allElementsBoundByIndex where restored.exists {
                restored.buttons[XCUIIdentifierCloseWindow].click()
            }
            XCUIDevice.shared.system.open(
                URL(fileURLWithPath: documents).appendingPathComponent("My Drawing.tortoise"))
            // The one with the transport, not merely the one with the title:
            // once the recorder has the window, macOS hangs its "sharing this
            // window" control off it, and that answers to the same title.
            window =
                app.windows.matching(NSPredicate(format: "title == %@", "My Drawing.tortoise"))
                .containing(.button, identifier: "play.fill").firstMatch
            XCTAssertTrue(window.waitForExistence(timeout: 30), "the document never opened")
            XCTAssertTrue(
                window.buttons["play.fill"].waitForExistence(timeout: 30),
                "the document has no transport")
            let bounds = window.frame
            record([
                "type": "screen", "w": bounds.width, "h": bounds.height, "x": bounds.minX,
                "y": bounds.minY,
            ])

            // The recorder's head start: it polls for the window four times a
            // second and takes about half a second to begin writing.
            pause(8)
            record(["type": "start"])

            do {
                pause(0.8)
                try playDrawing(holding: 0.7)
                try setNumber(inRow: "Turn Right,", to: "144")
                try playDrawing(holding: 0.7)
                try drag("Pen Color", above: "Number 5", bringing: "Pen Color,")
                pause(0.6)
                try click(chip(inRow: "Pen Color,"))
                pause(0.8)
                try click(button("orange"))
                pause(0.8)
                try playDrawing(holding: 1.2)
                try click(frame(of: window.radioGroups.firstMatch.radioButtons.element(boundBy: 1)))
                pause(0.8)
                linger(2.5)
                pause(3)
            }
            catch {
                let screen = XCTAttachment(string: app.debugDescription)
                screen.name = "failure.txt"
                screen.lifetime = .keepAlways
                add(screen)
                throw error
            }
            record(["type": "end"])
            pause(1)
        }

        // MARK: - The hands

        /// The leftmost button with this label: the palette is the first
        /// column, and "Forward" is the transport's step button too.
        @MainActor
        private func palette(_ title: String) throws -> CGRect {
            try find(title) { $0.minX < $1.minX }
        }

        /// The topmost button with this label.
        @MainActor
        private func button(_ label: String) throws -> CGRect {
            try find(label) { $0.minY < $1.minY }
        }

        /// Read from one snapshot of the window — walking a query's matches one
        /// by one raced the UI on iPad and lost an element between counting and
        /// fetching it. A label ending in a comma matches as a prefix: that is
        /// how a row is named on a Mac, where its chips fold into it
        /// ("Turn Right, Number 90").
        @MainActor
        private func find(
            _ label: String, within timeout: TimeInterval = 10,
            preferring order: (CGRect, CGRect) -> Bool
        ) throws -> CGRect {
            let matches: (String) -> Bool =
                label.hasSuffix(",") ? { $0.hasPrefix(label) } : { $0 == label }
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                var found: [CGRect] = []
                func walk(_ node: XCUIElementSnapshot) {
                    if node.elementType == .button, matches(node.label), !node.frame.isEmpty {
                        found.append(node.frame)
                    }
                    node.children.forEach(walk)
                }
                walk(try window.snapshot())
                // A popover is not inside the window on a Mac: the colour
                // swatches live there.
                let popover = app.popovers.firstMatch
                if found.isEmpty, popover.exists { walk(try popover.snapshot()) }
                if let best = found.min(by: order) { return best }
                pause(0.3)
            } while Date() < deadline
            throw MacFilmError.missing(label)
        }

        @MainActor
        private func frame(of element: XCUIElement) throws -> CGRect {
            guard element.waitForExistence(timeout: 10) else {
                throw MacFilmError.missing(element.description)
            }
            return element.frame
        }

        /// Where a row's first chip is: the row's leading edge, then a fixed
        /// run of padding, icon slot and gaps, then the label, measured in the
        /// font the row draws it in.
        ///
        /// **A Mac folds a row's chips into the row.** On iOS "Number 90" is a
        /// button of its own inside "Turn Right, Number 90"; on a Mac the row is
        /// the one element and the chip has no frame to ask for. Looking for it
        /// in a screenshot of the row was tried and found nothing — the
        /// runner's screenshots do not show the app's window — so it is
        /// measured instead: 41pt before the label, taken from a recording
        /// ("Turn Right", 62.4pt wide, puts its chip 103.5pt in), and 10pt past
        /// its start, which is inside a chip whatever it holds and survives a
        /// running row being drawn 3% larger.
        @MainActor
        private func chip(inRow row: String) throws -> CGRect {
            let frame = try button(row)
            let label = String(row.dropLast())
            let width = (label as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            ]).width
            let x = frame.minX + 41 + width + 10
            return CGRect(x: x - 1, y: frame.midY - 1, width: 2, height: 2)
        }

        /// A point on the screen, as a coordinate in the window.
        @MainActor
        private func coordinate(_ point: CGPoint) -> XCUICoordinate {
            let origin = window.frame.origin
            return window.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x - origin.x, dy: point.y - origin.y))
        }

        /// Clicks the middle of `frame`. `tap()` is not an option on a Mac: it
        /// compiles, runs and presses nothing (see `ScreenshotTests.press`).
        @MainActor
        private func click(_ frame: CGRect) throws {
            let point = CGPoint(x: frame.midX, y: frame.midY)
            let started = Date()
            coordinate(point).click()
            record([
                "type": "tap", "x": point.x, "y": point.y, "t0": started.timeIntervalSince1970,
            ])
        }

        /// Drags a palette entry into the gap above the row that `row` sits
        /// on, and tries again if the block did not arrive — logging the failed
        /// take as a `cut` for the driver to leave out, as on iPad.
        @MainActor
        private func drag(_ title: String, above row: String, bringing label: String) throws {
            for _ in 0..<3 {
                let from = try palette(title)
                let target = try button(row)
                let start = CGPoint(x: from.midX, y: from.midY)
                let end = CGPoint(x: target.minX + 60, y: target.minY - 16)
                let hold = 0.3
                let velocity: CGFloat = 600
                let linger = 0.4
                let started = Date()
                coordinate(start).click(
                    forDuration: hold, thenDragTo: coordinate(end),
                    withVelocity: XCUIGestureVelocity(velocity), thenHoldForDuration: linger)
                if (try? find(label, within: 3) { $0.minY < $1.minY }) != nil {
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
            throw MacFilmError.missing("\(label) after dragging \(title) in")
        }

        /// Opens the number chip on a row, types the new value, and closes it
        /// with Return and Escape — a Mac has a keyboard, and that is what it is
        /// used with.
        @MainActor
        private func setNumber(inRow row: String, to value: String) throws {
            try click(chip(inRow: row))
            pause(0.8)
            try click(frame(of: app.popovers.textFields.firstMatch))
            let editing = Date()
            pause(0.4)
            window.typeKey("a", modifierFlags: .command)
            record(["type": "key"])
            pause(0.3)
            for character in value {
                window.typeText(String(character))
                record(["type": "key"])
                pause(0.2)
            }
            window.typeText("\r")
            record(["type": "key"])
            pause(0.5)
            // The caret blinks while the field has focus, and each blink is a
            // frame; the driver keeps only the keys inside this span.
            record(["type": "typing", "from": editing.timeIntervalSince1970])
            window.typeKey(.escape, modifierFlags: [])
            pause(0.7)
        }

        /// Presses play and waits for the scrubber — a number here, not the
        /// spoken string iOS gives — to have moved, or had time to, and settle.
        @MainActor
        private func playDrawing(holding seconds: TimeInterval) throws {
            let scrubber = window.sliders.firstMatch
            var last = scrubber.exists ? scrubber.value.map { String(describing: $0) } : nil
            let pressed = Date()
            try click(frame(of: window.buttons["play.fill"]))
            var moved = false
            var settled = 0
            let deadline = Date().addingTimeInterval(60)
            while Date() < deadline {
                pause(0.2)
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
            throw MacFilmError.stalled
        }

        // MARK: - The log

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
            events.append(data + Data("\n".utf8))
        }

        private func environment(_ name: String) throws -> String {
            guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
                throw XCTSkip("\(name) is not set — run this through Tools/film/previews.rb")
            }
            return value
        }

        private enum MacFilmError: Error, CustomStringConvertible {
            case missing(String)
            case stalled

            var description: String {
                switch self {
                case .missing(let what): "nothing in the window matches \(what)"
                case .stalled: "the drawing never finished"
                }
            }
        }
    }

#endif
