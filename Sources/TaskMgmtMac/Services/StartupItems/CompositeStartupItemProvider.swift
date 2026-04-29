import Foundation

struct CompositeStartupItemProvider: StartupItemProviding {
    private let providers: [any StartupItemProviding]

    init(providers: [any StartupItemProviding] = [
        BackgroundTaskManagementStartupItemProvider(),
        LaunchAgentPlistStartupItemProvider(),
        SystemEventsLoginItemProvider()
    ]) {
        self.providers = providers
    }

    func startupItems() async -> [StartupItem] {
        var mergedItems: [StartupItem] = []
        var seenKeys: Set<String> = []

        for provider in providers {
            let items = await provider.startupItems()

            for item in items {
                let key = deduplicationKey(for: item)
                guard seenKeys.insert(key).inserted else { continue }
                mergedItems.append(item)
            }
        }

        return mergedItems.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private func deduplicationKey(for item: StartupItem) -> String {
    if !item.controlTargets.isEmpty {
        return "target:\(item.controlTargets.map(\.id).sorted().joined(separator: "|"))"
    }

    if let path = item.path {
        return "path:\(path)"
    }

    return "name:\(item.name.lowercased())"
}
