import Foundation

/// Thread-safe pause / cancel switch shared between UI and scan thread.
final class ScanControl {
    private let cond = NSCondition()
    private var paused = false
    private var cancelled = false

    var isPaused: Bool { cond.lock(); defer { cond.unlock() }; return paused }
    var isCancelled: Bool { cond.lock(); defer { cond.unlock() }; return cancelled }

    func pause() { cond.lock(); paused = true; cond.unlock() }
    func resume() { cond.lock(); paused = false; cond.broadcast(); cond.unlock() }
    func cancel() { cond.lock(); cancelled = true; paused = false; cond.broadcast(); cond.unlock() }

    /// Blocks while paused. Returns false when cancelled.
    func checkpoint() -> Bool {
        cond.lock(); defer { cond.unlock() }
        while paused && !cancelled { cond.wait() }
        return !cancelled
    }
}

struct ScanProgress {
    var currentPath = ""
    var files = 0
    var bytes: Int64 = 0
    var denied = 0
    var elapsed: TimeInterval = 0
}

struct ScanResult {
    var kind: ScanKind
    var date: Date
    var roots: [String]
    var dirs: [String: DirStat] = [:]     // normalized path -> allocated size
    var largeFiles: [FileEntry] = []
    var denied: [String] = []
    var files = 0
    var bytes: Int64 = 0
    var duration: TimeInterval = 0
    var cancelled = false
}

/// Read-only filesystem walker built on fts(3).
/// FTS_PHYSICAL: symlinks are reported, never followed. FTS_XDEV: never crosses into another volume.
/// Sizes are allocated blocks (st_blocks * 512), so sparse files and APFS holes are counted correctly.
/// Hard links (st_nlink > 1) are counted once per (dev, inode).
enum Scanner {
    struct Options {
        var depth = 6
        var minFileSize: Int64 = 100_000_000
        var excluded: [String] = []
        var collectLarge = true
    }

    static func scan(kind: ScanKind, roots: [String], options: Options, control: ScanControl,
                     progress: ((ScanProgress) -> Void)? = nil) -> ScanResult {
        let start = Date()
        var result = ScanResult(kind: kind, date: start, roots: roots)
        var prog = ScanProgress()
        var lastReport = Date.distantPast
        var seenInodes = Set<InodeKey>()
        let excluded = options.excluded.map(Guard.normalize).filter { !$0.isEmpty }

        for root in roots {
            if control.isCancelled { break }
            walk(root: root, options: options, excluded: excluded, control: control, result: &result,
                 seen: &seenInodes) { path, files, bytes, denied in
                prog.files = files
                prog.bytes = bytes
                prog.denied = denied
                let now = Date()
                if now.timeIntervalSince(lastReport) > 0.12 {
                    lastReport = now
                    prog.currentPath = path
                    prog.elapsed = now.timeIntervalSince(start)
                    progress?(prog)
                }
            }
        }
        result.cancelled = control.isCancelled
        result.duration = Date().timeIntervalSince(start)
        result.largeFiles.sort { $0.allocated > $1.allocated }
        return result
    }

    /// Allocated size of one path (file or tree). Used for targets outside the scanned roots.
    static func measure(_ path: String, control: ScanControl = ScanControl()) -> DirStat {
        var r = ScanResult(kind: .quick, date: Date(), roots: [path])
        var seen = Set<InodeKey>()
        var opts = Options()
        opts.depth = 0
        opts.collectLarge = false
        walk(root: path, options: opts, excluded: [], control: control, result: &r, seen: &seen, tick: nil)
        return DirStat(size: r.bytes, count: r.files)
    }

    struct InodeKey: Hashable { let dev: Int32; let ino: UInt64 }

    private struct Frame { let path: String; let level: Int; var stat = DirStat() }

    private static func walk(root: String, options: Options, excluded: [String], control: ScanControl,
                             result: inout ScanResult, seen: inout Set<InodeKey>, tick: ((String, Int, Int64, Int) -> Void)?) {
        var st = stat()
        guard lstat(root, &st) == 0 else { result.denied.append(root); return }
        if (st.st_mode & S_IFMT) == S_IFREG {
            result.files += 1
            result.bytes += Int64(st.st_blocks) * 512
            return
        }

        let cRoot = strdup(root)
        defer { free(cRoot) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cRoot, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else {
            result.denied.append(root)
            return
        }
        defer { fts_close(fts) }

        var stack: [Frame] = []
        var n = 0

        func popFrame() {
            guard let f = stack.popLast() else { return }
            let key = Guard.normalize(f.path)
            if f.level <= options.depth { result.dirs[key] = f.stat }
            if !stack.isEmpty {
                stack[stack.count - 1].stat.size += f.stat.size
                stack[stack.count - 1].stat.count += f.stat.count
            }
        }

        while let ent = fts_read(fts) {
            n += 1
            if n & 255 == 0 && !control.checkpoint() { break }
            let e = ent.pointee
            let path = String(cString: e.fts_path)
            let level = Int(e.fts_level)

            switch Int32(e.fts_info) {
            case FTS_D:
                if !excluded.isEmpty && excluded.contains(where: { Guard.isInside(Guard.normalize(path), $0) }) {
                    fts_set(fts, ent, FTS_SKIP)
                    continue
                }
                stack.append(Frame(path: path, level: level))
                tick?(path, result.files, result.bytes, result.denied.count)
            case FTS_DP:
                // fts also emits FTS_DP for unreadable dirs that were reported as FTS_DNR (never pushed).
                if stack.last?.path == path { popFrame() }
            case FTS_DNR, FTS_ERR, FTS_NS:
                result.denied.append(path)
                // A directory that fails to open comes back as FTS_D, then FTS_DNR in place of FTS_DP.
                if stack.last?.path == path { popFrame(); continue }
                if Int32(e.fts_info) == FTS_DNR, let s = e.fts_statp {
                    // Directory itself is still allocated even if unreadable.
                    addToTop(&stack, Int64(s.pointee.st_blocks) * 512, files: 0)
                }
            case FTS_DC:
                continue
            default:
                // Regular files, symlinks (FTS_SL, not followed), and others: count the inode itself.
                guard let s = e.fts_statp?.pointee else { continue }
                if s.st_nlink > 1 && (s.st_mode & S_IFMT) == S_IFREG {
                    let k = InodeKey(dev: s.st_dev, ino: s.st_ino)
                    if seen.contains(k) { continue }
                    seen.insert(k)
                }
                let alloc = Int64(s.st_blocks) * 512
                result.files += 1
                result.bytes += alloc
                addToTop(&stack, alloc, files: 1)
                if options.collectLarge && (s.st_mode & S_IFMT) == S_IFREG && alloc >= options.minFileSize {
                    result.largeFiles.append(makeEntry(path: path, st: s, alloc: alloc))
                }
            }
        }
        while !stack.isEmpty { popFrame() }   // cancelled mid-walk: keep partial totals
    }

    private static func addToTop(_ stack: inout [Frame], _ bytes: Int64, files: Int) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].stat.size += bytes
        stack[stack.count - 1].stat.count += files
    }

    static func makeEntry(path raw: String, st s: stat, alloc: Int64) -> FileEntry {
        let path = Guard.normalize(raw)
        let name = (path as NSString).lastPathComponent
        let status: FileStatus
        if Guard.blockReason(path) != nil { status = .protected }
        else if Guard.isPersonal(path) { status = .personal }
        else if path.hasPrefix(Guard.home + "/Library/") || path.hasPrefix("/Library/") { status = .system }
        else { status = .eligible }
        let mtime = Date(timeIntervalSince1970: TimeInterval(s.st_mtimespec.tv_sec))
        return FileEntry(path: path, name: name, allocated: alloc, logical: Int64(s.st_size), modified: mtime,
                         type: Fmt.fileType(name), status: status, restricted: s.st_flags & 0x0008_0000 != 0)
    }
}
