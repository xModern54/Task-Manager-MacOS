import AppKit
import SwiftUI

@main
struct TaskMgmtMacApp: App {
    @StateObject private var viewModel = TaskManagerViewModel(
        monitor: ProcessMonitor()
    )
    @StateObject private var settings = TaskManagerSettings()
    @StateObject private var helperManager = PrivilegedHelperManager()

    var body: some Scene {
        WindowGroup {
            TaskManagerRootView(viewModel: viewModel)
                .environmentObject(settings)
                .environmentObject(helperManager)
                .preferredColorScheme(settings.preferredColorScheme)
                .tint(settings.effectiveAccentColor)
                .frame(width: 682, height: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 682, height: 660)
    }
}
