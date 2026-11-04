import AppKit
import Foundation

enum Section: String, CaseIterable, Identifiable {
    case dashboard = "DASHBOARD", scanner = "STORAGE SCANNER", largeFiles = "LARGE FILES", systemData = "SYSTEM DATA",
         caches = "CACHE CLEANER", appData = "APPLICATION DATA", timeMachine = "TIME MACHINE", backups = "iOS BACKUPS",
         developer = "DEVELOPER FILES", queue = "CLEANUP QUEUE", settings = "SETTINGS"
    var id: String { rawValue }
}

enum ScanState: Equatable {
    case idle, running, paused, finished, cancelled
    var label: String {
        switch self {
        case .idle: return "IDLE"
        case .running: return "SCANNING"
        case .paused: return "PAUSED"
        case .finished: return "SCAN COMPLETE"
        case .cancelled: return "SCAN CANCELLED"
        }
    }
}

struct Baseline {
    var applications: Int64 = 0
    var documents: Int64 = 0   // Desktop + Documents + Downloads
    var media: Int64 = 0       // Pictures + Movies + Music
    var trash: Int64? = nil    // nil = unreadable without Full Disk Access
}

struct CategorySummary: Identifiable {
    var id: Category { category }
    let category: Category
    var size: Int64
    var files: Int
    var recoverable: Int64
    var risk: Risk
    var status: String
    var items: [CleanupItem]
}

@MainActor
final class AppState: ObservableObject {
    @Published var section: Section = .dashboard
    @Published var settings: SolidSettings { didSet { if settings != oldValue { Store.save("settings.json", settings) } } }

    @Published var volume = VolumeInfo()
    @Published var apfs = APFSInfo()
    @Published var baseline: Baseline?
    @Published var swap: (total: Int64, used: Int64) = (0, 0)
    @Published var fullDiskAccess = false
    @Published var refreshing = false

    @Published var scanState: ScanState = .idle
    @Published var scanKind: ScanKind = .full
    @Published var progress = ScanProgress()
    @Published var lastResult: ScanResult?
    @Published var candidates: [CleanupItem] = []
    @Published var appData: [CleanupItem] = []
    @Published var largeFiles: [FileEntry] = []
    @Published var resolving = false

    @Published var tmSnapshots: [Snapshot] = []
    @Published var apfsSnapshots: [Snapshot] = []
    @Published var tmDestination = ""
    @Published var iosBackups: [IOSBackup] = []
    @Published var iosBackupsDenied = false
    @Published var brewEstimate: (bytes: Int64, text: String)?
    @Published var dockerReport: String?

    @Published var queue: [CleanupItem] = []
    @Published var log: [LogEntry]
    @Published var history: [ScanRecord]
    @Published var executing = false
    @Published var execProgress = ""
    @Published var lastRun: (before: Int64, after: Int64, items: Int)?

    private var control = ScanControl()

    init() {
        settings = Store.load("settings.json", SolidSettings.self) ?? SolidSettings()
        log = Store.load("cleanup-log.json", [LogEntry].self) ?? []
        history = Store.load("scan-history.json", [ScanRecord].self) ?? []
    }

    // MARK: Derived

    var lastScanDate: Date? { history.first?.date }

    var systemDataEstimate: Int64? {
        guard let b = baseline else { return nil }
        let used = volume.used
        let macOS = apfs.used(role: "System")
        return max(0, used - macOS - b.applications - b.documents - b.media - (b.trash ?? 0))
    }

    var recoverableLowMedium: Int64 {
        (candidates + appData.filter { $0.risk == .medium }).filter { $0.risk <= .medium }.reduce(0) { $0 + $1.size }
    }

    var queueTotal: Int64 { queue.reduce(0) { $0 + $1.size } }

    func inQueue(_ id: String) -> Bool { queue.contains { $0.id == id } }

    // MARK: Refresh

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task.detached(priority: .userInitiated) {
            let v = SystemInfo.volume()
            let a = SystemInfo.apfs()
            let s = SystemInfo.swap()
            let fda = SystemInfo.hasFullDiskAccess()
            let tm = SystemInfo.timeMachineSnapshots()
            let ap = SystemInfo.apfsSnapshots()
            let dest = SystemInfo.timeMachineDestination()
            await MainActor.run {
                self.volume = v; self.apfs = a; self.swap = s; self.fullDiskAccess = fda
                self.tmSnapshots = tm; self.apfsSnapshots = ap; self.tmDestination = dest
            }
            let h = Guard.home
            let m: (String) -> Int64 = { Scanner.measure($0).size }
            var b = Baseline()
            b.applications = m("/Applications")
            b.documents = m(h + "/Desktop") + m(h + "/Documents") + m(h + "/Downloads")
            b.media = m(h + "/Pictures") + m(h + "/Movies") + m(h + "/Music")
            if (try? FileManager.default.contentsOfDirectory(atPath: h + "/.Trash")) != nil { b.trash = m(h + "/.Trash") }
            let ios = SystemInfo.iosBackups()
            let final = b
            await MainActor.run {
                self.baseline = final
                self.iosBackups = ios.backups
                self.iosBackupsDenied = ios.denied
                self.refreshing = false
            }
        }
    }

    // MARK: Scan

    func startScan(_ kind: ScanKind) {
        guard scanState != .running && scanState != .paused else { return }
        control = ScanControl()
        let ctl = control
        scanKind = kind
        scanState = .running
        progress = ScanProgress()
        section = .scanner
        let roots = kind == .full ? ["/System/Volumes/Data"] : [Guard.home]
        var opts = Scanner.Options()
        opts.depth = settings.scanDepth + (kind == .full ? 3 : 0)   // full scan root is 3 levels above home
        opts.minFileSize = settings.minFileSize
        opts.excluded = settings.excluded

        Task.detached(priority: .userInitiated) {
            let result = Scanner.scan(kind: kind, roots: roots, options: opts, control: ctl) { p in
                Task { @MainActor in self.progress = p }
            }
            await MainActor.run {
                self.lastResult = result
                self.largeFiles = result.largeFiles
                self.progress.files = result.files
                self.progress.bytes = result.bytes
                self.progress.denied = result.denied.count
                self.progress.elapsed = result.duration
                self.history.insert(ScanRecord(date: result.date, kind: kind, duration: result.duration, files: result.files,
                                               bytes: result.bytes, denied: result.denied.count, cancelled: result.cancelled), at: 0)
                Store.save("scan-history.json", self.history)
                self.scanState = result.cancelled ? .cancelled : .finished
                self.resolving = !result.cancelled
            }
            guard !result.cancelled else { return }
            let lookup: (String) -> DirStat? = { result.dirs[$0] }
            let items = Rules.resolve(lookup: lookup, control: ctl)
            let apps = Rules.appData(lookup: lookup, control: ctl)
            let brew = Self.brewEstimate()
            let docker = Self.dockerReport()
            await MainActor.run {
                self.candidates = items
                self.appData = apps
                self.brewEstimate = brew
                self.dockerReport = docker
                self.resolving = false
            }
        }
        refresh()
    }

    func pauseScan() { control.pause(); scanState = .paused }
    func resumeScan() { control.resume(); scanState = .running }
    func cancelScan() { control.cancel() }

    nonisolated static func brewEstimate() -> (Int64, String)? {
        guard let brew = Shell.brew else { return nil }
        let r = Shell.run(brew, ["cleanup", "-n", "--prune=all"], timeout: 120)
        let text = (r.out + r.err)
        let line = text.split(separator: "\n").last { $0.contains("free approximately") }.map(String.init)
        return (line.flatMap(parseSize) ?? 0, line ?? "Nothing to clean.")
    }

    nonisolated static func dockerReport() -> String? {
        guard let docker = Shell.docker else { return nil }
        let r = Shell.run(docker, ["system", "df"], timeout: 15)
        return r.ok ? r.out : "Docker CLI found but the engine is not running. Start Docker Desktop to see image/volume usage."
    }

    /// Parses "1.23GB", "456.7MB", "12 KB" etc.
    nonisolated static func parseSize(_ s: String) -> Int64? {
        guard let m = s.range(of: #"([0-9.]+)\s*([KMGT]i?B)"#, options: .regularExpression) else { return nil }
        let token = String(s[m]).replacingOccurrences(of: " ", with: "")
        let num = Double(token.prefix { "0123456789.".contains($0) }) ?? 0
        let unit = token.drop { "0123456789.".contains($0) }.uppercased()
        let mult: Double = unit.hasPrefix("K") ? 1e3 : unit.hasPrefix("M") ? 1e6 : unit.hasPrefix("G") ? 1e9 : 1e12
        return Int64(num * mult)
    }

    // MARK: Categories

    var categorySummaries: [CategorySummary] {
        var out: [CategorySummary] = []
        // App-data folders that contain rule candidates (e.g. Docker, Claude) are reduced by those sizes: no double counting.
        let apps = appData.filter { $0.risk != .protected }.map { a -> CleanupItem in
            var a = a
            let nested = candidates.filter { Guard.isInside($0.path, a.path) }
            a.size = max(0, a.size - nested.reduce(0) { $0 + $1.size })
            a.fileCount = max(0, a.fileCount - nested.reduce(0) { $0 + $1.fileCount })
            return a
        }
        let pool = candidates + apps
        for c in Category.allCases {
            let items = pool.filter { $0.category == c }
            var s = CategorySummary(category: c, size: items.reduce(0) { $0 + $1.size }, files: items.reduce(0) { $0 + $1.fileCount },
                                    recoverable: items.filter { $0.risk <= .medium }.reduce(0) { $0 + $1.size },
                                    risk: items.map(\.risk).max() ?? .low,
                                    status: lastResult == nil ? "Not scanned" : "Measured", items: items)
            switch c {
            case .tmSnapshots:
                s.files = tmSnapshots.count
                s.status = "\(tmSnapshots.count) snapshot(s). APFS does not expose per-snapshot size."
                s.risk = tmSnapshots.isEmpty ? .low : .medium
            case .apfsSnapshots:
                s.files = apfsSnapshots.count
                s.status = "\(apfsSnapshots.count) on Data volume. Size not exposed."
                s.risk = .protected
            case .swap:
                s.size = apfs.used(role: "VM")
                s.recoverable = 0
                s.risk = .protected
                s.status = "Measured (VM volume). Swap used \(Fmt.bytes(swap.used)) of \(Fmt.bytes(swap.total))."
            case .other:
                if let est = systemDataEstimate {
                    let attributed = out.reduce(0) { $0 + $1.size }
                    s.size = max(0, est - attributed)
                    s.status = "Estimated: System Data estimate minus measured categories. Includes Preboot/Recovery, " +
                               (fullDiskAccess ? "APFS metadata." : "APFS metadata and folders unreadable without Full Disk Access.")
                } else {
                    s.status = "Waiting for refresh"
                }
                s.risk = .protected
                s.recoverable = 0
            case .iosBackups where iosBackupsDenied:
                s.status = "Needs Full Disk Access"
            default: break
            }
            out.append(s)
        }
        return out
    }

    // MARK: Queue

    func enqueue(_ items: [CleanupItem]) {
        for item in items where item.risk != .protected && !inQueue(item.id) {
            if queue.contains(where: { $0.method.isPathBased && item.method.isPathBased && Guard.isInside(item.path, $0.path) }) { continue }
            queue.removeAll { $0.method.isPathBased && item.method.isPathBased && Guard.isInside($0.path, item.path) }
            queue.append(item)
        }
    }

    func dequeue(_ ids: Set<String>) { queue.removeAll { ids.contains($0.id) } }

    func cleanupItem(for f: FileEntry) -> CleanupItem {
        let risk: Risk = f.status == .protected ? .protected : (f.status == .personal ? .high : .medium)
        let reason: String
        switch f.status {
        case .personal: reason = "Large personal file selected manually."
        case .system: reason = "Large application data file selected manually."
        default: reason = "Large file selected manually."
        }
        return CleanupItem(id: f.path, name: f.name, path: f.path, size: f.allocated, fileCount: 1, app: Rules.appName(for: f.path),
                           category: .other, risk: risk, method: .trash, reason: reason, personal: f.status == .personal)
    }

    func executeQueue() {
        guard !executing, !queue.isEmpty else { return }
        executing = true
        let items = queue
        let ctx = DeletionEngine.Context(userProtected: settings.protectedPaths, forceTrash: settings.alwaysUseTrash)
        let before = SystemInfo.volume().available
        Task.detached(priority: .userInitiated) {
            var done: [String] = []
            for (i, item) in items.enumerated() {
                await MainActor.run { self.execProgress = "[\(i + 1)/\(items.count)] \(Fmt.display(item.path))" }
                let entry = DeletionEngine.execute(item, ctx: ctx)
                if entry.result == .success || entry.result == .partial { done.append(item.id) }
                await MainActor.run { self.log.insert(entry, at: 0) }
            }
            let after = SystemInfo.volume().available
            let finished = done
            await MainActor.run {
                Store.save("cleanup-log.json", self.log)
                self.queue.removeAll { finished.contains($0.id) }
                self.candidates.removeAll { finished.contains($0.id) }
                self.appData.removeAll { finished.contains($0.id) }
                self.largeFiles.removeAll { finished.contains($0.id) }
                self.lastRun = (before, after, items.count)
                self.execProgress = ""
                self.executing = false
                self.refresh()
            }
        }
    }

    func emptyTrash() {
        let item = CleanupItem(id: "op:empty-trash", name: "Empty Trash", path: Guard.home + "/.Trash", size: baseline?.trash ?? 0,
                               fileCount: 0, app: "Finder", category: .temp, risk: .high,
                               method: .command(tool: "/usr/bin/osascript", args: ["-e", "tell application \"Finder\" to empty trash"], admin: false),
                               reason: "Items in the Trash still use disk space until it is emptied.")
        enqueue([item])
        section = .queue
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFullDiskAccessSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(u)
        }
    }

    func clearLog() { log = []; Store.save("cleanup-log.json", log) }
    func clearHistory() { history = []; Store.save("scan-history.json", history) }
}
