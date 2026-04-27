import SwiftUI

@main
struct TaskMgmtMacApp: App {
    @StateObject private var viewModel = TaskManagerViewModel(
        monitor: ProcessMonitor()
    )
    @StateObject private var settings = TaskManagerSettings()

    init() {
        RootLaunchManager.exitIfHandlingProbeArgument()
    }

    var body: some Scene {
        WindowGroup {
            RootLaunchGate {
                TaskManagerRootView(viewModel: viewModel)
            }
                .environmentObject(settings)
                .preferredColorScheme(settings.preferredColorScheme)
                .tint(settings.effectiveAccentColor)
                .frame(width: 682, height: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 682, height: 660)
    }
}
