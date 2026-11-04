import Foundation

enum Risk: Int, Codable, Comparable, CaseIterable {
    case low, medium, high, protected

    static func < (a: Risk, b: Risk) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .low: return "LOW"
        case .medium: return "MEDIUM"
        case .high: return "HIGH"
        case .protected: return "PROTECTED"
        }
    }
}

enum Category: String, Codable, CaseIterable, Identifiable {
    case tmSnapshots, apfsSnapshots, appCaches, appSupport, iosBackups, updates, developer, swap, logs, temp, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tmSnapshots: return "Time Machine snapshots"
        case .apfsSnapshots: return "APFS snapshots"
        case .appCaches: return "Application caches"
        case .appSupport: return "Application support"
        case .iosBackups: return "iOS backups"
        case .updates: return "macOS update leftovers"
        case .developer: return "Developer data"
        case .swap: return "Swap and virtual memory"
        case .logs: return "Logs"
        case .temp: return "Temporary files"
        case .other: return "Other / unidentified"
        }
    }
}

enum DeleteMethod: Codable, Hashable {
    case trash              // move item to ~/.Trash
    case remove             // permanently remove this exact item
    case trashContents      // move each child to Trash, keep folder
    case removeContents     // permanently remove each child, keep folder
    case command(tool: String, args: [String], admin: Bool)
    case snapshot(date: String)

    var label: String {
        switch self {
        case .trash: return "Move to Trash"
        case .remove: return "Remove (rebuildable)"
        case .trashContents: return "Trash contents"
        case .removeContents: return "Clear contents"
        case .command(let tool, let args, let admin):
            return (admin ? "sudo " : "") + ([URL(fileURLWithPath: tool).lastPathComponent] + args).joined(separator: " ")
        case .snapshot: return "tmutil deletelocalsnapshots"
        }
    }

    var isPathBased: Bool {
        switch self {
        case .trash, .remove, .trashContents, .removeContents: return true
        default: return false
        }
    }

    var usesTrash: Bool {
        switch self {
        case .trash, .trashContents: return true
        default: return false
        }
    }
}

/// A removable unit: a file, a folder, its contents, or a supported command.
struct CleanupItem: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var path: String
    var size: Int64
    var fileCount: Int
    var app: String
    var category: Category
    var risk: Risk
    var method: DeleteMethod
    var reason: String
    var personal: Bool = false
    var note: String = ""
}

enum FileStatus: String, Codable {
    case eligible = "Eligible"
    case personal = "Personal"
    case protected = "Protected"
    case system = "App data"

    var selectable: Bool { self != .protected }
}

struct FileEntry: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let allocated: Int64
    let logical: Int64
    let modified: Date
    let type: String
    let status: FileStatus
    let restricted: Bool
}

struct DirStat: Codable {
    var size: Int64 = 0
    var count: Int = 0
}

enum ScanKind: String, Codable {
    case full = "FULL"
    case quick = "QUICK"
}

struct ScanRecord: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var kind: ScanKind
    var duration: TimeInterval
    var files: Int
    var bytes: Int64
    var denied: Int
    var cancelled: Bool
}

enum OpResult: String, Codable {
    case success = "OK"
    case partial = "PARTIAL"
    case failed = "FAILED"
    case skipped = "SKIPPED"
}

struct LogEntry: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var name: String
    var path: String
    var size: Int64
    var method: String
    var result: OpResult
    var detail: String
}

struct Snapshot: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let date: String     // tmutil date token, e.g. 2026-11-04-101500
    let isTimeMachine: Bool
}

struct IOSBackup: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let device: String
    let product: String
    let lastBackup: Date?
    let size: Int64
}
