import Cocoa
import Combine

@MainActor
final class DockIconManager {
    static let shared = DockIconManager()
    
    private var cancellable: AnyCancellable?
    
    private init() {}
    
    func startMonitoring() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cancellable = NSApplication.shared.publisher(for: \.effectiveAppearance)
                .sink { [weak self] appearance in
                    self?.updateIcon(for: appearance)
                }
        }
    }
    
    private func updateIcon(for appearance: NSAppearance) {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let iconName = isDark ? "AppIcon" : "AppIconLight"
        
        guard let iconURL = Bundle.main.url(forResource: iconName, withExtension: "icns") else {
            // Fallback: clear custom icon so system uses default plist icon
            NSApplication.shared.applicationIconImage = nil
            return
        }
        
        if let image = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = image
        } else {
            NSApplication.shared.applicationIconImage = nil
        }
    }
}
