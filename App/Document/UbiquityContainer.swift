import Foundation
import os

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
    private static let log = Logger(subsystem: "space.hiraku.tortoiseblocks", category: "icloud")

    /// Creates the container, its `Documents` folder and the marker that makes
    /// the folder show, if they are not there yet. Does nothing without iCloud
    /// — signed out, iCloud Drive off, or the app switched off under it — which
    /// leaves documents where they always went, On My iPhone / iPad.
    ///
    /// Off the main actor, because the first call can block while iCloud sets
    /// the container up, and Apple's documentation says not to make it on the
    /// main thread.
    @concurrent
    static func prepare() async {
        let files = FileManager.default
        guard let container = files.url(forUbiquityContainerIdentifier: nil) else {
            log.info("No iCloud container: iCloud is unavailable to this app")
            return
        }

        let documents = container.appending(path: "Documents", directoryHint: .isDirectory)
        do {
            try files.createDirectory(at: documents, withIntermediateDirectories: true)
            try leaveMarker(in: documents)
            log.info(
                "iCloud container ready: \(documents.path(percentEncoded: false), privacy: .public)"
            )
        }
        catch {
            log.error("Could not prepare the iCloud Documents folder: \(error, privacy: .public)")
        }
    }

    /// An empty hidden file in `Documents`, because an empty `Documents` is not
    /// enough: measured on an iPhone, the folder stayed out of iCloud Drive —
    /// in the Files app and in the app's own browser alike, minutes later —
    /// until something was inside it, and appeared with its icon once this
    /// was. Hidden, so there is nothing for a child to find, open or delete,
    /// unlike a sample document; and nothing to keep track of either, because
    /// a marker that is already there is simply left alone.
    ///
    /// One another device left behind may not have downloaded yet, in which
    /// case only its `.icloud` placeholder is here; that counts as there, so
    /// two devices don't write the same file over each other.
    private static func leaveMarker(in documents: URL) throws {
        let files = FileManager.default
        let marker = documents.appending(path: ".keep")
        let placeholder = documents.appending(path: ".keep.icloud")
        guard
            !files.fileExists(atPath: marker.path(percentEncoded: false)),
            !files.fileExists(atPath: placeholder.path(percentEncoded: false))
        else { return }

        // Coordinated, as every write into a ubiquity container has to be.
        var coordinationError: NSError?
        var writeError: (any Error)?
        NSFileCoordinator().coordinate(
            writingItemAt: marker, options: .forReplacing, error: &coordinationError
        ) { url in
            do { try Data().write(to: url) }
            catch { writeError = error }
        }
        if let error = coordinationError ?? writeError { throw error }
    }
}
