import SwiftUI
import Observation

/// Owns the navigation path. One per scene per [A-058].
@MainActor
@Observable
public final class AppRouter {
    public var path = NavigationPath()
    public var presentedSheet: SheetRoute?

    public init() {}

    /// Navigate to the editor view.
    public func openEditor() {
        path.append(AppRoute.editor)
    }

    /// Return to the home screen.
    public func popToHome() {
        path = NavigationPath()
    }

    /// Present the settings sheet.
    public func showSettings() {
        presentedSheet = .settings
    }

    /// Present the subscription offer sheet.
    public func showSubscriptionOffer() {
        presentedSheet = .subscriptionOffer
    }

    /// Dismiss any presented sheet.
    public func dismissSheet() {
        presentedSheet = nil
    }
}
