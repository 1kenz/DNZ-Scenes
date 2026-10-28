import Foundation
import ScenesCore

enum ConfigStoreError: Error {
    case symlinkRefused
}

enum ConfigStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DNZ-Scenes", isDirectory: true)
    }
    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    /// Loads config; on first run writes a starter config. A corrupt file throws and is never overwritten.
    /// A config file that is a symbolic link is refused.
    static func load(starterDisplays: [String: String]) throws -> Config {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let values = try fileURL.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw ConfigStoreError.symlinkRefused }
            return try ConfigCodec.decode(Data(contentsOf: fileURL))
        }
        let config = Config.starter(displays: starterDisplays)
        try save(config)
        return config
    }

    static func save(_ config: Config) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try ConfigCodec.encode(config).write(to: fileURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
