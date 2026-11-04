import Foundation

struct SolidSettings: Codable, Equatable {
    var scanDepth = 6
    var minFileSize: Int64 = 100_000_000
    var excluded: [String] = []
    var protectedPaths: [String] = []
    var confirmMediumTwice = false     // high risk always needs the second confirmation
    var alwaysUseTrash = false
}

/// Local JSON persistence in ~/Library/Application Support/SOLID. Nothing leaves the machine.
enum Store {
    static let dir = Guard.home + "/Library/Application Support/SOLID"

    static func load<T: Decodable>(_ name: String, _ type: T.Type) -> T? {
        guard let d = FileManager.default.contents(atPath: dir + "/" + name) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: d)
    }

    static func save<T: Encodable>(_ name: String, _ value: T) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(value) {
            FileManager.default.createFile(atPath: dir + "/" + name, contents: d)
        }
    }
}
