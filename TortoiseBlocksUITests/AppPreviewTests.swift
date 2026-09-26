// iPhone and iPad only, like everything the films are made of: see
// `FilmTestCase`.
#if os(iOS)

    import XCTest

    /// The App Store previews: fifteen-odd seconds each, one per device, of a
    /// program changing until it draws something — the teaser's story, told
    /// short. `ruby Tools/film/previews.rb` records and cuts them.
    ///
    /// **Nothing here asks for a camera or a caption.** Apple's rules for a
    /// preview are stricter than the website's: the footage is the screen as
    /// captured, not zoomed into, and these carry no text by the maintainer's
    /// choice. So each script starts from a document that already holds most
    /// of a program — fifteen seconds is not enough to build one from nothing
    /// and still show it drawing.
    final class AppPreviewTests: FilmTestCase {
        /// A square becomes a star, and the star turns orange.
        ///
        /// The document is `Pen Width 6`, then `Repeat 5 { Forward 150,
        /// Turn Right 90 }` — thick lines, so they survive the 13-inch screen
        /// being scaled down to 1600×1200, and already five times round, so a
        /// single number turns the square into a star (the fifth side of a
        /// square only retraces the first).
        @MainActor
        func testIPad() throws {
            try film("My Drawing", landscape: true) {
                pause(0.8)
                try playDrawing(holding: 0.7)
                try setNumber("Number 90", to: "144")
                try playDrawing(holding: 0.7)
                try drag("Pen Color", above: "Number 5", bringing: "Color blue")
                pause(0.8)
                try tap(button("Color blue"))
                pause(0.8)
                try tap(button("orange"))
                pause(0.8)
                try playDrawing(holding: 2)
            }
        }

        /// The two blocks a star is made of, from the palette, into a repeat
        /// that is waiting for them — then the one number that makes it a star.
        ///
        /// The document is `Pen Width 6`, `Pen Color orange` and an empty
        /// `Repeat 5`. Its "Add Here" makes the repeat the palette's target, so
        /// the forward and the turn land inside it; the palette is a sheet on a
        /// phone, raised for each block and gone again once one is added.
        @MainActor
        func testIPhone() throws {
            try film("My Drawing", landscape: false) {
                pause(0.8)
                // A `Toggle` in the button style, which XCUITest calls a
                // switch.
                try tap(find("Add Here", type: .switch) { $0.minY < $1.minY })
                pause(0.8)
                for title in ["Forward", "Turn Right"] {
                    try tap(frame(of: app.buttons["square.grid.2x2"].firstMatch))
                    pause(0.9)
                    try tap(palette(title, top: 120))
                    pause(0.9)
                }
                try setNumber("Number 90", to: "144")
                try playDrawing(holding: 2)
            }
        }
    }

#endif
