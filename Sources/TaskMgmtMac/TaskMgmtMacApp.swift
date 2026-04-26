import SwiftUI

@main
struct TaskMgmtMacApp: App {
    @StateObject private var viewModel = TaskManagerViewModel(
        monitor: ProcessMonitor()
    )

    init() {
        RootLaunchManager.exitIfHandlingProbeArgument()
    }

    var body: some Scene {
        WindowGroup {
            RootLaunchGate {
                TaskManagerRootView(viewModel: viewModel)
            }
                .frame(width: 682, height: 660)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.automatic)
        .defaultSize(width: 682, height: 660)
    }
}
