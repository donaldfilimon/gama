//  StudioApplicationDelegate.swift — GamaStudioEditor
//
//  Hears when the system discards scene sessions, windows closed for good
//  (ADR 0014): it sweeps recovery files past the 7-day grace period (ADR
//  0013) and lets a still-untouched window adopt a discarded window's
//  unsaved Untitled changes. The app installs it with
//  @UIApplicationDelegateAdaptor.

#if canImport(UIKit) && canImport(RealityKit)

public import UIKit

/// The app delegate the iOS and visionOS app installs for recovery upkeep.
@MainActor
public final class StudioApplicationDelegate: NSObject, UIApplicationDelegate {
    public func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        Self.sessionsDiscarded(Set(sceneSessions.map(\.persistentIdentifier)))
    }

    /// What discarding the sessions `ids` does, callable without real
    /// sessions (the gate's smoke does): their windows stop being live, the
    /// sweep runs with them excluded, and untouched windows are offered
    /// their recovery files to adopt.
    public static func sessionsDiscarded(_ ids: Set<String>) {
        RecoveryWindows.activeKeys.subtract(ids)
        UntitledRecovery.sweepOrphans(in: UntitledRecovery.defaultDirectory(), keeping: RecoveryWindows.liveKeys(discarding: ids))
        NotificationCenter.default.post(name: RecoveryWindows.sessionsDiscarded, object: nil)
    }
}

/// The recovery keys of this process's windows (ADR 0014), so a window
/// named by an explicit key rather than a scene session is never taken for
/// an orphan.
@MainActor
public enum RecoveryWindows {
    /// Keys of windows that have chosen their recovery file this run.
    public static var activeKeys: Set<String> = []

    /// Posted after scene sessions were discarded; untouched windows may
    /// then adopt an orphan.
    public static let sessionsDiscarded = Notification.Name("GamaStudioRecoverySessionsDiscarded")

    /// The keys whose recovery files belong to a window the system keeps.
    public static func liveKeys(discarding discarded: Set<String> = []) -> Set<String> {
        UntitledRecovery.liveKeys(
            open: Set(UIApplication.shared.openSessions.map(\.persistentIdentifier)),
            discarded: discarded,
            active: activeKeys
        )
    }
}

#endif
