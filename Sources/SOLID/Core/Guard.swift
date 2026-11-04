import Foundation

/// Decides whether a path may be touched by the deletion engine.
/// Checked when an item is classified AND again immediately before every operation.
enum Guard {
    static let home = NSHomeDirectory()

    /// Never touch anything at or below these.
    static var protectedTrees: [String] {
        [
            "/System", "/bin", "/sbin", "/usr/bin", "/usr/lib", "/usr/libexec", "/usr/sbin", "/usr/share",
            "/private/var/vm", "/private/var/db", "/private/var/protected", "/private/var/root",
            "/private/etc", "/Library/Apple", "/Library/Updates", "/Library/Keychains", "/Library/Security",
            "/Library/Preferences", "/Library/LaunchDaemons", "/Library/Extensions", "/Library/SystemExtensions",
            "/Library/Frameworks", "/Library/Filesystems", "/Library/Receipts",
            home + "/Library/Keychains", home + "/Library/Preferences", home + "/Library/Mail",
            home + "/Library/Messages", home + "/Library/Mobile Documents", home + "/Library/CloudStorage",
            home + "/Library/Accounts", home + "/Library/Cookies", home + "/Library/Calendars",
            home + "/Library/Safari", home + "/Library/Photos", home + "/Library/IdentityServices",
            home + "/Library/Group Containers/group.com.apple.notes",
            home + "/Library/Application Support/AddressBook", home + "/Library/Application Support/com.apple.TCC",
            home + "/Library/LaunchAgents",
        ]
    }

    /// These folders themselves must never be removed, though some of their contents may be.
    static var protectedRoots: [String] {
        [
            "/", "/Applications", "/Library", "/Users", "/Users/Shared", "/opt", "/opt/homebrew", "/usr", "/usr/local",
            "/private", "/private/var", "/private/tmp", "/private/var/folders", "/Volumes", "/Library/Caches",
            "/Library/Logs", "/Library/Application Support",
            home, home + "/Library", home + "/Library/Caches", home + "/Library/Logs",
            home + "/Library/Application Support", home + "/Library/Containers", home + "/Library/Group Containers",
            home + "/Library/Developer", home + "/Documents", home + "/Desktop", home + "/Downloads",
            home + "/Pictures", home + "/Movies", home + "/Music", home + "/Public", home + "/.Trash",
            home + "/.config", home + "/.ssh", home + "/.gnupg", home + "/.cache",
        ]
    }

    /// User content. Never auto-selected; deletion requires the high-risk confirmation.
    static var personalTrees: [String] {
        [home + "/Documents", home + "/Desktop", home + "/Downloads", home + "/Pictures", home + "/Movies",
         home + "/Music", home + "/Public", home + "/Library/Mobile Documents", "/Users/Shared"]
    }

    static func normalize(_ path: String) -> String {
        var p = (path as NSString).expandingTildeInPath
        p = (p as NSString).standardizingPath
        if p.hasPrefix("/System/Volumes/Data/") { p = String(p.dropFirst("/System/Volumes/Data".count)) }
        for (short, full) in [("/var", "/private/var"), ("/tmp", "/private/tmp"), ("/etc", "/private/etc")] {
            if p == short || p.hasPrefix(short + "/") { p = full + p.dropFirst(short.count) }
        }
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    static func isInside(_ path: String, _ tree: String) -> Bool {
        tree == "/" ? true : (path == tree || path.hasPrefix(tree + "/"))
    }

    /// Returns a reason string when the path must not be removed, nil when allowed.
    static func blockReason(_ raw: String, userProtected: [String] = []) -> String? {
        let p = normalize(raw)
        if p.isEmpty || p == "/" { return "root path" }
        // Require a minimum depth so no top-level location can ever be targeted.
        if p.split(separator: "/").count < 3 { return "path too shallow" }
        if p.hasPrefix("/System/Volumes/") { return "system volume" }
        for t in protectedTrees where isInside(p, t) { return "protected location (\(Fmt.display(t)))" }
        for t in userProtected.map(normalize) where !t.isEmpty && (isInside(p, t) || isInside(t, p)) {
            return "user-protected (\(Fmt.display(t)))"
        }
        for r in protectedRoots where p == r { return "essential folder" }
        // Removing an ancestor of a protected tree would remove the protected tree.
        for t in protectedTrees + personalTrees where isInside(t, p) && t != p { return "contains protected data" }
        if p.hasSuffix(".photoslibrary") || p.contains(".photoslibrary/") { return "Photos library" }
        if p.hasPrefix("/Applications/") && p.split(separator: "/").count <= 2 { return "installed application" }
        if hasRestrictedFlag(p) { return "SIP restricted" }
        return nil
    }

    static func isPersonal(_ raw: String) -> Bool {
        let p = normalize(raw)
        return personalTrees.contains { isInside(p, $0) }
    }

    /// SF_RESTRICTED (SIP) or immutable flags on the item itself.
    static func hasRestrictedFlag(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return false }
        let restricted: UInt32 = 0x0008_0000   // SF_RESTRICTED
        let immutable: UInt32 = 0x0000_0002 | 0x0002_0000   // UF_IMMUTABLE | SF_IMMUTABLE
        return st.st_flags & (restricted | immutable) != 0
    }
}
