import CoreServices
import SwiftUI

struct LargeFilesView: View {
    @EnvironmentObject var app: AppState
    @State private var search = ""
    @State private var minSize: Int64 = 0
    @State private var type = "All types"
    @State private var status = "Any status"
    @State private var checked = Set<String>()
    @State private var sort = [KeyPathComparator(\FileEntry.allocated, order: .reverse)]
    @State private var focus: FileEntry.ID?

    private let thresholds: [(String, Int64)] = [("Any size", 0), ("> 100 MB", 100_000_000), ("> 500 MB", 500_000_000),
                                                 ("> 1 GB", 1_000_000_000), ("> 5 GB", 5_000_000_000), ("> 10 GB", 10_000_000_000)]

    private var filtered: [FileEntry] {
        app.largeFiles.filter { f in
            f.allocated >= minSize
                && (type == "All types" || f.type == type)
                && (status == "Any status" || f.status.rawValue == status)
                && (search.isEmpty || f.name.localizedCaseInsensitiveContains(search) || f.path.localizedCaseInsensitiveContains(search))
        }
        .sorted(using: sort)
    }

    private var types: [String] { ["All types"] + Set(app.largeFiles.map(\.type)).sorted() }
    private var checkedFiles: [FileEntry] { app.largeFiles.filter { checked.contains($0.id) } }

    var body: some View {
        if app.lastResult == nil {
            NeedsScan()
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Search filename or path", text: $search).solidField().frame(maxWidth: 260)
                    Picker("", selection: $minSize) { ForEach(thresholds, id: \.1) { Text($0.0).tag($0.1) } }.frame(width: 110)
                    Picker("", selection: $type) { ForEach(types, id: \.self) { Text($0).tag($0) } }.frame(width: 140)
                    Picker("", selection: $status) {
                        ForEach(["Any status", "Eligible", "App data", "Personal", "Protected"], id: \.self) { Text($0).tag($0) }
                    }.frame(width: 110)
                    Spacer()
                    Text("\(filtered.count) files · \(Fmt.bytes(filtered.reduce(0) { $0 + $1.allocated }))")
                        .font(T.mono(10)).foregroundColor(T.dim)
                }
                .font(T.mono(11))

                HStack(spacing: 8) {
                    table
                    if let id = focus, let f = app.largeFiles.first(where: { $0.id == id }) {
                        FileDetail(file: f).frame(width: 300)
                    }
                }

                HStack(spacing: 8) {
                    Text("SELECTED: \(checked.count) · \(Fmt.bytes(checkedFiles.reduce(0) { $0 + $1.allocated }))").font(T.mono(11, .semibold))
                    Spacer()
                    SButton("SELECT ALL ELIGIBLE") {
                        // Personal, protected and app-data files are never auto-selected.
                        checked = Set(filtered.filter { $0.status == .eligible && !app.inQueue($0.id) }.map(\.id))
                    }
                    SButton("CLEAR SELECTION") { checked.removeAll() }.disabled(checked.isEmpty)
                    SButton("ADD TO CLEANUP QUEUE") { enqueue() }.disabled(checked.isEmpty)
                    SButton("REVIEW & DELETE", primary: true) { enqueue(); app.section = .queue }.disabled(checked.isEmpty)
                }
                .padding(8)
                .background(T.sidebar)
                .clipShape(RoundedRectangle(cornerRadius: T.radius))
                Note(text: "Sizes are allocated disk space. Sparse files (e.g. VM disks) show a smaller logical size in Finder details. Personal files are never auto-selected and require the high-risk confirmation.")
            }
        }
    }

    private var table: some View {
        Table(filtered, selection: $focus, sortOrder: $sort) {
            TableColumn("") { (f: FileEntry) in
                Check(on: checked.contains(f.id), enabled: f.status.selectable && !app.inQueue(f.id)) {
                    if checked.contains(f.id) { checked.remove(f.id) } else { checked.insert(f.id) }
                }
            }.width(26)
            TableColumn("FILE NAME", value: \.name) { (f: FileEntry) in
                Text(f.name).font(T.mono(11)).foregroundColor(app.inQueue(f.id) ? T.dim : T.text).help(f.path)
            }.width(min: 140, ideal: 220)
            TableColumn("LOCATION", value: \.path) { (f: FileEntry) in
                Text(Fmt.display((f.path as NSString).deletingLastPathComponent)).font(T.mono(10)).foregroundColor(T.dim)
                    .truncationMode(.middle).help(f.path)
            }.width(min: 160, ideal: 320)
            TableColumn("SIZE", value: \.allocated) { (f: FileEntry) in
                Text(Fmt.bytes(f.allocated)).font(T.mono(11, .semibold)).help(Fmt.exact(f.allocated))
            }.width(76)
            TableColumn("TYPE", value: \.type) { (f: FileEntry) in Text(f.type).font(T.mono(10)).foregroundColor(T.dim) }.width(90)
            TableColumn("MODIFIED", value: \.modified) { (f: FileEntry) in
                Text(Fmt.date(f.modified)).font(T.mono(10)).foregroundColor(T.dim)
            }.width(120)
            TableColumn("STATUS", value: \.status.rawValue) { (f: FileEntry) in
                Text(app.inQueue(f.id) ? "Queued" : f.status.rawValue.uppercased())
                    .font(T.mono(9, .bold)).foregroundColor(f.status == .eligible ? T.text : T.dim)
            }.width(80)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
        .background(T.panel)
        .clipShape(RoundedRectangle(cornerRadius: T.radius))
        .overlay(RoundedRectangle(cornerRadius: T.radius).stroke(T.border, lineWidth: 1))
        .contextMenu(forSelectionType: FileEntry.ID.self) { ids in
            if let id = ids.first {
                Button("Reveal in Finder") { app.reveal(id) }
                Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(id, forType: .string) }
            }
        } primaryAction: { ids in if let id = ids.first { app.reveal(id) } }
    }

    private func enqueue() {
        app.enqueue(checkedFiles.map(app.cleanupItem(for:)))
        checked.removeAll()
    }
}

struct FileDetail: View {
    @EnvironmentObject var app: AppState
    let file: FileEntry
    @State private var meta: [(String, String)] = []

    var body: some View {
        Panel(title: "FILE DETAILS") {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    Text(file.name).font(T.mono(12, .semibold)).textSelection(.enabled)
                    Text(Fmt.display(file.path)).font(T.mono(10)).foregroundColor(T.dim).textSelection(.enabled)
                    Rectangle().fill(T.border).frame(height: 1)
                    KV(k: "Allocated", v: Fmt.exact(file.allocated))
                    KV(k: "Logical", v: Fmt.exact(file.logical))
                    if file.logical > file.allocated * 2 { KV(k: "Note", v: "Sparse file") }
                    KV(k: "Modified", v: Fmt.date(file.modified))
                    KV(k: "Status", v: file.status.rawValue)
                    KV(k: "App", v: Rules.appName(for: file.path))
                    if let why = Guard.blockReason(file.path) { KV(k: "Protected", v: why) }
                    ForEach(meta, id: \.0) { KV(k: $0.0, v: $0.1) }
                    SButton("REVEAL IN FINDER") { app.reveal(file.path) }.padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: file.path) { meta = Self.metadata(file.path) }
    }

    /// Spotlight metadata (same source as `mdls`) plus owner/flags from lstat.
    static func metadata(_ path: String) -> [(String, String)] {
        var out: [(String, String)] = []
        var st = stat()
        if lstat(path, &st) == 0 {
            let owner = getpwuid(st.st_uid).map { String(cString: $0.pointee.pw_name) } ?? "\(st.st_uid)"
            out.append(("Owner", owner))
            out.append(("Created", Fmt.date(Date(timeIntervalSince1970: TimeInterval(st.st_birthtimespec.tv_sec)))))
            out.append(("Accessed", Fmt.date(Date(timeIntervalSince1970: TimeInterval(st.st_atimespec.tv_sec)))))
            out.append(("Hard links", "\(st.st_nlink)"))
            if Guard.hasRestrictedFlag(path) { out.append(("Flags", "restricted / immutable")) }
        }
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return out }
        if let kind = MDItemCopyAttribute(item, kMDItemKind) as? String { out.append(("Kind", kind)) }
        if let used = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date { out.append(("Last opened", Fmt.date(used))) }
        if let from = MDItemCopyAttribute(item, kMDItemWhereFroms) as? [String], let f = from.first { out.append(("Downloaded from", f)) }
        if let creator = MDItemCopyAttribute(item, kMDItemCreator) as? String { out.append(("Creator", creator)) }
        return out
    }
}
