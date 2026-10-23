import AppKit
import SwiftUI

/// Renders the window to a PNG without a display: `SimpleScanner --snapshot /tmp/simplescanner.png`.
@MainActor
enum Snapshot {
    static func renderOffscreenPNG(model: AppModel, size: CGSize = CGSize(width: 1340, height: 780)) -> Data? {
        // Borderless, far off every screen: AppKit does not pull it back on screen, and a List
        // (an NSTableView underneath) only lays out rows once its window is ordered in.
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.background
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: ContentView(model: model))
        hosting.frame = CGRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let png = renderPNG(of: hosting)
        window.orderOut(nil)
        return png
    }

    static func renderOffscreenPNG<V: View>(_ view: V, size: CGSize) -> Data? {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.panel
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        hosting.displayIfNeeded()
        let png = renderPNG(of: hosting)
        window.orderOut(nil)
        return png
    }

    static func renderPNG(of view: NSView) -> Data? {
        let bounds = view.bounds
        guard bounds.width > 1, bounds.height > 1, let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// `--snapshot out.png [--view results|welcome|about|help|shortcuts]`
    static func runCLISnapshot(outputPath: String, view: String = "results") -> Never {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let model = AppModel(startServices: false)
        let png: Data?
        switch view {
        case "welcome":
            model.scan.rangeInput = SyntheticScan.range
            png = renderOffscreenPNG(model: model)
        case "about":
            png = renderOffscreenPNG(AboutSheet(model: model, openHelp: {}, close: {}), size: CGSize(width: 640, height: 470))
        case "help":
            png = renderOffscreenPNG(HelpManualSheet(openShortcuts: {}, close: {}), size: CGSize(width: 780, height: 540))
        case "shortcuts":
            png = renderOffscreenPNG(ShortcutsSheet(close: {}), size: CGSize(width: 900, height: 420))
        default:
            SyntheticScan.load(into: model)
            png = renderOffscreenPNG(model: model)
        }
        guard let png else {
            fputs("snapshot error: failed to render PNG\n", stderr)
            exit(1)
        }
        let outURL = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
        do {
            try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: outURL, options: .atomic)
            print("Snapshot written to \(outURL.path) (\(png.count) bytes)")
            exit(0)
        } catch {
            fputs("snapshot error: \(error)\n", stderr)
            exit(1)
        }
    }
}
