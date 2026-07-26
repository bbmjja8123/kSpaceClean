//
//  WidgetBundle.swift
//  kWatchWidget
//
//  The kWatch System Status widget bundle. Hosts `SystemStatusWidget` (and any
//  future widgets the team adds). This file is the `@main` entry point for the
//  widget extension target.
//
//  --- Xcode integration (developer must perform manually) -----------------
//  1. File > New > Target... > Widget Extension.
//       Product Name: kWatchWidget
//       Bundle ID:    app.kraftly.kwatch.widget
//       Deployment:   macOS 13.0
//  2. In the new target's Signing & Capabilities:
//       - Enable "App Sandbox".
//       - Add the "App Groups" capability and check `group.app.kraftly.shared`.
//  3. Add the following files from the main app target to the widget target's
//     "Compile Sources" phase (Build Phases > Compile Sources > +):
//       - SharedSnapshot.swift
//       - SnapshotWriter.swift
//       - AppGroupConfiguration.swift
//     Alternatively, move them into the local `kFoundation` Swift Package so
//     both targets can `import kFoundation` without duplication.
//  4. Delete the auto-generated `kWatchWidgetBundle.swift` (and any sample
//     `kWatchWidget.swift`) from the new target and add our
//     `WidgetBundle.swift`, `SystemStatusWidget.swift`,
//     `WidgetSnapshotProvider.swift`, `WidgetViews.swift`, and `WidgetEntry.swift`.
//  5. (Optional) Add an `Info.plist` to the widget target with
//     `NSExtensionPointIdentifier = com.apple.widgetkit-extension`. Xcode's
//     "Widget Extension" template usually injects this for you.
//  -------------------------------------------------------------------------
//

import SwiftUI
import WidgetKit

/// The `@main` bundle that the system loads when the widget is registered.
///
/// Adding a widget here is the only thing required to expose it to the widget
/// picker — the system reads `Widget`s from this bundle and lists them.
@main
struct KWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        SystemStatusWidget()
    }
}