// iPad only, like everything the films are made of: see `FilmTestCase`.
#if os(iOS)

    import XCTest

    /// The website's teaser: one program, built by trial and error, from a
    /// line to a spiral of stars — played slowly enough to watch, on the
    /// 11-inch iPad. `ruby Tools/film/teaser.rb` records and cuts it.
    final class TeaserTests: FilmTestCase {
        @MainActor
        func testTeaser() throws {
            try film("My Drawing", landscape: true) {
                try firstSteps()
                try repeating()
                try findingTheStar()
                try addingColour()
                try growingTheLine()
                try showingTheCode()
            }
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
            try setNumber("Number 2", to: "6")
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
            try setNumber("Number 5", to: "30")
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
            camera(shot.rect(on: app.frame))
        }
    }

#endif
