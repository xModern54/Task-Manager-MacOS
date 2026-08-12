import SwiftUI

struct PrivilegedHelperInstallView: View {
    @EnvironmentObject private var helperManager: PrivilegedHelperManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .taskManagerFont(30)
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable privileged features?")
                        .taskManagerFont(20, weight: .semibold)
                    Text("Task Manager itself will continue running as your user.")
                        .taskManagerFont(13)
                        .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Label("Read CPU, GPU and ANE power telemetry", systemImage: "waveform.path.ecg")
                Label("End processes owned by other users", systemImage: "xmark.circle")
                Label("Enable or disable system launch daemons", systemImage: "switch.2")
            }
            .taskManagerFont(13)

            Text("The helper exposes only these fixed operations over XPC. It cannot run arbitrary commands. macOS controls its approval in Login Items settings.")
                .taskManagerFont(12)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage = helperManager.errorMessage {
                Text(errorMessage)
                    .taskManagerFont(12, weight: .medium)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Not now") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                if helperManager.requiresApproval {
                    Button("Open System Settings") {
                        helperManager.openSystemSettings()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(helperManager.isWorking ? "Installing…" : "Install helper") {
                        Task { await helperManager.register() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(helperManager.isWorking)
                }
            }
        }
        .padding(24)
        .frame(width: 470)
        .background(WindowsTaskManagerTheme.content)
    }
}
