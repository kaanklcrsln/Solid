import AppKit
import SwiftUI

struct SolidApp: App {
    @StateObject private var app = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("SOLID") {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 1120, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Full System Scan") { app.startScan(.full) }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Quick Scan") { app.startScan(.quick) }.keyboardShortcut("r")
                Button("Cancel Scan") { app.cancelScan() }.keyboardShortcut(".")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

let args = CommandLine.arguments
if args.contains("--selftest") {
    exit(MainActor.assumeIsolated { SelfTest.run() } ? 0 : 1)
} else if let i = args.firstIndex(of: "--scan"), i + 1 < args.count {
    SelfTest.headlessScan(args[i + 1])   // read-only report, no deletion
    exit(0)
} else if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    MainActor.assumeIsolated { UISnapshot.run(args[i + 1]) }
} else {
    SolidApp.main()
}
