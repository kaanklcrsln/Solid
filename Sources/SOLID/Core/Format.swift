import Foundation

enum Fmt {
    static func bytes(_ b: Int64) -> String {
        if b <= 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(b)
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        return i == 0 ? "\(b) B" : String(format: v >= 100 ? "%.0f %@" : "%.2f %@", v, units[i])
    }

    static func exact(_ b: Int64) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return (f.string(from: NSNumber(value: b)) ?? "\(b)") + " bytes"
    }

    static func count(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func date(_ d: Date?) -> String { d.map { df.string(from: $0) } ?? "—" }

    /// Strip the Data-volume firmlink prefix so paths read like Finder paths.
    static func display(_ path: String) -> String {
        var p = path
        if p.hasPrefix("/System/Volumes/Data/") { p = String(p.dropFirst("/System/Volumes/Data".count)) }
        let home = NSHomeDirectory()
        if p == home { return "~" }
        if p.hasPrefix(home + "/") { return "~" + p.dropFirst(home.count) }
        return p
    }

    static func fileType(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "dmg", "iso", "pkg", "img", "raw", "qcow2", "vmdk", "vdi", "sparseimage", "sparsebundle": return "Disk image"
        case "zip", "gz", "tgz", "xz", "zst", "7z", "rar", "tar", "bz2": return "Archive"
        case "mov", "mp4", "m4v", "mkv", "avi", "webm": return "Video"
        case "jpg", "jpeg", "png", "heic", "tif", "tiff", "raw2", "psd", "dng": return "Image"
        case "mp3", "wav", "aiff", "flac", "m4a", "aac": return "Audio"
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "txt", "md": return "Document"
        case "gguf", "safetensors", "bin", "pt", "pth", "onnx", "ckpt", "mlmodel": return "ML model"
        case "sqlite", "db", "sqlite3", "gpkg", "parquet", "duckdb", "realm", "ldb": return "Database"
        case "app", "dylib", "so", "a", "o", "framework": return "Binary"
        case "log": return "Log"
        case "tmp", "temp", "partial", "download", "crdownload": return "Temporary"
        case "": return "No extension"
        default: return ext.uppercased()
        }
    }
}
