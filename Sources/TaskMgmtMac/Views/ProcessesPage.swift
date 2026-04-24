import SwiftUI

struct ProcessesPage: View {
    @ObservedObject var viewModel: TaskManagerViewModel

    var body: some View {
        VStack(spacing: 0) {
            ProcessesCommandBar()

            ProcessTableView(
                summary: viewModel.snapshot.summary,
                processes: viewModel.visibleProcesses,
                sortColumn: viewModel.sortColumn,
                sortDirection: viewModel.sortDirection,
                selectedProcessID: $viewModel.selectedProcessID,
                onSort: viewModel.sort(by:)
            )
        }
        .background(WindowsTaskManagerTheme.content)
    }
}

private struct ProcessesCommandBar: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("Processes")
                .taskManagerFont(16, weight: .semibold)
                .padding(.leading, 22)

            Spacer()

            CommandButton(icon: "plus.square.on.square", title: "Run new task", isEnabled: true)
            VerticalSeparator()
            CommandButton(icon: "circle.slash", title: "End task", isEnabled: true)

            Image(systemName: "ellipsis")
                .taskManagerFont(18, weight: .bold)
                .frame(width: 48, height: 50)
        }
        .frame(height: 61)
        .background(WindowsTaskManagerTheme.content)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WindowsTaskManagerTheme.separator)
                .frame(height: 1)
        }
    }
}

private struct CommandButton: View {
    let icon: String
    let title: String
    let isEnabled: Bool

    var body: some View {
        Button {} label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .taskManagerFont(16)

                Text(title)
                    .taskManagerFont(13)
            }
            .frame(height: 50)
            .padding(.horizontal, 14)
            .foregroundStyle(isEnabled ? WindowsTaskManagerTheme.textPrimary : WindowsTaskManagerTheme.textMuted)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct VerticalSeparator: View {
    var body: some View {
        Rectangle()
            .fill(WindowsTaskManagerTheme.separator)
            .frame(width: 1, height: 30)
            .padding(.horizontal, 4)
    }
}
