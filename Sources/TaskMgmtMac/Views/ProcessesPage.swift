import SwiftUI

struct ProcessesPage: View {
    @ObservedObject var viewModel: TaskManagerViewModel
    @State private var isTableMounted = false
    @State private var isRunNewTaskPresented = false
    @State private var isEndTaskConfirmationPresented = false
    @State private var terminationErrorMessage = ""
    @State private var isTerminationErrorPresented = false

    var body: some View {
        VStack(spacing: 0) {
            ProcessesCommandBar(
                canEndTask: viewModel.canTerminateSelection,
                onRunNewTask: {
                    isRunNewTaskPresented = true
                },
                onEndTask: {
                    isEndTaskConfirmationPresented = true
                }
            )

            if isTableMounted {
                ProcessTableView(
                    summary: viewModel.snapshot.summary,
                    rows: viewModel.visibleProcessRows,
                    sortColumn: viewModel.sortColumn,
                    sortDirection: viewModel.sortDirection,
                    selectedProcessID: $viewModel.selectedProcessID,
                    selectedProcessGroupID: $viewModel.selectedProcessGroupID,
                    onSort: viewModel.sort(by:),
                    onToggleGroup: viewModel.toggleProcessGroupExpansion(_:),
                    onSelectProcess: viewModel.selectProcess(_:),
                    onSelectGroup: viewModel.selectProcessGroup(_:)
                )
            } else {
                WindowsTaskManagerTheme.table
            }
        }
        .background(WindowsTaskManagerTheme.content)
        .task {
            isTableMounted = false
            await Task.yield()

            do {
                try await Task.sleep(for: .milliseconds(60))
            } catch {
                return
            }

            isTableMounted = true
        }
        .sheet(isPresented: $isRunNewTaskPresented) {
            RunNewTaskDialog()
        }
        .alert(endTaskPromptTitle, isPresented: $isEndTaskConfirmationPresented) {
            Button("End task", role: .destructive) {
                let result = viewModel.terminateSelectedTask()
                guard !result.isSuccess else { return }
                terminationErrorMessage = result.message
                isTerminationErrorPresented = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.selectedTerminationMessage)
        }
        .alert("Could not end task", isPresented: $isTerminationErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(terminationErrorMessage)
        }
    }

    private var endTaskPromptTitle: String {
        guard viewModel.canTerminateSelection else {
            return "End task?"
        }

        return "End \(viewModel.selectedTerminationTitle)?"
    }
}

private struct ProcessesCommandBar: View {
    let canEndTask: Bool
    let onRunNewTask: () -> Void
    let onEndTask: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text("Processes")
                .taskManagerFont(16, weight: .semibold)
                .padding(.leading, 22)

            Spacer()

            CommandButton(
                icon: "plus.square.on.square",
                title: "Run new task",
                isEnabled: true,
                action: onRunNewTask
            )
            VerticalSeparator()
            CommandButton(
                icon: "circle.slash",
                title: "End task",
                isEnabled: canEndTask,
                action: onEndTask
            )

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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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

private struct RunNewTaskDialog: View {
    @Environment(\.dismiss) private var dismiss
    @State private var command = ""
    @State private var output = ""
    @State private var exitCode: Int32?
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Run new task")
                .taskManagerFont(17, weight: .semibold)

            TextField("Command", text: $command)
                .textFieldStyle(.roundedBorder)
                .disabled(isRunning)
                .onSubmit {
                    runCommand()
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(statusText)
                        .taskManagerFont(12)
                        .foregroundStyle(WindowsTaskManagerTheme.textSecondary)

                    Spacer()

                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                TextEditor(text: $output)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(WindowsTaskManagerTheme.table)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(WindowsTaskManagerTheme.separator, lineWidth: 1)
                    }
                    .frame(height: 190)
                    .disabled(isRunning)
            }

            HStack {
                Spacer()

                Button("Close") {
                    dismiss()
                }
                .disabled(isRunning)

                Button("Run") {
                    runCommand()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRunning)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(WindowsTaskManagerTheme.content)
    }

    private var statusText: String {
        if isRunning {
            return "Running..."
        }

        if let exitCode {
            return "Exit code \(exitCode)"
        }

        return "Output"
    }

    private func runCommand() {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty, !isRunning else { return }

        isRunning = true
        exitCode = nil
        output = ""

        Task {
            do {
                let result = try await TaskCommandRunner.run(trimmedCommand)
                exitCode = result.exitCode
                output = result.combinedOutput.isEmpty ? "(no output)" : result.combinedOutput
            } catch {
                exitCode = nil
                output = error.localizedDescription
            }

            isRunning = false
        }
    }
}
