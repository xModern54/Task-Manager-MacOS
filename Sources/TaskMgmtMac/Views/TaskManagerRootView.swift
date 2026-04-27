import SwiftUI

struct TaskManagerRootView: View {
    @ObservedObject var viewModel: TaskManagerViewModel
    @EnvironmentObject private var settings: TaskManagerSettings

    var body: some View {
        VStack(spacing: 0) {
            TaskManagerTitleBar(viewModel: viewModel)

            HStack(spacing: 0) {
                TaskManagerSidebar(
                    selection: $viewModel.selectedSection,
                    isExpanded: viewModel.isSidebarExpanded
                )

                Divider()
                    .overlay(WindowsTaskManagerTheme.separator)

                switch viewModel.selectedSection {
                case .processes:
                    ProcessesPage(viewModel: viewModel)
                case .devices:
                    PerformancePage(
                        summary: viewModel.snapshot.summary,
                        cpuHistory: viewModel.cpuHistory,
                        memoryHistory: viewModel.memoryHistory,
                        gpuSnapshot: viewModel.gpuSnapshot,
                        gpuHistory: viewModel.gpuHistory,
                        diskSnapshot: viewModel.diskSnapshot,
                        diskHistory: viewModel.diskHistory,
                        networkSnapshot: viewModel.networkSnapshot,
                        networkHistory: viewModel.networkHistory,
                        npuSnapshot: viewModel.npuSnapshot,
                        npuHistory: viewModel.npuHistory,
                        batterySnapshot: viewModel.batterySnapshot,
                        batteryHistory: viewModel.batteryHistory,
                        cpuSensorSnapshot: viewModel.cpuSensorSnapshot,
                        selectedDeviceID: $viewModel.selectedPerformanceDeviceID
                    )
                case .settings:
                    SettingsPage()
                }
            }
        }
        .background(WindowsTaskManagerTheme.windowBackground)
        .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
        .tint(settings.effectiveAccentColor)
        .background(WindowConfigurator())
        .task {
            viewModel.setRefreshInterval(settings.refreshInterval)
            await viewModel.startRefreshing()
        }
        .onChange(of: settings.refreshInterval) { _, newInterval in
            viewModel.setRefreshInterval(newInterval)
        }
    }
}
