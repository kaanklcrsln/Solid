import Foundation

struct ProcessOutput {
    var status: Int32
    var out: String
    var err: String
    var ok: Bool { status == 0 }
}

enum Shell {
    static let searchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Runs a tool directly (no shell interpolation). Arguments are passed verbatim.
    @discardableResult
    static func run(_ tool: String, _ args: [String], timeout: TimeInterval = 120) -> ProcessOutput {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPath
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        p.environment = env
        let outPipe = Pipe(), errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch { return ProcessOutput(status: -1, out: "", err: error.localizedDescription) }

        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        if group.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return ProcessOutput(status: -2, out: "", err: "timed out after \(Int(timeout))s")
        }
        p.waitUntilExit()
        return ProcessOutput(status: p.terminationStatus,
                             out: String(decoding: outData, as: UTF8.self),
                             err: String(decoding: errData, as: UTF8.self))
    }

    /// Runs one fixed command with administrator rights via the native macOS authorization prompt.
    static func runAdmin(_ tool: String, _ args: [String]) -> ProcessOutput {
        let cmd = ([tool] + args).map(quote).joined(separator: " ")
        let script = "do shell script \"\(cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        return run("/usr/bin/osascript", ["-e", script], timeout: 600)
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func find(_ names: [String]) -> String? {
        names.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var brew: String? { find(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) }
    static var docker: String? {
        find(["/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"])
    }
}

struct VolumeInfo {
    var name = "Macintosh HD"
    var total: Int64 = 0
    var available: Int64 = 0           // free right now
    var availableImportant: Int64 = 0  // free + purgeable, per macOS
    var purgeable: Int64 { max(0, availableImportant - available) }
    var used: Int64 { max(0, total - available) }
}

struct APFSVolume: Identifiable {
    var id: String { device }
    let device: String
    let name: String
    let roles: [String]
    let used: Int64
}

struct APFSInfo {
    var container = ""
    var ceiling: Int64 = 0
    var free: Int64 = 0
    var volumes: [APFSVolume] = []

    func used(role: String) -> Int64 { volumes.filter { $0.roles.contains(role) }.reduce(0) { $0 + $1.used } }
}

enum SystemInfo {
    static func volume() -> VolumeInfo {
        var v = VolumeInfo()
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                         .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedNameKey]
        if let r = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) {
            v.name = r.volumeLocalizedName ?? v.name
            v.total = Int64(r.volumeTotalCapacity ?? 0)
            v.available = Int64(r.volumeAvailableCapacity ?? 0)
            v.availableImportant = r.volumeAvailableCapacityForImportantUsage ?? v.available
        }
        return v
    }

    static func apfs() -> APFSInfo {
        var info = APFSInfo()
        let parent = plist(Shell.run("/usr/sbin/diskutil", ["info", "-plist", "/"]).out)?["ParentWholeDisk"] as? String
        guard let root = plist(Shell.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"]).out),
              let containers = root["Containers"] as? [[String: Any]] else { return info }
        let c = containers.first { ($0["ContainerReference"] as? String) == parent } ?? containers.last
        guard let c else { return info }
        info.container = c["ContainerReference"] as? String ?? ""
        info.ceiling = (c["CapacityCeiling"] as? NSNumber)?.int64Value ?? 0
        info.free = (c["CapacityFree"] as? NSNumber)?.int64Value ?? 0
        for v in c["Volumes"] as? [[String: Any]] ?? [] {
            info.volumes.append(APFSVolume(device: v["DeviceIdentifier"] as? String ?? "",
                                           name: v["Name"] as? String ?? "",
                                           roles: v["Roles"] as? [String] ?? [],
                                           used: (v["CapacityInUse"] as? NSNumber)?.int64Value ?? 0))
        }
        return info
    }

    static func timeMachineSnapshots() -> [Snapshot] {
        Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"]).out
            .split(separator: "\n").map(String.init)
            .filter { $0.hasPrefix("com.apple.") }
            .map { name in
                let date = name.components(separatedBy: ".").first { $0.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) != nil } ?? ""
                return Snapshot(name: name, date: date, isTimeMachine: name.contains("TimeMachine"))
            }
    }

    static func apfsSnapshots() -> [Snapshot] {
        guard let d = plist(Shell.run("/usr/sbin/diskutil", ["apfs", "listSnapshots", "/System/Volumes/Data", "-plist"]).out),
              let arr = d["Snapshots"] as? [[String: Any]] else { return [] }
        return arr.compactMap { s in
            guard let name = s["SnapshotName"] as? String else { return nil }
            return Snapshot(name: name, date: "", isTimeMachine: name.contains("TimeMachine"))
        }
    }

    static func timeMachineDestination() -> String {
        let r = Shell.run("/usr/bin/tmutil", ["destinationinfo"])
        let text = (r.out + r.err).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Unknown" : text
    }

    /// vm.swapusage via sysctl: (total, used)
    static func swap() -> (Int64, Int64) {
        var u = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &u, &size, nil, 0) == 0 else { return (0, 0) }
        return (Int64(u.xsu_total), Int64(u.xsu_used))
    }

    /// True when the process can read a TCC-protected location.
    static func hasFullDiskAccess() -> Bool {
        let probes = [Guard.home + "/Library/Mail", Guard.home + "/Library/Safari", Guard.home + "/Library/Messages",
                      "/Library/Application Support/com.apple.TCC"]
        for p in probes where FileManager.default.fileExists(atPath: p) {
            if (try? FileManager.default.contentsOfDirectory(atPath: p)) != nil { return true }
        }
        return false
    }

    static func installedBundleIDs() -> Set<String> {
        var ids = Set<String>()
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                    Guard.home + "/Applications"]
        for d in dirs {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? [] where name.hasSuffix(".app") {
                if let b = Bundle(path: d + "/" + name)?.bundleIdentifier { ids.insert(b.lowercased()) }
            }
        }
        return ids
    }

    static func installedAppNames() -> Set<String> {
        var names = Set<String>()
        for d in ["/Applications", "/Applications/Utilities", Guard.home + "/Applications"] {
            for n in (try? FileManager.default.contentsOfDirectory(atPath: d)) ?? [] where n.hasSuffix(".app") {
                names.insert(String(n.dropLast(4)).lowercased())
            }
        }
        return names
    }

    /// PIDs holding a file open (single regular files only; directories are not checked).
    static func openBy(_ path: String) -> [String] {
        let r = Shell.run("/usr/sbin/lsof", ["-t", "--", path], timeout: 15)
        return r.out.split(separator: "\n").map(String.init)
    }

    static func iosBackups() -> (backups: [IOSBackup], denied: Bool) {
        let dir = Guard.home + "/Library/Application Support/MobileSync/Backup"
        guard FileManager.default.fileExists(atPath: dir) else { return ([], false) }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return ([], true) }
        let list = items.filter { !$0.hasPrefix(".") }.map { id -> IOSBackup in
            let p = dir + "/" + id
            let info = NSDictionary(contentsOfFile: p + "/Info.plist")
            return IOSBackup(path: p,
                             device: info?["Device Name"] as? String ?? id,
                             product: info?["Product Type"] as? String ?? "",
                             lastBackup: info?["Last Backup Date"] as? Date,
                             size: Scanner.measure(p).size)
        }
        return (list.sorted { $0.size > $1.size }, false)
    }

    static func plist(_ s: String) -> [String: Any]? {
        guard let d = s.data(using: .utf8) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: d, format: nil)) as? [String: Any]
    }
}
