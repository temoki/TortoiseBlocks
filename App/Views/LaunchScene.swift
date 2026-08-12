#if !os(macOS)

    import SwiftUI

    /// The screen in front of the system document browser (#32).
    ///
    /// `DocumentGroupLaunchScene` is `@available(macOS, unavailable)` and
    /// nothing else, so this file covers iPadOS and visionOS while the Mac
    /// keeps the standard open panel.
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
        /// can see, not the transparent bleed around it.
        private static let artworkLeading: CGFloat = 97.0 / 1219.0
        private static let artworkBottom: CGFloat = 115.0 / 809.0
        private static let artworkHeight: CGFloat = 612.0 / 809.0

        /// How far the nose is allowed onto the card. Enough to read as
        /// standing in front of it, far short of the centred button.
        private static let cardOverlap: CGFloat = 60
        /// The sheet draws over this view, so the feet stop short of the edge.
        private static let bottomGap: CGFloat = 12
        /// Below the title's text box in both orientations, measured in the app.
        private static let heightFraction: CGFloat = 0.45

        var body: some View {
            let height = min(
                titleFrame.height * Self.heightFraction / Self.artworkHeight,
                Self.maxWidth / Self.aspectRatio)
            let width = height * Self.aspectRatio
            Image(.launchTortoise)
                .resizable()
                .scaledToFit()
                .frame(width: width, height: height)
                .offset(
                    x: titleFrame.maxX - Self.cardOverlap - width * Self.artworkLeading,
                    y: titleFrame.maxY - Self.bottomGap - height * (1 - Self.artworkBottom)
                )
                // The accessory view is laid out inside the safe area; the
                // proxy's rects are not. Without this the two disagree by the
                // status bar's height and the tortoise sinks into the sheet.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
    }

#endif
