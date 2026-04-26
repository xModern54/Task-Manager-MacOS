import SwiftUI

struct TaskManagerRootView: View {
    @ObservedObject var viewModel: TaskManagerViewModel

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
                        privilegedCPUSensorSnapshot: viewModel.privilegedCPUSensorSnapshot,
                        selectedDeviceID: $viewModel.selectedPerformanceDeviceID
                    )
                }
            }
        }
        .background(WindowsTaskManagerTheme.windowBackground)
        .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
        .tint(WindowsTaskManagerTheme.accent)
        .background(WindowConfigurator())
        .task {
            await viewModel.startRefreshing()
        }
    }
}
