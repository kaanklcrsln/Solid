import Foundation

/// `SOLID --selftest`: exercises scanner, guard, rules, queue and deletion engine inside a temporary sandbox.
/// Only files created by the test are deleted (one 4-byte file goes through the real Trash).
@MainActor
enum SelfTest {
    private static var failures = 0

    static func check(_ ok: Bool, _ name: String, _ detail: String = "") {
        print((ok ? "PASS " : "FAIL ") + name + (detail.isEmpty ? "" : "  — " + detail))
        if !ok { failures += 1 }
    }

    static func run() -> Bool {
        let fm = FileManager.default
        let box = Guard.normalize(NSTemporaryDirectory() + "solid-selftest-\(getpid())")
        try? fm.removeItem(atPath: box)
        try! fm.createDirectory(atPath: box + "/a/b/c", withIntermediateDirectories: true)
        try! fm.createDirectory(atPath: box + "/outside", withIntermediateDirectories: true)
        try! fm.createDirectory(atPath: box + "/cache/sub", withIntermediateDirectories: true)

        let mb = Data(repeating: 7, count: 1_000_000)
        fm.createFile(atPath: box + "/a/one.bin", contents: mb)
        fm.createFile(atPath: box + "/a/b/two.bin", contents: mb + mb)
        fm.createFile(atPath: box + "/a/b/c/small.txt", contents: Data("hello".utf8))
        fm.createFile(atPath: box + "/outside/big.bin", contents: mb + mb + mb)
        try! fm.linkItem(atPath: box + "/a/one.bin", toPath: box + "/a/b/hardlink.bin")
        try! fm.createSymbolicLink(atPath: box + "/a/link-to-outside", withDestinationPath: box + "/outside")
        // 1 GB sparse file: logical size large, allocated ~0
        let fd = open(box + "/a/sparse.img", O_CREAT | O_WRONLY, 0o644)
        ftruncate(fd, 1_000_000_000)
        close(fd)
        fm.createFile(atPath: box + "/cache/x.tmp", contents: mb)
        fm.createFile(atPath: box + "/cache/sub/y.tmp", contents: mb)

        // Unreadable folder must not corrupt per-folder attribution
        try! fm.createDirectory(atPath: box + "/a/locked/inner", withIntermediateDirectories: true)
        chmod(box + "/a/locked", 0o000)
        defer { chmod(box + "/a/locked", 0o755) }

        // 1. Scanner vs du
        var opts = Scanner.Options()
        opts.depth = 5
        opts.minFileSize = 900_000
        let r = Scanner.scan(kind: .quick, roots: [box + "/a"], options: opts, control: ScanControl())
        let du = Int64(Shell.run("/usr/bin/du", ["-sk", box + "/a"]).out.split(separator: "\t").first.map(String.init) ?? "0")! * 1024
        let aSize = r.dirs[box + "/a"]?.size ?? -1
        check(aSize == du, "scanner total matches du -sk", "scanner \(aSize) / du \(du)")
        check(r.bytes == du, "scan byte total matches du", "\(r.bytes)")

        // 2. Hard link counted once, symlink not followed
        check(!r.largeFiles.contains { $0.path.hasSuffix("hardlink.bin") } || !r.largeFiles.contains { $0.path.hasSuffix("one.bin") },
              "hard link counted once")
        check(!r.largeFiles.contains { $0.path.contains("/outside/") }, "symlink not followed")
        check(aSize < 3_000_000 + 400_000 + 1_000_000, "outside dir not included in total", "\(aSize)")

        check(r.denied.contains { $0.hasSuffix("/a/locked") }, "unreadable folder reported as denied")
        check((r.dirs[box + "/a/locked"]?.size ?? 0) < 100_000 && (r.dirs[box + "/a"]?.size ?? 0) == aSize,
              "unreadable folder does not steal parent totals", "locked \(r.dirs[box + "/a/locked"]?.size ?? -1)")

        // 3. Sparse file
        let sparse = Scanner.measure(box + "/a/sparse.img")
        check(sparse.size < 1_000_000, "sparse file measured by allocation", "allocated \(sparse.size) of 1 GB logical")

        // 4. Large file detection + sorting
        check(r.largeFiles.count == 2, "large files ≥ 900 KB found", r.largeFiles.map(\.name).joined(separator: ","))
        check(r.largeFiles.first?.name == "two.bin", "large files sorted by size desc")
        let byDate = r.largeFiles.sorted(using: KeyPathComparator(\FileEntry.modified))
        check(byDate.count == r.largeFiles.count, "sort by date")

        // 5. Directory depth aggregation
        check(r.dirs[box + "/a/b"]?.size ?? 0 >= 2_000_000, "nested folder total", "\(r.dirs[box + "/a/b"]?.size ?? 0)")

        // 6. Guard
        let h = Guard.home
        let blocked = ["/", "/System/Library/CoreServices", h, h + "/Documents", h + "/Library", h + "/Library/Caches",
                       "/private/var/vm/sleepimage", "/var/vm/swapfile0", h + "/Library/Keychains/login.keychain-db",
                       "/Library/Updates/047-48781", h + "/Library/Mail/V10", "/Users", "/Applications",
                       "/System/Volumes/Data/private/var/db/foo", h + "/Library/Mobile Documents/x",
                       h + "/Pictures/Photos Library.photoslibrary/database", "/usr/bin/ls"]
        for p in blocked { check(Guard.blockReason(p) != nil, "guard blocks \(Fmt.display(p))", Guard.blockReason(p) ?? "ALLOWED") }
        let allowed = [h + "/Library/Caches/com.example.app", h + "/.npm/_cacache", box + "/a/one.bin",
                       h + "/Library/Developer/Xcode/DerivedData/Foo-abc"]
        for p in allowed { check(Guard.blockReason(p) == nil, "guard allows \(Fmt.display(p))", Guard.blockReason(p) ?? "") }
        check(Guard.blockReason(box + "/a/one.bin", userProtected: [box + "/a"]) != nil, "user-protected dir blocks children")
        check(Guard.blockReason(box, userProtected: [box + "/a"]) != nil, "user-protected blocks ancestors")
        check(Guard.isPersonal(h + "/Desktop/x.zip") && !Guard.isPersonal(h + "/Library/Caches/x"), "personal detection")

        // 7. Rules glob expansion (no symlink traversal)
        let ex = Rules.expand(box + "/a/*")
        check(ex.contains(box + "/a/b") && !ex.contains { $0.hasPrefix(box + "/a/link-to-outside/") }, "rule glob expansion")

        // 8. Queue logic
        let app = AppState()
        app.queue = []
        let parent = CleanupItem(id: box + "/cache", name: "cache", path: box + "/cache", size: 2_000_000, fileCount: 2, app: "t",
                                 category: .temp, risk: .low, method: .removeContents, reason: "t")
        var child = parent; child.id = box + "/cache/x.tmp"; child.path = child.id
        var prot = parent; prot.id = "/System/x"; prot.path = prot.id; prot.risk = .protected
        app.enqueue([child]); app.enqueue([parent]); app.enqueue([prot]); app.enqueue([parent])
        check(app.queue.count == 1 && app.queue[0].id == parent.id, "queue: parent replaces child, dedupe, protected rejected",
              app.queue.map(\.id).joined(separator: ","))
        check(app.queueTotal == 2_000_000, "queue total")
        app.dequeue([parent.id])
        check(app.queue.isEmpty, "queue removal")

        // 9. Deletion engine
        let ctx = DeletionEngine.Context()
        let sys = DeletionEngine.execute(CleanupItem(id: "/System/Library", name: "x", path: "/System/Library", size: 0, fileCount: 0,
                                                     app: "", category: .other, risk: .low, method: .remove, reason: ""), ctx: ctx)
        check(sys.result == .skipped && fm.fileExists(atPath: "/System/Library"), "engine refuses protected path", sys.detail)
        let home = DeletionEngine.execute(CleanupItem(id: h, name: "home", path: h, size: 0, fileCount: 0, app: "",
                                                      category: .other, risk: .low, method: .trash, reason: ""), ctx: ctx)
        check(home.result == .skipped, "engine refuses home folder", home.detail)

        let rm = DeletionEngine.execute(CleanupItem(id: box + "/a/b/two.bin", name: "two.bin", path: box + "/a/b/two.bin", size: 2_000_000,
                                                    fileCount: 1, app: "", category: .other, risk: .low, method: .remove, reason: ""), ctx: ctx)
        check(rm.result == .success && !fm.fileExists(atPath: box + "/a/b/two.bin"), "remove single file + verify", rm.detail)

        let cc = DeletionEngine.execute(parent, ctx: ctx)
        let left = (try? fm.contentsOfDirectory(atPath: box + "/cache")) ?? ["?"]
        check(cc.result == .success && left.isEmpty && fm.fileExists(atPath: box + "/cache"), "clear contents keeps folder", cc.detail)

        // In-use: hold a file open in this process
        let busy = box + "/a/busy.bin"
        fm.createFile(atPath: busy, contents: mb)
        let handle = FileHandle(forReadingAtPath: busy)
        let inUse = DeletionEngine.execute(CleanupItem(id: busy, name: "busy", path: busy, size: 0, fileCount: 1, app: "",
                                                       category: .other, risk: .low, method: .remove, reason: ""), ctx: ctx)
        check(inUse.result == .skipped && fm.fileExists(atPath: busy), "file in use is skipped", inUse.detail)
        try? handle?.close()

        let ghost = DeletionEngine.execute(CleanupItem(id: box + "/nope", name: "nope", path: box + "/nope", size: 0, fileCount: 0, app: "",
                                                       category: .other, risk: .low, method: .remove, reason: ""), ctx: ctx)
        check(ghost.result == .skipped, "missing item reported", ghost.detail)

        let trashFile = box + "/a/SOLID-selftest-trash.txt"
        fm.createFile(atPath: trashFile, contents: Data("test".utf8))
        let tr = DeletionEngine.execute(CleanupItem(id: trashFile, name: "trash", path: trashFile, size: 4, fileCount: 1, app: "",
                                                    category: .other, risk: .low, method: .trash, reason: ""), ctx: ctx)
        check(tr.result == .success && !fm.fileExists(atPath: trashFile), "move to Trash + verify", tr.detail)

        var forced = DeletionEngine.Context(); forced.forceTrash = true
        let p2 = box + "/a/b/c/small.txt"
        let ft = DeletionEngine.execute(CleanupItem(id: p2, name: "small", path: p2, size: 5, fileCount: 1, app: "", category: .other,
                                                    risk: .low, method: .remove, reason: ""), ctx: forced)
        check(ft.method == "Remove (rebuildable)" && ft.detail.contains("Trash"), "always-use-Trash setting converts remove", ft.detail)

        // 10. Misc
        check(AppState.parseSize("would free approximately 1.5GB of disk space") == 1_500_000_000, "parse brew size")
        check(Fmt.display("/System/Volumes/Data" + h + "/x") == "~/x", "firmlink path display")

        chmod(box + "/a/locked", 0o755)
        try? fm.removeItem(atPath: box)
        print(failures == 0 ? "\nALL TESTS PASSED" : "\n\(failures) FAILURE(S)")
        return failures == 0
    }

    /// `SOLID --scan PATH`: read-only scan printed to stdout.
    nonisolated static func headlessScan(_ root: String) {
        let r = Scanner.scan(kind: .quick, roots: [root], options: Scanner.Options(), control: ScanControl())
        print("ROOT \(root)\nTOTAL \(Fmt.bytes(r.bytes)) (\(r.bytes) bytes) · \(Fmt.count(r.files)) files · \(r.denied.count) denied · \(Fmt.duration(r.duration))")
        print("\nLARGE FILES")
        for f in r.largeFiles.prefix(25) { print(String(format: "%10@  %-9@  %@", Fmt.bytes(f.allocated), f.status.rawValue, Fmt.display(f.path))) }
        let items = Rules.resolve(lookup: { r.dirs[$0] }, control: ScanControl())
        print("\nCANDIDATES")
        for i in items.prefix(40) { print(String(format: "%10@  %-9@  %@", Fmt.bytes(i.size), i.risk.label, Fmt.display(i.path))) }
        let low = items.filter { $0.risk == .low }.reduce(0) { $0 + $1.size }
        let med = items.filter { $0.risk == .medium }.reduce(0) { $0 + $1.size }
        print("\nLOW \(Fmt.bytes(low))  MEDIUM \(Fmt.bytes(med))")
    }
}
