import SwiftUI

/// Checkbox table of cleanup candidates with a selection footer. Protected rows cannot be checked.
struct ItemTable: View {
    @EnvironmentObject var app: AppState
    let items: [CleanupItem]
    var autoSelectMaxRisk: Risk = .low
    @State private var checked = Set<String>()
    @State private var sort = [KeyPathComparator(\CleanupItem.size, order: .reverse)]
    @State private var focus: CleanupItem.ID?

    private var sorted: [CleanupItem] { items.sorted(using: sort) }
    private var checkedItems: [CleanupItem] { items.filter { checked.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            Table(sorted, selection: $focus, sortOrder: $sort) {
                TableColumn("") { (i: CleanupItem) in
                    Check(on: checked.contains(i.id), enabled: i.risk != .protected && !app.inQueue(i.id)) { toggle(i.id) }
                }.width(26)
                TableColumn("NAME", value: \.name) { (i: CleanupItem) in
                    Text(i.name).font(T.mono(11)).foregroundColor(app.inQueue(i.id) ? T.dim : T.text).help(i.path)
                }.width(min: 120, ideal: 180)
                TableColumn("LOCATION", value: \.path) { (i: CleanupItem) in
                    Text(Fmt.display((i.path as NSString).deletingLastPathComponent)).font(T.mono(10)).foregroundColor(T.dim)
                        .truncationMode(.middle).help(i.path)
                }.width(min: 140, ideal: 260)
                TableColumn("SIZE", value: \.size) { (i: CleanupItem) in
                    Text(Fmt.bytes(i.size)).font(T.mono(11, .semibold)).help(Fmt.exact(i.size))
                }.width(76)
                TableColumn("FILES", value: \.fileCount) { (i: CleanupItem) in
                    Text(i.fileCount > 0 ? Fmt.count(i.fileCount) : "—").font(T.mono(10)).foregroundColor(T.dim)
                }.width(64)
                TableColumn("APP", value: \.app) { (i: CleanupItem) in
                    Text(i.app).font(T.mono(10)).foregroundColor(T.dim)
                }.width(min: 80, ideal: 120)
                TableColumn("RISK", value: \.risk) { (i: CleanupItem) in RiskBadge(risk: i.risk) }.width(78)
                TableColumn("REASON") { (i: CleanupItem) in
                    Text(i.note.isEmpty ? i.reason : "\(i.reason) \(i.note)").font(T.mono(10)).foregroundColor(T.dim)
                        .help(i.note.isEmpty ? i.reason : "\(i.reason)\n\(i.note)")
                }.width(min: 160, ideal: 320)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            .background(T.panel)
            .contextMenu(forSelectionType: CleanupItem.ID.self) { ids in
                if let id = ids.first, let i = items.first(where: { $0.id == id }) {
                    Button("Reveal in Finder") { app.reveal(i.path) }
                    Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(i.path, forType: .string) }
                    if i.risk != .protected { Button("Add to Cleanup Queue") { app.enqueue([i]) } }
                }
            } primaryAction: { ids in
                if let id = ids.first, let i = items.first(where: { $0.id == id }) { app.reveal(i.path) }
            }

            HStack(spacing: 8) {
                Text("SELECTED: \(checkedItems.count) · \(Fmt.bytes(checkedItems.reduce(0) { $0 + $1.size }))")
                    .font(T.mono(11, .semibold))
                Text("of \(items.count) · \(Fmt.bytes(items.reduce(0) { $0 + $1.size }))").font(T.mono(10)).foregroundColor(T.dim)
                Spacer()
                SButton(autoSelectMaxRisk == .low ? "SELECT LOW RISK" : "SELECT ALL ELIGIBLE") {
                    checked = Set(items.filter { $0.risk <= autoSelectMaxRisk && !$0.personal && !app.inQueue($0.id) }.map(\.id))
                }
                SButton("CLEAR SELECTION") { checked.removeAll() }.disabled(checked.isEmpty)
                SButton("ADD TO CLEANUP QUEUE") { app.enqueue(checkedItems); checked.removeAll() }.disabled(checked.isEmpty)
                SButton("REVIEW & DELETE", primary: true) {
                    app.enqueue(checkedItems); checked.removeAll(); app.section = .queue
                }.disabled(checked.isEmpty)
            }
            .padding(8)
            .background(T.sidebar)
        }
        .clipShape(RoundedRectangle(cornerRadius: T.radius))
        .overlay(RoundedRectangle(cornerRadius: T.radius).stroke(T.border, lineWidth: 1))
    }

    private func toggle(_ id: String) {
        if checked.contains(id) { checked.remove(id) } else { checked.insert(id) }
    }
}

/// Shown in place of a table until a scan has produced data.
struct NeedsScan: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        Panel(title: "NO DATA") {
            VStack(alignment: .leading, spacing: 8) {
                Note(text: app.resolving ? "Classifying scan results…" : "Run a scan to populate this view. Scanning is read-only.")
                if !app.resolving {
                    HStack {
                        SButton("FULL SYSTEM SCAN", primary: true) { app.startScan(.full) }
                        SButton("QUICK SCAN") { app.startScan(.quick) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
