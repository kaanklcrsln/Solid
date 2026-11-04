import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    private let sizes: [(String, Int64)] = [("50 MB", 50_000_000), ("100 MB", 100_000_000), ("500 MB", 500_000_000),
                                            ("1 GB", 1_000_000_000), ("5 GB", 5_000_000_000)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Panel(title: "SCANNING") {
                        VStack(alignment: .leading, spacing: 8) {
                            KV(k: "Theme", v: "Dark (default)")
                            HStack {
                                Text("Folder depth").font(T.mono(10)).foregroundColor(T.dim).frame(width: 120, alignment: .leading)
                                Stepper("\(app.settings.scanDepth) levels below home", value: $app.settings.scanDepth, in: 2...12)
                                    .font(T.mono(10))
                            }
                            HStack {
                                Text("Min. large file").font(T.mono(10)).foregroundColor(T.dim).frame(width: 120, alignment: .leading)
                                Picker("", selection: $app.settings.minFileSize) { ForEach(sizes, id: \.1) { Text($0.0).tag($0.1) } }
                                    .frame(width: 120)
                            }
                            Note(text: "Depth controls how many folder levels keep individual totals. Files are always counted at every depth.")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Panel(title: "CONFIRMATION") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Move everything to Trash (never remove directly)", isOn: $app.settings.alwaysUseTrash)
                            Toggle("Require typed confirmation for MEDIUM risk too", isOn: $app.settings.confirmMediumTwice)
                            Note(text: "HIGH risk and personal files always require typed confirmation. Protected items can never be deleted.")
                        }
                        .toggleStyle(.checkbox).font(T.mono(10))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 10) {
                    PathList(title: "EXCLUDED DIRECTORIES (NOT SCANNED)", paths: $app.settings.excluded)
                    PathList(title: "PROTECTED DIRECTORIES (NEVER DELETED)", paths: $app.settings.protectedPaths)
                }

                Panel(title: "BUILT-IN PROTECTION") {
                    Text(Guard.protectedTrees.map(Fmt.display).joined(separator: "  ·  "))
                        .font(T.mono(9)).foregroundColor(T.dim).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Panel(title: "SCAN HISTORY", trailing: AnyView(Button("Clear") { app.clearHistory() }.buttonStyle(.plain).font(T.mono(10)))) {
                    VStack(alignment: .leading, spacing: 3) {
                        if app.history.isEmpty { Note(text: "No scans yet.") }
                        ForEach(app.history.prefix(30)) { h in
                            HStack {
                                Text(Fmt.date(h.date)).frame(width: 130, alignment: .leading)
                                Text(h.kind.rawValue + (h.cancelled ? " (cancelled)" : "")).frame(width: 130, alignment: .leading)
                                Text(Fmt.duration(h.duration)).frame(width: 80, alignment: .leading)
                                Text("\(Fmt.count(h.files)) files").frame(width: 120, alignment: .leading)
                                Text(Fmt.bytes(h.bytes)).frame(width: 90, alignment: .leading)
                                Text("\(h.denied) denied").foregroundColor(T.dim)
                                Spacer()
                            }
                            .font(T.mono(10))
                        }
                    }
                }

                Panel(title: "CLEANUP HISTORY", trailing: AnyView(Button("Clear") { app.clearLog() }.buttonStyle(.plain).font(T.mono(10)))) {
                    VStack(alignment: .leading, spacing: 3) {
                        if app.log.isEmpty { Note(text: "No cleanup operations yet.") }
                        ForEach(app.log.prefix(50)) { e in
                            HStack {
                                Text(Fmt.date(e.date)).frame(width: 130, alignment: .leading)
                                Text(e.result.rawValue).frame(width: 70, alignment: .leading)
                                Text(Fmt.bytes(e.size)).frame(width: 80, alignment: .leading)
                                Text(Fmt.display(e.path)).foregroundColor(T.dim).lineLimit(1).truncationMode(.middle)
                                Spacer()
                            }
                            .font(T.mono(10))
                        }
                        SButton("OPEN DATA FOLDER") { NSWorkspace.shared.open(URL(fileURLWithPath: Store.dir)) }.padding(.top, 4)
                    }
                }
            }
        }
    }
}

struct PathList: View {
    let title: String
    @Binding var paths: [String]
    @State private var focus: String?

    var body: some View {
        Panel(title: title) {
            VStack(alignment: .leading, spacing: 6) {
                List(paths, id: \.self, selection: $focus) { Text(Fmt.display($0)).font(T.mono(10)) }
                    .listStyle(.plain).scrollContentBackground(.hidden).frame(height: 110)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(T.border, lineWidth: 1))
                HStack {
                    SButton("ADD…") { add() }
                    SButton("REMOVE") { paths.removeAll { $0 == focus }; focus = nil }.disabled(focus == nil)
                }
            }
        }
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK {
            for u in panel.urls where !paths.contains(u.path) { paths.append(u.path) }
        }
    }
}
