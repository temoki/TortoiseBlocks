#if os(iOS)

    import SwiftUI

    /// The screen in front of the system document browser (#32) — iPadOS only.
    ///
    /// `DocumentGroupLaunchScene` is `@available(macOS, unavailable)`, so this
    /// once covered visionOS too. It never actually appeared there — visionOS
    /// shows the system document browser straight away — and #53 took the
    /// DocumentGroup off that platform entirely, leaving this nothing to sit in
    /// front of. The Mac keeps the standard open panel.
    struct LaunchScene: Scene {
        var body: some Scene {
            DocumentGroupLaunchScene(
                // The app name, not a localized phrase: it mirrors
                // CFBundleDisplayName, which is "Tortoise Blocks" in every
                // language. The scene restyles this `Text` outright — neither
                // view modifiers nor `AttributedString` attributes survive — so
                // there is nothing to set here but the string.
                Text(verbatim: "Tortoise Blocks")
            ) {
                NewDocumentButton(LocalizedStringResource("New Drawing"))
            } background: {
                LaunchBackground()
            } overlayAccessoryView: { geometry in
                LaunchTortoise(titleFrame: geometry.titleViewFrame)
            }
        }
    }

    /// The banner artwork's two background layers, kept in register.
    ///
    /// Both renditions are the same 1600×1200 frame, so laying them over one
    /// `Color.clear` — which takes the full proposal — scales and crops them
    /// identically. `scaledToFill` on its own reports a size *larger* than the
    /// proposal, which is what `clipped()` trims back.
    private struct LaunchBackground: View {
        var body: some View {
            Color.clear
                .overlay {
                    Image(.launchBackground)
                        .resizable()
                        .scaledToFill()
                }
                .overlay {
                    Image(.launchDecoration)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
    }

    /// The mascot, standing against the trailing end of the title card.
    ///
    /// The system owns most of this screen: `titleFrame` is the white card, the
    /// browser's sheet starts on the card's bottom edge, and the action button
    /// is centred inside the card — so the tortoise is anchored by two edges it
    /// can trust. It stands *on* the card's bottom edge, and its nose stops a
    /// fixed overlap short of the card's trailing edge; it faces leading, so it
    /// looks at the title. Its height is a fraction of the card's, which keeps
    /// it out of the title's own text box.
    ///
    /// In portrait the card is nearly as wide as the screen, so the same anchors
    /// send the tortoise's back off the trailing edge. That is the intent: a big
    /// mascot cropped by the screen reads better than a small whole one, and
    /// nothing it could cover is on that side.
    private struct LaunchTortoise: View {
        let titleFrame: CGRect

        private static let aspectRatio: CGFloat = 1219.0 / 809.0
        /// The asset is 1219px wide, so past this it upscales on an @2x iPad.
        private static let maxWidth: CGFloat = 600

        /// The visible artwork inside the asset — the rest is the soft halo
        /// baked into the PNG. Placement is expressed against the tortoise you
        /// can see, not the transparent bleed around it. Measured from the
        /// asset's alpha, not read off the canvas it was drawn on.
        private static let artworkLeading: CGFloat = 97.0 / 1219.0
        private static let artworkTrailing: CGFloat = 83.0 / 1219.0
        private static let artworkBottom: CGFloat = 115.0 / 809.0
        private static let artworkHeight: CGFloat = 612.0 / 809.0

        /// How far the nose is allowed onto the card. Enough to read as
        /// standing in front of it, far short of the centred button.
        private static let cardOverlap: CGFloat = 60
        /// The sheet draws over this view, so the feet stop short of the edge.
        private static let bottomGap: CGFloat = 12
        /// Below the title's text box in both orientations, measured in the app.
        private static let heightFraction: CGFloat = 0.45
        /// **A phone's card is the width of the screen**, so there is no room
        /// beside it to stand in — measured on an iPhone 17, about 60% of a
        /// 317pt artwork was past the right edge. Compact gets a smaller
        /// tortoise, tucked into the card's bottom corner under the button.
        private static let compactHeightFraction: CGFloat = 0.24
        /// Between the artwork and the screen edge, on a phone.
        private static let trailingInset: CGFloat = 8

        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        /// The container, which the accessory view fills. Read only to hold the
        /// compact tortoise on screen; the regular placement is the card's
        /// business and uses none of it.
        @State private var containerWidth: CGFloat = 0

        var body: some View {
            let compact = horizontalSizeClass == .compact
            let height = min(
                titleFrame.height
                    * (compact ? Self.compactHeightFraction : Self.heightFraction)
                    / Self.artworkHeight,
                Self.maxWidth / Self.aspectRatio)
            let width = height * Self.aspectRatio
            Image(.launchTortoise)
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height)
                .offset(
                    x: leadingOffset(width: width, compact: compact),
                    y: titleFrame.maxY - Self.bottomGap - height * (1 - Self.artworkBottom)
                )
                // The accessory view is laid out inside the safe area; the
                // proxy's rects are not. Without this the two disagree by the
                // status bar's height and the tortoise sinks into the sheet.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .ignoresSafeArea()
                // After `ignoresSafeArea`, so this is the full container and
                // shares the proxy's coordinate space rather than the inset one.
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    containerWidth = $0
                }
                .accessibilityHidden(true)
        }

        /// Where the image's left edge goes. Regular stands the tortoise beside
        /// the card; compact pins the artwork's right edge to the screen's,
        /// which is the only anchor a full-width card leaves.
        ///
        /// **Compact only, deliberately.** An iPad in *portrait* has the same
        /// card-nearly-fills-the-window shape and cuts the shell off the same
        /// way — a pre-existing bug, invisible until now because both the
        /// capture rig and the design work are landscape. This clamp alone is
        /// not its fix: pulled on screen at the regular size, the tortoise
        /// lands on top of the centred button, which is worse than a cropped
        /// shell. That case needs its own composition and is not this change's
        /// to make.
        private func leadingOffset(width: CGFloat, compact: Bool) -> CGFloat {
            let besideCard = titleFrame.maxX - Self.cardOverlap - width * Self.artworkLeading
            guard compact, containerWidth > 0 else { return besideCard }
            let againstEdge =
                containerWidth - Self.trailingInset - width * (1 - Self.artworkTrailing)
            return min(besideCard, againstEdge)
        }
    }

#endif
