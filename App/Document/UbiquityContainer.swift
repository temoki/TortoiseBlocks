import Foundation

/// The app's own iCloud container — the folder iCloud Drive shows with the
/// app's icon (#140).
///
/// Nothing creates it on the app's behalf. The document browser makes a new
/// document wherever it is currently looking rather than in the container, so
/// without this the container never comes into being and iCloud Drive has no
/// folder to show. Asking for its URL is what creates it, and `Documents` is
/// the part `NSUbiquitousContainerIsDocumentScopePublic` publishes.
///
/// Not on macOS, which has no iCloud entitlement (see CLAUDE.md): the URL
/// would only ever come back nil there.
enum UbiquityContainer {
    /// Creates the container and its `Documents` folder if they are not there
    /// yet. Does nothing without iCloud — signed out, iCloud Drive off, or the
    /// app switched off under it — which leaves documents where they always
    /// went, On My iPhone / iPad.
    ///
    /// Off the main actor, because the first call can block while iCloud sets
    /// the container up, and Apple's documentation says not to make it on the
    /// main thread.
    @concurrent
    static func prepare() async {
        let files = FileManager.default
        guard let container = files.url(forUbiquityContainerIdentifier: nil) else { return }

        let documents = container.appending(path: "Documents", directoryHint: .isDirectory)
        try? files.createDirectory(at: documents, withIntermediateDirectories: true)
    }
}
