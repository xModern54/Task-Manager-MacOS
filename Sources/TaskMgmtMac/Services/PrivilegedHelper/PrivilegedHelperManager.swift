import AppKit
import Foundation
import PrivilegedHelperIPC
import ServiceManagement

@MainActor
final class PrivilegedHelperManager: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var isInstallationPromptPresented = false

    private let service = SMAppService.daemon(plistName: PrivilegedHelperConstants.daemonPlistName)
    private let legacyCleanupDefaultsKey = "didRemoveLegacyRootLaunchRule"
    private var didOfferInstallation = false
    private var isLegacyCleanupPending = false

    init() {
        status = service.status
    }

    var statusText: String {
        switch status {
        case .enabled:
            "Installed and enabled"
        case .notRegistered:
            "Not installed"
        case .requiresApproval:
            "Approval required"
        case .notFound:
            "Not registered"
        @unknown default:
            "Unknown"
        }
    }

    var isEnabled: Bool {
        status == .enabled
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func offerInstallationIfNeeded() {
        refresh()
        guard !didOfferInstallation, status != .enabled else { return }
        didOfferInstallation = true
        isInstallationPromptPresented = true
    }

    func refresh() {
        status = service.status
        guard status == .enabled else { return }

        isInstallationPromptPresented = false
        guard !UserDefaults.standard.bool(forKey: legacyCleanupDefaultsKey),
              !isLegacyCleanupPending else {
            return
        }

        isLegacyCleanupPending = true
        Task {
            do {
                try await PrivilegedHelperClient.shared.removeLegacyRootLaunchRule()
                UserDefaults.standard.set(true, forKey: legacyCleanupDefaultsKey)
            } catch {
                // Retrying on the next activation is safe and keeps migration
                // failures from blocking the rest of the application.
            }
            isLegacyCleanupPending = false
        }
    }

    func register() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil

        do {
            switch service.status {
            case .notRegistered, .notFound:
                try service.register()
            case .enabled, .requiresApproval:
                break
            @unknown default:
                try service.register()
            }
            refresh()

            if status == .enabled {
                isInstallationPromptPresented = false
            } else if status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            refresh()
            if status == .requiresApproval {
                errorMessage = nil
                SMAppService.openSystemSettingsLoginItems()
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isWorking = false
    }

    func unregister() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil

        do {
            try await service.unregister()
            refresh()
        } catch {
            errorMessage = error.localizedDescription
            refresh()
        }

        isWorking = false
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
