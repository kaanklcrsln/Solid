import SwiftUI

struct SystemDataView: View {
    @EnvironmentObject var app: AppState
    @State private var expanded: Category?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Panel(title: "APFS CONTAINER \(app.apfs.container.uppercased())") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Stat(label: "CAPACITY", value: Fmt.bytes(app.apfs.ceiling))
                        Stat(label: "ALLOCATED", value: Fmt.bytes(app.apfs.ceiling - app.apfs.free))
                        Stat(label: "FREE", value: Fmt.bytes(app.apfs.free))
                        Stat(label: "PURGEABLE", value: Fmt.bytes(app.volume.purgeable), sub: "reported by macOS, not file-mapped")
                        Stat(label: "SYSTEM DATA (EST.)", value: app.systemDataEstimate.map(Fmt.bytes) ?? "…")
                    }
                    Rectangle().fill(T.border).frame(height: 1).padding(.vertical, 4)
                    ForEach(app.apfs.volumes) { v in
                        KV(k: v.name, v: "\(Fmt.bytes(v.used))   \(v.device)   \(v.roles.joined(separator: ", "))")
                    }
                }
            }

            if app.lastResult == nil {
                NeedsScan()
            } else {
                HStack {
                    Text("CATEGORY").frame(maxWidth: .infinity, alignment: .leading)
                    Text("SIZE").frame(width: 80, alignment: .trailing)
                    Text("FILES").frame(width: 80, alignment: .trailing)
                    Text("RECOVERABLE").frame(width: 96, alignment: .trailing)
                    Text("RISK").frame(width: 86)
                    Text("STATUS").frame(width: 280, alignment: .leading)
                }
                .font(T.mono(9, .semibold)).foregroundColor(T.dim).padding(.horizontal, 10)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(app.categorySummaries) { c in
                            VStack(spacing: 0) {
                                Button { expanded = expanded == c.category ? nil : c.category } label: {
                                    HStack {
                                        Text((expanded == c.category ? "▾ " : "▸ ") + c.category.title)
                                            .font(T.mono(11, .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                                        Text(Fmt.bytes(c.size)).font(T.mono(11, .semibold)).frame(width: 80, alignment: .trailing)
                                        Text(c.files > 0 ? Fmt.count(c.files) : "—").font(T.mono(10)).foregroundColor(T.dim)
                                            .frame(width: 80, alignment: .trailing)
                                        Text(Fmt.bytes(c.recoverable)).font(T.mono(11)).frame(width: 96, alignment: .trailing)
                                        RiskBadge(risk: c.risk).frame(width: 86)
                                        Text(c.status).font(T.mono(9)).foregroundColor(T.dim).lineLimit(2)
                                            .frame(width: 280, alignment: .leading)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if expanded == c.category {
                                    Group {
                                        if c.items.isEmpty {
                                            Note(text: detailText(c.category)).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                        } else {
                                            ItemTable(items: c.items).frame(height: min(360, CGFloat(c.items.count) * 24 + 80)).padding(6)
                                        }
                                    }
                                }
                            }
                            .background(T.panel)
                            .clipShape(RoundedRectangle(cornerRadius: T.radius))
                            .overlay(RoundedRectangle(cornerRadius: T.radius).stroke(T.border, lineWidth: 1))
                        }
                    }
                }
            }
        }
    }

    private func detailText(_ c: Category) -> String {
        switch c {
        case .tmSnapshots, .apfsSnapshots: return "Manage snapshots in the Time Machine section."
        case .swap: return "Swap files and sleepimage live in /private/var/vm and the VM volume. They are managed by the kernel and are never deleted. Swap shrinks after a restart or when memory pressure drops."
        case .other: return "Space that cannot be mapped to a readable file: APFS metadata, Preboot/Recovery volumes, TCC-protected folders, and macOS bookkeeping. Grant Full Disk Access and rescan to reduce the unattributed part."
        case .updates: return "No update leftovers found outside SIP-restricted locations."
        default: return "Nothing found in this category."
        }
    }
}

struct CacheCleanerView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Note(text: "Rebuildable caches, logs and temporary files. Apps recreate them as needed; quit an app before clearing its cache.")
            if app.lastResult == nil { NeedsScan() } else {
                ItemTable(items: app.candidates.filter { [.appCaches, .logs, .temp].contains($0.category) })
            }
        }
    }
}

struct AppDataView: View {
    @EnvironmentObject var app: AppState
    @State private var orphansOnly = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Note(text: "Top-level folders in Application Support, Containers and Group Containers (≥ 1 MB). Installed-app data is HIGH risk; folders with no matching app are MEDIUM. Apple folders are protected. Nothing here is auto-selected.")
                Spacer()
                Toggle("No matching app only", isOn: $orphansOnly).toggleStyle(.checkbox).font(T.mono(10))
            }
            if app.lastResult == nil { NeedsScan() } else {
                ItemTable(items: orphansOnly ? app.appData.filter { $0.risk == .medium } : app.appData, autoSelectMaxRisk: .low)
            }
        }
    }
}

struct TimeMachineView: View {
    @EnvironmentObject var app: AppState
    @State private var selected = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Panel(title: "TIME MACHINE") {
                VStack(alignment: .leading, spacing: 4) {
                    KV(k: "Destination", v: app.tmDestination)
                    KV(k: "Local snapshots", v: "\(app.tmSnapshots.count)")
                    KV(k: "APFS snapshots", v: "\(app.apfsSnapshots.count) on Data volume")
                    KV(k: "Purgeable", v: Fmt.bytes(app.volume.purgeable))
                    Note(text: "Snapshot sizes are not exposed by APFS. Local snapshots are purgeable: macOS deletes them automatically under disk pressure. Deleting uses `tmutil deletelocalsnapshots` and needs administrator rights (macOS will prompt).")
                        .padding(.top, 4)
                }
            }
            Panel(title: "LOCAL SNAPSHOTS") {
                if app.tmSnapshots.isEmpty && app.apfsSnapshots.isEmpty {
                    Note(text: "No local snapshots. Snapshots are not using any space on this Mac.")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(app.tmSnapshots) { s in
                            HStack {
                                Check(on: selected.contains(s.name), enabled: !s.date.isEmpty) {
                                    if selected.contains(s.name) { selected.remove(s.name) } else { selected.insert(s.name) }
                                }
                                Text(s.name).font(T.mono(11))
                                Spacer()
                                Text(s.isTimeMachine ? "TIME MACHINE" : "OTHER").font(T.mono(9)).foregroundColor(T.dim)
                            }
                        }
                        ForEach(app.apfsSnapshots.filter { s in !app.tmSnapshots.contains { $0.name == s.name } }) { s in
                            HStack {
                                Text("    " + s.name).font(T.mono(11)).foregroundColor(T.dim)
                                Spacer()
                                Text("APFS (system managed)").font(T.mono(9)).foregroundColor(T.dim)
                            }
                        }
                        HStack {
                            Spacer()
                            SButton("DELETE SELECTED") {
                                app.enqueue(app.tmSnapshots.filter { selected.contains($0.name) }.map(item(for:)))
                                selected.removeAll()
                                app.section = .queue
                            }.disabled(selected.isEmpty)
                            SButton("THIN ALL LOCAL SNAPSHOTS") {
                                app.enqueue([CleanupItem(id: "op:tm-thin", name: "Thin local snapshots", path: "/", size: app.volume.purgeable,
                                                         fileCount: app.tmSnapshots.count, app: "Time Machine", category: .tmSnapshots,
                                                         risk: .medium, method: .command(tool: "/usr/bin/tmutil",
                                                         args: ["thinlocalsnapshots", "/", "999999999999", "4"], admin: true),
                                                         reason: "Asks macOS to purge as much local snapshot space as possible.")])
                                app.section = .queue
                            }.disabled(app.tmSnapshots.isEmpty)
                        }
                        .padding(.top, 6)
                    }
                }
            }
            Spacer()
        }
    }

    private func item(for s: Snapshot) -> CleanupItem {
        CleanupItem(id: "snap:" + s.name, name: s.name, path: "/", size: 0, fileCount: 0, app: "Time Machine",
                    category: .tmSnapshots, risk: .medium, method: .snapshot(date: s.date),
                    reason: "Local Time Machine snapshot. Size not exposed by APFS.")
    }
}

struct BackupsView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Panel(title: "iOS / iPadOS BACKUPS · ~/Library/Application Support/MobileSync/Backup") {
                if app.iosBackupsDenied {
                    HStack {
                        Note(text: "This folder is protected by macOS privacy controls. Grant SOLID Full Disk Access, then press Refresh.")
                        Spacer()
                        SButton("OPEN PRIVACY SETTINGS") { app.openFullDiskAccessSettings() }
                    }
                } else if app.iosBackups.isEmpty {
                    Note(text: "No local device backups found.").frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Note(text: "Each backup is HIGH risk: it may be the only copy of a device's data. Backups are moved to the Trash, not erased.")
                }
            }
            if !app.iosBackups.isEmpty {
                ItemTable(items: app.iosBackups.map { b in
                    CleanupItem(id: b.path, name: b.device, path: b.path, size: b.size, fileCount: 0, app: b.product,
                                category: .iosBackups, risk: .high, method: .trash,
                                reason: "Device backup, last \(Fmt.date(b.lastBackup)).")
                }, autoSelectMaxRisk: .low)
            }
            Spacer()
        }
    }
}

struct DeveloperView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Panel(title: "HOMEBREW") {
                    VStack(alignment: .leading, spacing: 6) {
                        if Shell.brew == nil {
                            Note(text: "Homebrew not installed.")
                        } else if let b = app.brewEstimate {
                            Note(text: "brew cleanup --prune=all (dry run): \(b.text)")
                            SButton("QUEUE BREW CLEANUP") {
                                app.enqueue([CleanupItem(id: "op:brew-cleanup", name: "brew cleanup", path: "/opt/homebrew", size: b.bytes,
                                                         fileCount: 0, app: "Homebrew", category: .developer, risk: .low,
                                                         method: .command(tool: Shell.brew!, args: ["cleanup", "--prune=all", "-s"], admin: false),
                                                         reason: "Removes old formula versions and the download cache. Installed versions are kept.")])
                            }.disabled(b.bytes == 0 || app.inQueue("op:brew-cleanup"))
                        } else {
                            Note(text: app.lastResult == nil ? "Run a scan to estimate." : "Checking…")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Panel(title: "DOCKER") {
                    VStack(alignment: .leading, spacing: 6) {
                        if Shell.docker == nil {
                            Note(text: "Docker CLI not found.")
                        } else {
                            Text(app.dockerReport ?? (app.lastResult == nil ? "Run a scan to query Docker." : "Checking…"))
                                .font(T.mono(9)).foregroundColor(T.dim).textSelection(.enabled)
                            SButton("QUEUE DOCKER PRUNE") {
                                app.enqueue([CleanupItem(id: "op:docker-prune", name: "docker system prune", path: "Docker", size: 0, fileCount: 0,
                                                         app: "Docker Desktop", category: .developer, risk: .high,
                                                         method: .command(tool: Shell.docker!, args: ["system", "prune", "-af", "--volumes"], admin: false),
                                                         reason: "Deletes all stopped containers, unused images, networks, build cache and volumes. Docker.raw shrinks over time, not immediately.")])
                            }.disabled(app.inQueue("op:docker-prune"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            if app.lastResult == nil { NeedsScan() } else {
                ItemTable(items: app.candidates.filter { $0.category == .developer || $0.category == .updates })
            }
        }
    }
}
