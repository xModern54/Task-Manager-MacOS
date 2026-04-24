import AppKit
import Foundation

@MainActor
final class ProcessIconCache {
    static let shared = ProcessIconCache()

    private var icons: [String: NSImage] = [:]

    private init() {}

    func icon(pid: Int, executablePath: String?) -> NSImage {
        let cacheKey = "\(pid):\(executablePath ?? "")"
        if let cachedIcon = icons[cacheKey] {
            return cachedIcon
        }

        let icon = loadIcon(pid: pid, executablePath: executablePath)
        icon.size = NSSize(width: 18, height: 18)
        icons[cacheKey] = icon
        return icon
    }

    private func loadIcon(pid: Int, executablePath: String?) -> NSImage {
        if let runningApplication = NSRunningApplication(processIdentifier: pid_t(pid)),
           let applicationIcon = runningApplication.icon {
            return applicationIcon
        }

        if let executablePath {
            return NSWorkspace.shared.icon(forFile: iconPath(forExecutablePath: executablePath))
        }

        return NSWorkspace.shared.icon(for: .unixExecutable)
    }

    private func iconPath(forExecutablePath executablePath: String) -> String {
        let components = executablePath.split(separator: "/", omittingEmptySubsequences: false)
        guard let appIndex = components.lastIndex(where: { $0.hasSuffix(".app") }) else {
            return executablePath
        }

        return components.prefix(through: appIndex).joined(separator: "/")
    }
}
