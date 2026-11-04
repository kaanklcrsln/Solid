import AppKit
import SwiftUI

/// `SOLID --snapshot DIR`: renders every section offscreen to PNG after a quick scan (for visual QA without screen recording).
@MainActor
enum UISnapshot {
    static func run(_ dir: String) {
        let nsApp = NSApplication.shared
        nsApp.setActivationPolicy(.accessory)
        nsApp.appearance = NSAppearance(named: .darkAqua)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let state = AppState()
        let size = NSSize(width: 1280, height: 800)
        let host = NSHostingView(rootView: ContentView().environmentObject(state).frame(width: size.width, height: size.height))
        let win = NSWindow(contentRect: NSRect(origin: NSPoint(x: -6000, y: -6000), size: size), styleMask: [.borderless],
                           backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        win.orderFrontRegardless()

        func shoot(_ name: String) {
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            print("wrote \(name).png")
        }

        var step = 0
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            MainActor.assumeIsolated {
                step += 1
                if step == 6 { shoot("00-dashboard-prescan"); state.startScan(.quick) }
                if step == 12 && state.scanState == .running { shoot("01-scanner-running") }
                guard step > 12, state.scanState == .finished, !state.resolving, !state.refreshing else { return }
                t.invalidate()
                for (i, s) in Section.allCases.enumerated() {
                    state.section = s
                    RunLoop.main.run(until: Date().addingTimeInterval(0.8))
                    shoot(String(format: "%02d-", i + 2) + s.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))
                }
                exit(0)
            }
        }
        nsApp.run()
    }
}
