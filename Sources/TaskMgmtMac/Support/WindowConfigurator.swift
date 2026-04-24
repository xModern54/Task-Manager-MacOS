import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    private let contentSize = NSSize(width: 682, height: 660)

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            configure(view.window, context: context)
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window, context: context)
        }
    }

    private func configure(_ window: NSWindow?, context: Context) {
        guard let window else { return }

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.clear
        window.styleMask.insert(.fullSizeContentView)
        window.styleMask.insert(.resizable)
        window.minSize = contentSize
        window.maxSize = contentSize

        if !context.coordinator.didSetInitialSize {
            window.setContentSize(contentSize)
            context.coordinator.didSetInitialSize = true
        }

        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false
    }

    final class Coordinator {
        var didSetInitialSize = false
    }
}
