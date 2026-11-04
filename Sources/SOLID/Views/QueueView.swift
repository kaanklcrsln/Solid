import SwiftUI

struct QueueView: View {
    @EnvironmentObject var app: AppState
    @State private var focus = Set<CleanupItem.ID>()
    @State private var confirming = false

    var body: some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TOTAL SELECTED FOR CLEANUP: \(Fmt.bytes(app.queueTotal))").font(T.mono(13, .bold))
                    Text("\(app.queue.count) item(s)").font(T.mono(10)).foregroundColor(T.dim)
                    Spacer()
                    SButton("REMOVE FROM QUEUE") { app.dequeue(focus); focus.removeAll() }.disabled(focus.isEmpty || app.executing)
                    SButton("CLEAR QUEUE") { app.queue.removeAll() }.disabled(app.queue.isEmpty || app.executing)
                    SButton(app.executing ? "CLEANING…" : "EXECUTE CLEANUP", primary: true) { confirming = true }
                        .disabled(app.queue.isEmpty || app.executing)
                }
                Table(app.queue, selection: $focus) {
                    TableColumn("") { (i: CleanupItem) in
                        Button("✕") { app.dequeue([i.id]) }.buttonStyle(.plain).font(T.mono(11)).foregroundColor(T.dim)
                            .disabled(app.executing)
                    }.width(22)
                    TableColumn("NAME") { (i: CleanupItem) in Text(i.name).font(T.mono(11)) }.width(min: 110, ideal: 160)
                    TableColumn("FULL PATH") { (i: CleanupItem) in
                        Text(Fmt.display(i.path)).font(T.mono(10)).foregroundColor(T.dim).truncationMode(.middle).help(i.path)
                    }.width(min: 160, ideal: 300)
                    TableColumn("SIZE") { (i: CleanupItem) in Text(Fmt.bytes(i.size)).font(T.mono(11, .semibold)) }.width(76)
                    TableColumn("APP") { (i: CleanupItem) in Text(i.app).font(T.mono(10)).foregroundColor(T.dim) }.width(100)
                    TableColumn("RISK") { (i: CleanupItem) in RiskBadge(risk: i.risk) }.width(78)
                    TableColumn("METHOD") { (i: CleanupItem) in
                        Text(app.settings.alwaysUseTrash && i.method.isPathBased ? "Move to Trash" : i.method.label)
                            .font(T.mono(10)).foregroundColor(T.dim).help(i.method.label)
                    }.width(min: 110, ideal: 150)
                    TableColumn("REASON") { (i: CleanupItem) in
                        Text(i.reason).font(T.mono(10)).foregroundColor(T.dim).help(i.reason + (i.note.isEmpty ? "" : "\n" + i.note))
                    }.width(min: 160, ideal: 280)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .scrollContentBackground(.hidden)
                .background(T.panel)
                .clipShape(RoundedRectangle(cornerRadius: T.radius))
                .overlay(RoundedRectangle(cornerRadius: T.radius).stroke(T.border, lineWidth: 1))
                if let run = app.lastRun {
                    Text("LAST RUN: \(run.items) operation(s) · available \(Fmt.bytes(run.before)) → \(Fmt.bytes(run.after)) · recovered \(Fmt.bytes(run.after - run.before))")
                        .font(T.mono(10, .semibold))
                }
            }
            .padding(.bottom, 6)
            .frame(minHeight: 220)

            OperationLog().padding(.top, 6).frame(minHeight: 160)
        }
        .sheet(isPresented: $confirming) { ConfirmSheet(isPresented: $confirming) }
    }
}

struct ConfirmSheet: View {
    @EnvironmentObject var app: AppState
    @Binding var isPresented: Bool
    @State private var stage = 1
    @State private var typed = ""

    private var risky: [CleanupItem] {
        app.queue.filter { $0.risk == .high || $0.personal || (app.settings.confirmMediumTwice && $0.risk == .medium) }
    }
    private var trashed: Int64 {
        app.queue.filter { app.settings.alwaysUseTrash ? $0.method.isPathBased : $0.method.usesTrash }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if stage == 1 {
                Text("Are you sure you want to delete these selected files?").font(T.mono(13, .bold))
                KV(k: "Items", v: "\(app.queue.count)")
                KV(k: "Files", v: Fmt.count(app.queue.reduce(0) { $0 + $1.fileCount }))
                KV(k: "Total", v: "\(Fmt.bytes(app.queueTotal))  (\(Fmt.exact(app.queueTotal)))")
                KV(k: "To Trash", v: "\(Fmt.bytes(trashed)) — freed only after emptying the Trash")
                KV(k: "Admin needed", v: app.queue.contains { if case .command(_, _, true) = $0.method { return true }; if case .snapshot = $0.method { return true }; return false } ? "Yes — macOS will ask for your password" : "No")
                Note(text: "Protected paths are re-checked before every operation. Files in use are skipped. Each result is verified and logged.")
                HStack {
                    Spacer()
                    SButton("CANCEL") { isPresented = false }.keyboardShortcut(.cancelAction)
                    SButton("CONFIRM DELETION", primary: true) {
                        if risky.isEmpty { run() } else { stage = 2 }
                    }
                }
            } else {
                Text("HIGH-RISK ITEMS — SECOND CONFIRMATION").font(T.mono(13, .bold))
                Note(text: "These items may contain data that cannot be recreated (backups, personal files, app data, Docker volumes):")
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(risky) { i in
                            HStack {
                                RiskBadge(risk: i.risk)
                                Text(Fmt.display(i.path)).font(T.mono(10)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(Fmt.bytes(i.size)).font(T.mono(10, .semibold))
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
                Text("Type DELETE to continue").font(T.mono(10)).foregroundColor(T.dim)
                TextField("", text: $typed).solidField()
                HStack {
                    Spacer()
                    SButton("CANCEL") { isPresented = false }.keyboardShortcut(.cancelAction)
                    SButton("CONFIRM DELETION", primary: true) { run() }.disabled(typed != "DELETE")
                }
            }
        }
        .padding(18)
        .frame(width: 560)
        .background(T.panel)
        .preferredColorScheme(.dark)
    }

    private func run() {
        isPresented = false
        app.executeQueue()
    }
}

struct OperationLog: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Panel(title: "OPERATION LOG", trailing: AnyView(Text("\(app.log.count) entries").font(T.mono(9)).foregroundColor(T.dim))) {
            Table(app.log) {
                TableColumn("TIME") { (e: LogEntry) in Text(Fmt.date(e.date)).font(T.mono(10)).foregroundColor(T.dim) }.width(110)
                TableColumn("RESULT") { (e: LogEntry) in
                    Text(e.result.rawValue).font(T.mono(10, .bold)).foregroundColor(e.result == .success ? T.text : T.dim)
                }.width(64)
                TableColumn("ITEM") { (e: LogEntry) in Text(e.name).font(T.mono(10)) }.width(min: 100, ideal: 140)
                TableColumn("ORIGINAL PATH") { (e: LogEntry) in
                    Text(Fmt.display(e.path)).font(T.mono(10)).foregroundColor(T.dim).truncationMode(.middle).help(e.path)
                }.width(min: 140, ideal: 260)
                TableColumn("SIZE") { (e: LogEntry) in Text(Fmt.bytes(e.size)).font(T.mono(10)) }.width(70)
                TableColumn("METHOD") { (e: LogEntry) in Text(e.method).font(T.mono(10)).foregroundColor(T.dim) }.width(min: 90, ideal: 120)
                TableColumn("DETAIL / ERROR") { (e: LogEntry) in
                    Text(e.detail).font(T.mono(10)).foregroundColor(T.dim).help(e.detail).textSelection(.enabled)
                }.width(min: 160, ideal: 320)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
        }
    }
}
