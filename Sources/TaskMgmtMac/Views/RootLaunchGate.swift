import SwiftUI

struct RootLaunchGate<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if RootLaunchManager.isRunningAsRoot {
            content
        } else {
            RootAccessRequiredView()
        }
    }
}

private struct RootAccessRequiredView: View {
    @State private var isInstalling = false
    @State private var statusText = "Checking root launch configuration..."
    @State private var errorText: String?
    @State private var didCompleteAutomaticCheck = false

    var body: some View {
        VStack(spacing: 0) {
            RootAccessTitleBar()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Root access required")
                        .taskManagerFont(28, weight: .semibold)
                        .foregroundStyle(WindowsTaskManagerTheme.textPrimary)

                    Text("TaskMgmtMac needs root access to enable all application features. Install a local launch rule once, then the app will relaunch itself as root automatically.")
                        .taskManagerFont(14)
                        .foregroundStyle(WindowsTaskManagerTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("macOS will ask for your administrator password.", systemImage: "lock.shield")
                    Label("The password is handled by macOS and is not stored by TaskMgmtMac.", systemImage: "key")
                    Label("The rule only allows this exact app executable to relaunch as root.", systemImage: "checkmark.seal")
                }
                .taskManagerFont(13)
                .foregroundStyle(WindowsTaskManagerTheme.textSecondary)

                if let errorText {
                    Text(errorText)
                        .taskManagerFont(13, weight: .medium)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(statusText)
                        .taskManagerFont(13)
                        .foregroundStyle(WindowsTaskManagerTheme.textMuted)
                }

                HStack(spacing: 10) {
                    Button {
                        Task {
                            await installAndRelaunch()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isInstalling {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }

                            Text(isInstalling ? "Installing..." : "Install and relaunch")
                        }
                        .taskManagerFont(13, weight: .semibold)
                        .frame(height: 34)
                        .padding(.horizontal, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInstalling)

                    Button("Quit") {
                        RootLaunchManager.terminateCurrentProcess()
                    }
                    .taskManagerFont(13)
                    .buttonStyle(.bordered)
                    .disabled(isInstalling)
                }
            }
            .padding(.horizontal, 72)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background(WindowsTaskManagerTheme.windowBackground)
        .foregroundStyle(WindowsTaskManagerTheme.textPrimary)
        .background(WindowConfigurator())
        .task {
            await attemptAutomaticRelaunch()
        }
    }

    private func attemptAutomaticRelaunch() async {
        guard !didCompleteAutomaticCheck else { return }
        didCompleteAutomaticCheck = true

        if await RootLaunchManager.canRelaunchWithoutPassword() {
            do {
                try RootLaunchManager.relaunchAsRoot()
                RootLaunchManager.terminateCurrentProcess()
            } catch {
                statusText = "Automatic relaunch is configured, but the app could not start as root."
                errorText = error.localizedDescription
            }
        } else {
            statusText = "Root launch is not configured yet."
        }
    }

    private func installAndRelaunch() async {
        isInstalling = true
        errorText = nil
        statusText = "Installing root launch rule..."

        do {
            try await RootLaunchManager.installRootLaunchRule()
            statusText = "Relaunching as root..."
            try RootLaunchManager.relaunchAsRoot()
            RootLaunchManager.terminateCurrentProcess()
        } catch {
            errorText = error.localizedDescription
            statusText = "Root launch is not configured yet."
            isInstalling = false
        }
    }
}

private struct RootAccessTitleBar: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red.opacity(0.86))
                .frame(width: 13, height: 13)
            Circle()
                .fill(Color.yellow.opacity(0.86))
                .frame(width: 13, height: 13)
            Circle()
                .fill(Color.green.opacity(0.86))
                .frame(width: 13, height: 13)

            Text("Task Manager")
                .taskManagerFont(15, weight: .semibold)
                .padding(.leading, 10)

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(WindowsTaskManagerTheme.titleBar)
    }
}
