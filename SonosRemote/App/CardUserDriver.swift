import Foundation
import os
import Sparkle

/// Sparkle's user interface, redirected into the update card: every callback is forwarded to
/// `UpdateController` as plain values. Holds the controller weakly (the controller owns the updater, which owns this).
@MainActor
final class CardUserDriver: NSObject, SPUUserDriver {
    private let logger = Logger(subsystem: "com.jenswedin.SonosRemote", category: "updates")
    private weak var controller: UpdateController?

    init(controller: UpdateController) {
        self.controller = controller
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Not reached while SUEnableAutomaticChecks is set in Info.plist; answer like the Settings default if it is.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        // The card already shows "Downloading…" for Update now / Try again.
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        // Sparkle's header: never reply .install for an information-only item. Our feed doesn't publish
        // any, but this is a guard in case one ever slips through.
        guard !appcastItem.isInformationOnlyUpdate else { return reply(.dismiss) }
        guard let controller else { return reply(.dismiss) }
        let stage: UpdateStage = switch state.stage {
        case .downloaded: .downloaded
        case .installing: .installing
        case .notDownloaded: .notDownloaded
        @unknown default: .notDownloaded
        }
        controller.updateFound(
            version: appcastItem.displayVersionString,
            notesURL: appcastItem.fullReleaseNotesURL ?? appcastItem.releaseNotesURL,
            stage: stage
        ) { choice in
            switch choice {
            case .install: reply(.install)
            case .skip: reply(.skip)
            case .dismiss: reply(.dismiss)
            }
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        if let controller { controller.notFound(acknowledgement: acknowledgement) } else { acknowledgement() }
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        let ns = error as NSError
        // A signature mismatch (SUErrorDomain) may mean tampering; every updater error is kept at .error.
        logger.error("update error \(ns.domain, privacy: .public) \(ns.code): \(ns.localizedDescription, privacy: .private)")
        if let controller { controller.failed(message: ns.localizedDescription, acknowledgement: acknowledgement) } else { acknowledgement() }
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        controller?.downloadStarted()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        controller?.downloadExpected(length: expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        controller?.downloadReceived(length: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        controller?.extracting()
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard let controller else { return reply(.dismiss) }
        controller.readyToInstall { choice in reply(choice == .install ? .install : .dismiss) }
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        controller?.installing()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {}

    func dismissUpdateInstallation() {
        controller?.dismissed()
    }
}
