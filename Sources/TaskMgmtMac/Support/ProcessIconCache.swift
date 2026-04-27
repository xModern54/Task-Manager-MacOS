import AppKit
import Combine
import Foundation

@MainActor
final class ProcessIconCache: ObservableObject {
    static let shared = ProcessIconCache()

    @Published private(set) var generation = 0

    private var icons: [String: NSImage] = [:]
    private var warmupTask: Task<Void, Never>?

    private init() {}

    func cachedIcon(pid: Int, executablePath: String?) -> NSImage? {
        icons[cacheKey(pid: pid, executablePath: executablePath)]
    }

    func icon(pid: Int, executablePath: String?) -> NSImage {
        let cacheKey = cacheKey(pid: pid, executablePath: executablePath)
        if let cachedIcon = icons[cacheKey] {
            return cachedIcon
        }

        let icon = loadIcon(pid: pid, executablePath: executablePath)
        icon.size = NSSize(width: 18, height: 18)
        icons[cacheKey] = icon
        return icon
    }

    func warmIcons(for processes: [ProcessMetric]) {
        let requests: [IconRequest] = processes.compactMap { process in
            guard cachedIcon(pid: process.pid, executablePath: process.executablePath) == nil else {
                return nil
            }

            return IconRequest(pid: process.pid, executablePath: process.executablePath)
        }

        guard !requests.isEmpty, warmupTask == nil else { return }

        warmupTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                warmupTask = nil
            }

            var loadedCount = 0
            for request in requests {
                guard !Task.isCancelled else { return }
                guard cachedIcon(pid: request.pid, executablePath: request.executablePath) == nil else {
                    continue
                }

                _ = icon(pid: request.pid, executablePath: request.executablePath)
                loadedCount += 1

                if loadedCount.isMultiple(of: 6) {
                    generation += 1
                    try? await Task.sleep(for: .milliseconds(12))
                }
            }

            if loadedCount > 0 {
                generation += 1
            }
        }
    }

    private func cacheKey(pid: Int, executablePath: String?) -> String {
        guard let executablePath else {
            return "\(pid):"
        }

        return "\(pid):\(iconPath(forExecutablePath: executablePath))"
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

private struct IconRequest {
    let pid: Int
    let executablePath: String?
}
