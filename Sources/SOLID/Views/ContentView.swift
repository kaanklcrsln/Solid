import SwiftUI

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            Header()
            Rectangle().fill(T.border).frame(height: 1)
            HStack(spacing: 0) {
                Sidebar()
                Rectangle().fill(T.border).frame(width: 1)
                Group {
                    switch app.section {
                    case .dashboard: DashboardView()
                    case .scanner: ScannerView()
                    case .largeFiles: LargeFilesView()
                    case .systemData: SystemDataView()
                    case .caches: CacheCleanerView()
                    case .appData: AppDataView()
                    case .timeMachine: TimeMachineView()
                    case .backups: BackupsView()
                    case .developer: DeveloperView()
                    case .queue: QueueView()
                    case .settings: SettingsView()
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(T.bg)
            }
            Rectangle().fill(T.border).frame(height: 1)
            Footer()
        }
        .background(T.bg)
        .foregroundColor(T.text)
        .preferredColorScheme(.dark)
        .onAppear { app.refresh() }
    }
}

struct Header: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        HStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("SOLID").font(T.mono(15, .heavy)).tracking(3)
                Text("macOS Cleaner").font(T.mono(10)).foregroundColor(T.dim)
            }
            Rectangle().fill(T.border).frame(width: 1, height: 18)
            Text(app.volume.name.uppercased()).font(T.mono(11, .semibold))
            UsageBar(segments: [Segment(label: "Used", value: app.volume.used, shade: 0.8)], total: app.volume.total, height: 8)
                .frame(width: 140)
            Text("\(pct)%  ·  \(Fmt.bytes(app.volume.available)) FREE").font(T.mono(10)).foregroundColor(T.dim)
            Spacer()
            Text(status).font(T.mono(10, .semibold)).foregroundColor(app.scanState == .running ? T.text : T.dim)
            SButton(app.refreshing ? "REFRESHING" : "REFRESH") { app.refresh() }.disabled(app.refreshing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(T.sidebar)
    }

    private var pct: Int { app.volume.total > 0 ? Int(Double(app.volume.used) / Double(app.volume.total) * 100) : 0 }

    private var status: String {
        if app.executing { return "CLEANING" }
        if app.resolving { return "CLASSIFYING" }
        return app.scanState == .idle ? "SYSTEM: ONLINE" : app.scanState.label
    }
}

struct Sidebar: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Section.allCases) { s in
                Button { app.section = s } label: {
                    HStack {
                        Text(s.rawValue).font(T.mono(11, app.section == s ? .bold : .regular))
                        Spacer()
                        if s == .queue && !app.queue.isEmpty {
                            Text("\(app.queue.count)").font(T.mono(10, .bold))
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundColor(app.section == s ? .black : T.text)
                    .background(app.section == s ? T.text : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if s == .scanner || s == .developer { Rectangle().fill(T.border).frame(height: 1).padding(.vertical, 5) }
            }
            Spacer()
            if !app.fullDiskAccess {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIMITED ACCESS").font(T.mono(9, .bold)).foregroundColor(T.text)
                    Text("Mail, Messages, Trash and some system folders are not measured.").font(T.mono(9)).foregroundColor(T.dim)
                    Button("Grant Full Disk Access…") { app.openFullDiskAccessSettings() }
                        .buttonStyle(.plain).font(T.mono(9, .semibold)).underline()
                }
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(T.border, lineWidth: 1))
            }
        }
        .padding(8)
        .frame(width: 196)
        .background(T.sidebar)
    }
}

struct Footer: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        HStack {
            Text("SOLID v1.0.0").font(T.mono(9))
            Text("·  \(app.fullDiskAccess ? "FULL DISK ACCESS" : "STANDARD ACCESS")").font(T.mono(9))
            if app.executing { Text("·  \(app.execProgress)").font(T.mono(9)).lineLimit(1).truncationMode(.middle) }
            Spacer()
            Text("LOCAL ONLY  ·  NO NETWORK").font(T.mono(9))
        }
        .foregroundColor(T.dim)
        .padding(.horizontal, 12).padding(.vertical, 4)
        .background(T.sidebar)
    }
}
