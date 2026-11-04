import Foundation

/// Executes one approved CleanupItem at a time. Never called without a confirmed queue.
/// Each operation targets one exact path (or its direct children); there is no recursive wildcard deletion.
enum DeletionEngine {
    struct Context {
        var userProtected: [String] = []
        var forceTrash = false
    }

    static func execute(_ item: CleanupItem, ctx: Context) -> LogEntry {
        var log = LogEntry(date: Date(), name: item.name, path: item.path, size: item.size,
                           method: item.method.label, result: .failed, detail: "")
        if item.risk == .protected {
            log.result = .skipped
            log.detail = "Protected item; not removable."
            return log
        }

        var method = item.method
        if ctx.forceTrash {
            if case .remove = method { method = .trash }
            if case .removeContents = method { method = .trashContents }
        }

        switch method {
        case .trash, .remove:
            return single(item, method: method, ctx: ctx, log: log)
        case .trashContents, .removeContents:
            return contents(item, method: method, ctx: ctx, log: log)
        case .command(let tool, let args, let admin):
            let r = admin ? Shell.runAdmin(tool, args) : Shell.run(tool, args, timeout: 900)
            log.result = r.ok ? .success : .failed
            log.detail = r.ok ? lastLine(r.out) : "exit \(r.status): \(lastLine(r.err.isEmpty ? r.out : r.err))"
            return log
        case .snapshot(let date):
            let r = Shell.runAdmin("/usr/bin/tmutil", ["deletelocalsnapshots", date])
            let still = SystemInfo.timeMachineSnapshots().contains { $0.date == date }
            log.result = (r.ok && !still) ? .success : .failed
            log.detail = r.ok ? (still ? "Snapshot still listed after deletion." : "Snapshot removed.") : lastLine(r.err)
            return log
        }
    }

    private static func single(_ item: CleanupItem, method: DeleteMethod, ctx: Context, log: LogEntry) -> LogEntry {
        var log = log
        let path = Guard.normalize(item.path)
        if let why = Guard.blockReason(path, userProtected: ctx.userProtected) {
            log.result = .skipped
            log.detail = "Blocked by guard: \(why)"
            return log
        }
        var st = stat()
        guard lstat(path, &st) == 0 else {
            log.result = .skipped
            log.detail = "Not found (already removed?)"
            return log
        }
        if (st.st_mode & S_IFMT) == S_IFREG {
            let pids = SystemInfo.openBy(path)
            if !pids.isEmpty {
                log.result = .skipped
                log.detail = "In use by PID \(pids.joined(separator: ", ")). Quit the app and retry."
                return log
            }
        }
        do {
            try act(path, method: method)
        } catch {
            log.result = .failed
            log.detail = describe(error)
            return log
        }
        // Verify
        if lstat(path, &st) == 0 {
            log.result = .failed
            log.detail = "Item still exists after operation."
        } else {
            log.result = .success
            log.detail = method.usesTrash ? "Moved to Trash. Space is freed when the Trash is emptied." : "Removed."
        }
        return log
    }

    private static func contents(_ item: CleanupItem, method: DeleteMethod, ctx: Context, log: LogEntry) -> LogEntry {
        var log = log
        let dir = Guard.normalize(item.path)
        // The folder itself is kept, so it may be an essential root (e.g. ~/Library/Caches); each child is guarded.
        let fm = FileManager.default
        guard let kids = try? fm.contentsOfDirectory(atPath: dir) else {
            log.result = .failed
            log.detail = "Cannot read folder (permission denied?)"
            return log
        }
        let childMethod: DeleteMethod = method == .trashContents ? .trash : .remove
        var ok = 0, failed = 0, blocked = 0
        var firstError = ""
        for k in kids {
            let p = dir + "/" + k
            if let why = Guard.blockReason(p, userProtected: ctx.userProtected) {
                blocked += 1
                if firstError.isEmpty { firstError = "\(k): \(why)" }
                continue
            }
            do {
                try act(p, method: childMethod)
                ok += 1
            } catch {
                failed += 1
                if firstError.isEmpty { firstError = "\(k): \(describe(error))" }
            }
        }
        let remaining = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).count
        log.result = failed + blocked == 0 ? .success : (ok > 0 ? .partial : .failed)
        log.detail = "\(ok) removed, \(failed) failed, \(blocked) blocked, \(remaining) remaining" + (firstError.isEmpty ? "" : ". \(firstError)")
        return log
    }

    private static func act(_ path: String, method: DeleteMethod) throws {
        let url = URL(fileURLWithPath: path)
        switch method {
        case .trash:
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        case .remove:
            try FileManager.default.removeItem(at: url)
        default:
            break
        }
    }

    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        if let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            return "\(ns.localizedDescription) [\(u.domain) \(u.code): \(u.localizedDescription)]"
        }
        return "\(ns.localizedDescription) [\(ns.domain) \(ns.code)]"
    }

    private static func lastLine(_ s: String) -> String {
        s.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}
