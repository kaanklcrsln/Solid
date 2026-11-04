import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Panel(title: "STORAGE OVERVIEW · \(app.volume.name.uppercased())") {
                    VStack(alignment: .leading, spacing: 10) {
                        UsageBar(segments: segments, total: app.volume.total, height: 18)
                        Legend(segments: segments + [Segment(label: "Free", value: app.volume.available, shade: 0.13)])
                        Rectangle().fill(T.border).frame(height: 1)
                        HStack {
                            Stat(label: "CAPACITY", value: Fmt.bytes(app.volume.total))
                            Stat(label: "USED", value: Fmt.bytes(app.volume.used))
                            Stat(label: "AVAILABLE", value: Fmt.bytes(app.volume.available),
                                 sub: app.volume.purgeable > 0 ? "+\(Fmt.bytes(app.volume.purgeable)) purgeable" : "no purgeable space")
                            Stat(label: "SYSTEM DATA (EST.)", value: app.systemDataEstimate.map(Fmt.bytes) ?? "…",
                                 sub: "used − macOS − apps − user files")
                        }
                        Note(text: "System Data is computed by macOS from opaque rules. SOLID shows an estimate and, after a scan, the measured files behind it.")
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Panel(title: "CATEGORIES") {
                        VStack(alignment: .leading, spacing: 4) {
                            KV(k: "macOS (sealed)", v: Fmt.bytes(app.apfs.used(role: "System")))
                            KV(k: "Applications", v: app.baseline.map { Fmt.bytes($0.applications) } ?? "measuring…")
                            KV(k: "Documents", v: app.baseline.map { Fmt.bytes($0.documents) } ?? "measuring…")
                            KV(k: "Media", v: app.baseline.map { Fmt.bytes($0.media) } ?? "measuring…")
                            KV(k: "Trash", v: app.baseline.map { $0.trash.map(Fmt.bytes) ?? "needs Full Disk Access" } ?? "measuring…")
                            KV(k: "Preboot+Recovery", v: Fmt.bytes(app.apfs.used(role: "Preboot") + app.apfs.used(role: "Recovery")))
                            KV(k: "VM (swap)", v: Fmt.bytes(app.apfs.used(role: "VM")))
                            KV(k: "Snapshots", v: "\(app.tmSnapshots.count) Time Machine · \(app.apfsSnapshots.count) APFS")
                        }
                    }
                    Panel(title: "SCAN OPERATIONS") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                SButton("FULL SYSTEM SCAN", primary: true) { app.startScan(.full) }
                                SButton("QUICK SCAN") { app.startScan(.quick) }
                            }
                            .disabled(app.scanState == .running || app.scanState == .paused)
                            Note(text: "FULL: entire Data volume. QUICK: home folder only. Both are read-only.")
                            Rectangle().fill(T.border).frame(height: 1)
                            HStack {
                                Stat(label: "LAST SCAN", value: app.lastScanDate.map { Fmt.date($0) } ?? "Never")
                                Stat(label: "LARGE FILES", value: app.lastResult == nil ? "—" : "\(app.largeFiles.count)",
                                     sub: "≥ \(Fmt.bytes(app.settings.minFileSize))")
                            }
                            HStack {
                                Stat(label: "RECOVERABLE (LOW/MED)", value: app.lastResult == nil ? "—" : Fmt.bytes(app.recoverableLowMedium))
                                Stat(label: "CANDIDATES", value: app.lastResult == nil ? "—" : "\(app.candidates.filter { $0.risk != .protected }.count)")
                            }
                            if let t = app.baseline?.trash, t > 0 {
                                HStack {
                                    Note(text: "Trash holds \(Fmt.bytes(t)). It is freed only when emptied.")
                                    Spacer()
                                    SButton("EMPTY TRASH…") { app.emptyTrash() }
                                }
                            }
                        }
                    }
                }

                if let run = app.lastRun {
                    Panel(title: "LAST CLEANUP") {
                        HStack {
                            Stat(label: "AVAILABLE BEFORE", value: Fmt.bytes(run.before))
                            Stat(label: "AVAILABLE AFTER", value: Fmt.bytes(run.after))
                            Stat(label: "RECOVERED", value: Fmt.bytes(run.after - run.before))
                            Stat(label: "OPERATIONS", value: "\(run.items)")
                        }
                    }
                }
            }
        }
    }

    private var segments: [Segment] {
        let b = app.baseline ?? Baseline()
        var s = [
            Segment(label: "macOS", value: app.apfs.used(role: "System"), shade: 0.92),
            Segment(label: "Apps", value: b.applications, shade: 0.75),
            Segment(label: "Documents", value: b.documents, shade: 0.6),
            Segment(label: "Media", value: b.media, shade: 0.48),
        ]
        if let t = b.trash { s.append(Segment(label: "Trash", value: t, shade: 0.4)) }
        s.append(Segment(label: "System Data", value: app.systemDataEstimate ?? 0, shade: 0.32))
        return s
    }
}

struct ScannerView: View {
    @EnvironmentObject var app: AppState
    @State private var showDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Panel(title: "STORAGE SCANNER") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SButton("FULL SYSTEM SCAN", primary: true) { app.startScan(.full) }.disabled(busy)
                        SButton("QUICK SCAN") { app.startScan(.quick) }.disabled(busy)
                        Rectangle().fill(T.border).frame(width: 1, height: 18)
                        if app.scanState == .paused {
                            SButton("RESUME") { app.resumeScan() }
                        } else {
                            SButton("PAUSE") { app.pauseScan() }.disabled(app.scanState != .running)
                        }
                        SButton("CANCEL") { app.cancelScan() }.disabled(!busy)
                        Spacer()
                        Text(app.scanState.label).font(T.mono(11, .bold))
                    }
                    ProgressView(value: fraction).progressViewStyle(.linear).tint(T.text)
                    HStack {
                        Stat(label: "ELAPSED", value: Fmt.duration(app.progress.elapsed))
                        Stat(label: "FILES", value: Fmt.count(app.progress.files))
                        Stat(label: "MEASURED", value: Fmt.bytes(app.progress.bytes))
                        Stat(label: "ACCESS DENIED", value: Fmt.count(app.progress.denied))
                    }
                    KV(k: "Current", v: busy ? Fmt.display(app.progress.currentPath) : "—")
                    KV(k: "Roots", v: app.scanKind == .full ? "/System/Volumes/Data (entire Data volume, firmlinks counted once)" : "~ (home folder)")
                    KV(k: "Method", v: "fts(3): physical walk, symlinks not followed, no volume crossing, hard links counted once, allocated blocks")
                    if app.resolving { KV(k: "Status", v: "Classifying locations, checking Homebrew and Docker…") }
                }
            }

            if let r = app.lastResult {
                Panel(title: "LARGEST FOLDERS · \(r.kind.rawValue) SCAN \(Fmt.date(r.date))",
                      trailing: AnyView(Button(showDenied ? "Show folders" : "Show \(r.denied.count) denied paths") { showDenied.toggle() }
                        .buttonStyle(.plain).font(T.mono(10)).foregroundColor(T.dim))) {
                    if showDenied {
                        List(r.denied.prefix(2000), id: \.self) { Text(Fmt.display($0)).font(T.mono(10)).foregroundColor(T.dim) }
                            .listStyle(.plain).scrollContentBackground(.hidden)
                    } else {
                        List(topFolders(r), id: \.0) { row in
                            HStack {
                                Text(Fmt.display(row.0)).font(T.mono(11)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(Fmt.count(row.1.count) + " files").font(T.mono(10)).foregroundColor(T.dim).frame(width: 110, alignment: .trailing)
                                Text(Fmt.bytes(row.1.size)).font(T.mono(11, .semibold)).frame(width: 80, alignment: .trailing)
                            }
                            .contextMenu { Button("Reveal in Finder") { app.reveal(row.0) } }
                        }
                        .listStyle(.plain).scrollContentBackground(.hidden)
                    }
                }
            } else {
                Spacer()
            }
        }
    }

    private var busy: Bool { app.scanState == .running || app.scanState == .paused }

    private var fraction: Double {
        if app.scanState == .finished { return 1 }
        let target = app.scanKind == .full ? app.apfs.used(role: "Data") : max(app.progress.bytes, 1)
        return min(1, Double(app.progress.bytes) / Double(max(target, 1)))
    }

    /// Folders ≥ 500 MB whose size is not just one large child, deepest-first information.
    private func topFolders(_ r: ScanResult) -> [(String, DirStat)] {
        r.dirs.filter { $0.value.size >= 500_000_000 && $0.key.split(separator: "/").count >= 2 }
            .sorted { $0.value.size > $1.value.size }
            .prefix(300)
            .map { ($0.key, $0.value) }
    }
}
