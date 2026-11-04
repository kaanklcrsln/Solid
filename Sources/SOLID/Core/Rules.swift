import Foundation

/// A known removable location. `pattern` may contain `~` and `*` (one path segment).
struct Rule {
    let pattern: String
    let category: Category
    let risk: Risk
    let method: DeleteMethod
    let app: String          // "" = derive from path
    let reason: String
    var note: String = ""
    var onlyFiles = false    // pattern must match regular files
}

enum Rules {
    static let all: [Rule] = [
        // Caches
        Rule(pattern: "~/Library/Caches/*", category: .appCaches, risk: .low, method: .remove, app: "",
             reason: "Application cache. Rebuilt automatically when the app runs.", note: "Quit the app first."),
        Rule(pattern: "~/Library/Containers/*/Data/Library/Caches", category: .appCaches, risk: .low, method: .removeContents,
             app: "", reason: "Sandboxed app cache. Rebuilt automatically."),
        Rule(pattern: "~/Library/Application Support/*/Cache", category: .appCaches, risk: .low, method: .remove, app: "",
             reason: "Chromium/Electron HTTP cache.", note: "Quit the app first."),
        Rule(pattern: "~/Library/Application Support/*/Code Cache", category: .appCaches, risk: .low, method: .remove, app: "",
             reason: "Compiled JavaScript cache (Electron).", note: "Quit the app first."),
        Rule(pattern: "~/Library/Application Support/*/GPUCache", category: .appCaches, risk: .low, method: .remove, app: "",
             reason: "GPU shader cache.", note: "Quit the app first."),
        Rule(pattern: "~/Library/Application Support/*/CachedData", category: .appCaches, risk: .low, method: .remove, app: "",
             reason: "Electron cached data.", note: "Quit the app first."),
        Rule(pattern: "~/Library/Application Support/Code/CachedExtensionVSIXs", category: .appCaches, risk: .low, method: .remove,
             app: "Visual Studio Code", reason: "Downloaded extension installers kept after install.", note: "Quit VS Code first."),
        Rule(pattern: "~/Library/Application Support/Google/Chrome/*/Service Worker/CacheStorage", category: .appCaches, risk: .low,
             method: .remove, app: "Google Chrome", reason: "Service worker caches.", note: "Quit Chrome first."),
        Rule(pattern: "/Library/Caches/*", category: .appCaches, risk: .medium,
             method: .remove, app: "", reason: "System-wide cache. Usually rebuilt.", note: "May require administrator rights."),

        // Logs
        Rule(pattern: "~/Library/Logs/*", category: .logs, risk: .low, method: .remove, app: "",
             reason: "Application logs and crash reports."),
        Rule(pattern: "~/Library/Application Support/Code/logs", category: .logs, risk: .low, method: .removeContents,
             app: "Visual Studio Code", reason: "VS Code session logs."),
        Rule(pattern: "/Library/Logs/*", category: .logs, risk: .medium, method: .remove, app: "",
             reason: "System-wide logs.", note: "May require administrator rights."),

        // Temp
        Rule(pattern: "~/Library/Application Support/*/vm_bundles/*/*.tmp", category: .temp, risk: .low, method: .trash, app: "",
             reason: "Interrupted VM image download. Not used by the app.", onlyFiles: true),
        Rule(pattern: "~/Library/Containers/com.Ababe.UnzipAnyFile/Data/Library/Application Support/*", category: .temp, risk: .low,
             method: .trash, app: "Unzip Any File", reason: "Files left over from archive extraction."),

        // Developer
        Rule(pattern: "~/Library/Developer/Xcode/DerivedData", category: .developer, risk: .low, method: .removeContents,
             app: "Xcode", reason: "Build intermediates. Rebuilt on next build."),
        Rule(pattern: "~/Library/Developer/Xcode/Archives", category: .developer, risk: .high, method: .trash, app: "Xcode",
             reason: "App archives with dSYMs. Needed to symbolicate crash reports of shipped builds."),
        Rule(pattern: "~/Library/Developer/Xcode/iOS DeviceSupport/*", category: .developer, risk: .medium, method: .remove,
             app: "Xcode", reason: "Debug symbols for a connected iOS version. Re-copied when the device is connected."),
        Rule(pattern: "~/Library/Developer/CoreSimulator/Caches", category: .developer, risk: .low, method: .removeContents,
             app: "Simulator", reason: "Simulator dyld caches."),
        Rule(pattern: "~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", category: .developer, risk: .high,
             method: .trash, app: "Docker Desktop",
             reason: "Docker disk image: all images, containers and volumes. Docker creates an empty one on next start.",
             note: "Quit Docker Desktop first. All Docker data is lost.", onlyFiles: true),
        Rule(pattern: "~/.npm/_cacache", category: .developer, risk: .low, method: .remove, app: "npm",
             reason: "npm package cache. Re-downloaded on demand."),
        Rule(pattern: "~/Library/pnpm/store", category: .developer, risk: .medium, method: .remove, app: "pnpm",
             reason: "pnpm content store. Existing node_modules keep working (hard links); installs re-download."),
        Rule(pattern: "~/.bun/install/cache", category: .developer, risk: .low, method: .remove, app: "Bun",
             reason: "Bun package cache."),
        Rule(pattern: "~/.cache/uv", category: .developer, risk: .low, method: .remove, app: "uv", reason: "uv package cache."),
        Rule(pattern: "~/.cache/pip", category: .developer, risk: .low, method: .remove, app: "pip", reason: "pip package cache."),
        Rule(pattern: "~/.cache/huggingface/hub", category: .developer, risk: .medium, method: .trash, app: "Hugging Face",
             reason: "Downloaded model weights. Re-downloaded when a model is next used."),
        Rule(pattern: "~/.lmstudio/models", category: .developer, risk: .high, method: .trash, app: "LM Studio",
             reason: "Local LLM model files you downloaded."),
        Rule(pattern: "~/.gradle/caches", category: .developer, risk: .medium, method: .remove, app: "Gradle",
             reason: "Gradle dependency/build cache."),
        Rule(pattern: "~/.m2/repository", category: .developer, risk: .medium, method: .remove, app: "Maven",
             reason: "Maven local repository. Re-downloaded on build."),
        Rule(pattern: "~/Library/Application Support/Claude/vm_bundles", category: .developer, risk: .medium, method: .trash,
             app: "Claude", reason: "Claude desktop VM image. Re-downloaded on next use.", note: "Quit Claude first."),

        // Backups
        Rule(pattern: "~/Library/Application Support/MobileSync/Backup/*", category: .iosBackups, risk: .high, method: .trash,
             app: "Finder (iPhone/iPad)", reason: "Local iOS/iPadOS device backup."),

        // Update leftovers
        Rule(pattern: "/Library/Updates", category: .updates, risk: .protected, method: .remove, app: "softwareupdate",
             reason: "Staged updates. SIP-restricted; managed by macOS."),
        Rule(pattern: "~/Library/Application Support/com.apple.mobileAssetDesktop", category: .updates, risk: .medium,
             method: .removeContents, app: "macOS", reason: "Downloaded device firmware / mobile assets."),

        // Swap
        Rule(pattern: "/private/var/vm", category: .swap, risk: .protected, method: .remove, app: "macOS",
             reason: "Swap files and sleepimage. Managed by the kernel; never delete."),
    ]

    /// Expand `*` segments against the real filesystem without following symlinks.
    static func expand(_ pattern: String) -> [String] {
        let full = (pattern as NSString).expandingTildeInPath
        let parts = full.split(separator: "/").map(String.init)
        var paths = ["/"]
        let fm = FileManager.default
        for part in parts {
            var next: [String] = []
            for base in paths {
                if part.contains("*") {
                    guard let kids = try? fm.contentsOfDirectory(atPath: base) else { continue }
                    let rx = "^" + NSRegularExpression.escapedPattern(for: part).replacingOccurrences(of: "\\*", with: ".*") + "$"
                    for k in kids where k != ".DS_Store" && k.range(of: rx, options: .regularExpression) != nil {
                        next.append((base as NSString).appendingPathComponent(k))
                    }
                } else {
                    let p = (base as NSString).appendingPathComponent(part)
                    var st = stat()
                    if lstat(p, &st) == 0 { next.append(p) }
                }
            }
            // never descend through symlinks
            paths = next.filter { p in
                var st = stat()
                return lstat(p, &st) == 0 && ((st.st_mode & S_IFMT) != S_IFLNK)
            }
        }
        return paths
    }

    static func appName(for path: String) -> String {
        let comps = Guard.normalize(path).split(separator: "/").map(String.init)
        for anchor in ["Caches", "Application Support", "Containers", "Group Containers", "Logs"] {
            if let i = comps.firstIndex(of: anchor), i + 1 < comps.count { return prettyApp(comps[i + 1]) }
        }
        return (path as NSString).lastPathComponent
    }

    static func prettyApp(_ id: String) -> String {
        let known = ["com.docker.docker": "Docker Desktop", "com.microsoft.VSCode": "Visual Studio Code", "Code": "Visual Studio Code",
                     "com.spotify.client": "Spotify", "Homebrew": "Homebrew", "Google": "Google Chrome",
                     "com.google.Chrome": "Google Chrome", "Firefox": "Firefox", "pip": "pip", "Yarn": "Yarn"]
        if let k = known[id] { return k }
        if id.contains(".") && id.split(separator: ".").count >= 3 {
            return String(id.split(separator: ".").last ?? Substring(id))
        }
        return id
    }

    /// Resolve every rule to concrete items. `lookup` returns a pre-measured size when the scan already has it.
    static func resolve(lookup: (String) -> DirStat?, control: ScanControl) -> [CleanupItem] {
        var out: [CleanupItem] = []
        var seen = Set<String>()
        for rule in all {
            for path in expand(rule.pattern) {
                if control.isCancelled { return out }
                let key = Guard.normalize(path)
                if seen.contains(key) { continue }
                var st = stat()
                guard lstat(key, &st) == 0 else { continue }
                let isFile = (st.st_mode & S_IFMT) == S_IFREG
                if rule.onlyFiles && !isFile { continue }
                seen.insert(key)
                let stat = isFile ? DirStat(size: Int64(st.st_blocks) * 512, count: 1) : (lookup(key) ?? Scanner.measure(key, control: control))
                if stat.size == 0 && rule.risk != .protected { continue }
                var risk = rule.risk
                var note = rule.note
                if risk != .protected, let why = Guard.blockReason(key) {
                    risk = .protected
                    note = "Blocked: \(why)"
                }
                out.append(CleanupItem(id: key, name: (key as NSString).lastPathComponent, path: key, size: stat.size,
                                       fileCount: stat.count, app: rule.app.isEmpty ? appName(for: key) : rule.app,
                                       category: rule.category, risk: risk, method: rule.method, reason: rule.reason,
                                       personal: Guard.isPersonal(key), note: note))
            }
        }
        // Drop items nested inside another selected item of the same list (avoids double counting).
        let paths = out.map(\.path)
        out.removeAll { item in paths.contains { $0 != item.path && Guard.isInside(item.path, $0) } }
        return out.sorted { $0.size > $1.size }
    }

    /// Top-level folders in Application Support / Containers / Group Containers, with orphan detection.
    static func appData(lookup: (String) -> DirStat?, control: ScanControl) -> [CleanupItem] {
        let ids = SystemInfo.installedBundleIDs()
        let names = SystemInfo.installedAppNames()
        var out: [CleanupItem] = []
        let roots = [Guard.home + "/Library/Application Support", Guard.home + "/Library/Containers",
                     Guard.home + "/Library/Group Containers"]
        for root in roots {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] where !name.hasPrefix(".") {
                if control.isCancelled { return out }
                let p = root + "/" + name
                var st = stat()
                guard lstat(p, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { continue }
                let size = lookup(p) ?? Scanner.measure(p, control: control)
                if size.size < 1_000_000 { continue }
                let lower = name.lowercased()
                let isApple = lower.hasPrefix("com.apple.") || lower.hasPrefix("group.com.apple.") || lower.contains(".com.apple.")
                let installed = ids.contains(lower) || ids.contains { lower.hasSuffix($0) || $0.hasSuffix("." + lower) }
                    || names.contains(lower) || names.contains { $0.replacingOccurrences(of: " ", with: "") == lower.replacingOccurrences(of: " ", with: "") }
                let state = isApple ? "Apple" : (installed ? "Installed" : "No matching app found")
                var risk: Risk = isApple ? .protected : (installed ? .high : .medium)
                var note = state
                if let why = Guard.blockReason(p) { risk = .protected; note = "Blocked: \(why)" }
                out.append(CleanupItem(id: p, name: name, path: p, size: size.size, fileCount: size.count,
                                       app: prettyApp(name), category: .appSupport, risk: risk, method: .trash,
                                       reason: installed ? "Data of an installed app. Deleting resets the app."
                                                         : "Possibly left behind by an uninstalled app.",
                                       note: note))
            }
        }
        return out.sorted { $0.size > $1.size }
    }
}
