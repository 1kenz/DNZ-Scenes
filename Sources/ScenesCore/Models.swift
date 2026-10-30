import Foundation

/// One screen's content within a context. `displayRole` is a key into `Config.displays`.
public struct Slot: Codable, Equatable, Sendable {
    public var displayRole: String
    public var apps: [String]  // bundle identifiers

    public init(displayRole: String, apps: [String]) {
        self.displayRole = displayRole
        self.apps = apps
    }
}

public struct Context: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var colorHex: String
    public var slots: [Slot]
    /// e.g. "ctrl+opt+1". Optional.
    public var hotkey: String?
    /// File name (not a path) of the wallpaper applied to all screens when this context is activated.
    public var wallpaper: String?

    public init(id: String, name: String, colorHex: String, slots: [Slot],
                hotkey: String? = nil, wallpaper: String? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.slots = slots
        self.hotkey = hotkey
        self.wallpaper = wallpaper
    }
}

public struct Config: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// role ("left", "right", "laptop") -> display UUID
    public var displays: [String: String]
    public var contexts: [Context]
    /// When true, switching hides every regular running app that is not in the target profile
    /// (except `keepVisible` and the app itself). When false, only apps owned by other profiles are hidden.
    public var hideOthers: Bool
    /// Bundle identifiers that are never hidden by a switch.
    public var keepVisible: [String]

    public static let defaultKeepVisible = ["com.apple.finder"]

    public init(schemaVersion: Int = Config.currentSchemaVersion,
                displays: [String: String],
                contexts: [Context],
                hideOthers: Bool = true,
                keepVisible: [String] = Config.defaultKeepVisible) {
        self.schemaVersion = schemaVersion
        self.displays = displays
        self.contexts = contexts
        self.hideOthers = hideOthers
        self.keepVisible = keepVisible
    }

    // Older config files have no hideOthers/keepVisible keys; they get the defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        displays = try c.decode([String: String].self, forKey: .displays)
        contexts = try c.decode([Context].self, forKey: .contexts)
        hideOthers = try c.decodeIfPresent(Bool.self, forKey: .hideOthers) ?? true
        keepVisible = try c.decodeIfPresent([String].self, forKey: .keepVisible) ?? Config.defaultKeepVisible
    }

    /// First-run config: eight empty profiles 001...008 with ctrl+opt+1...8 and numbered wallpapers.
    public static func starter(displays: [String: String]) -> Config {
        let profiles: [(String, String, String, String)] = [
            ("001", "DNZ", "#3B8BEB", "001.png"),
            ("002", "Deutsch", "#FFCC00", "002.png"),
            ("003", "Clarusway", "#FF88C0", "003.png"),
            ("004", "Januam", "#3DDC97", "004.png"),
            ("005", "DNZ Security", "#A78BFA", "005.png"),
            ("006", "Cyber", "#22E07A", "006.png"),
            ("007", "Personal", "#FF9A3C", "007.png"),
            ("008", "Idle", "#8A8A8A", "008.jpg")
        ]
        let contexts = profiles.enumerated().map { index, p in
            Context(id: p.0, name: p.1, colorHex: p.2, slots: [],
                    hotkey: "ctrl+opt+\(index + 1)", wallpaper: p.3)
        }
        return Config(displays: displays, contexts: contexts)
    }

    /// Returns a copy where the context's slots are replaced. Unknown id -> unchanged copy.
    public func settingSlots(contextID: String, appsByRole: [String: [String]]) -> Config {
        var copy = self
        guard let i = copy.contexts.firstIndex(where: { $0.id == contextID }) else { return self }
        copy.contexts[i].slots = appsByRole.keys.sorted().map {
            Slot(displayRole: $0, apps: (appsByRole[$0] ?? []).sorted())
        }
        return copy
    }

    /// Adds an app to a context on a display role. If the app is already in that context it is moved.
    public func addingApp(_ bundleID: String, role: String, toContext contextID: String) -> Config {
        var copy = self
        guard let i = copy.contexts.firstIndex(where: { $0.id == contextID }) else { return self }
        var slots = copy.contexts[i].slots
        for s in slots.indices { slots[s].apps.removeAll { $0 == bundleID } }
        if let s = slots.firstIndex(where: { $0.displayRole == role }) {
            slots[s].apps.append(bundleID)
        } else {
            slots.append(Slot(displayRole: role, apps: [bundleID]))
        }
        copy.contexts[i].slots = slots.filter { !$0.apps.isEmpty }
        return copy
    }

    /// Removes an app from a context. Unknown id -> unchanged copy.
    public func removingApp(_ bundleID: String, fromContext contextID: String) -> Config {
        var copy = self
        guard let i = copy.contexts.firstIndex(where: { $0.id == contextID }) else { return self }
        var slots = copy.contexts[i].slots
        for s in slots.indices { slots[s].apps.removeAll { $0 == bundleID } }
        copy.contexts[i].slots = slots.filter { !$0.apps.isEmpty }
        return copy
    }
}

public enum ConfigError: Error, Equatable {
    case unsupportedSchema(Int)
}

public enum ConfigCodec {
    public static func decode(_ data: Data) throws -> Config {
        let config = try JSONDecoder().decode(Config.self, from: data)
        guard config.schemaVersion == Config.currentSchemaVersion else {
            throw ConfigError.unsupportedSchema(config.schemaVersion)
        }
        return config
    }

    public static func encode(_ config: Config) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(config)
    }
}

extension Context {
    /// Name shown in menus; falls back to the id when the name is blank.
    public var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? id : name
    }
}

extension Config {
    public func renamingContext(_ contextID: String, to name: String) -> Config {
        var copy = self
        guard let i = copy.contexts.firstIndex(where: { $0.id == contextID }) else { return self }
        copy.contexts[i].name = name
        return copy
    }

    public func settingColor(_ contextID: String, hex: String) -> Config {
        var copy = self
        guard let i = copy.contexts.firstIndex(where: { $0.id == contextID }) else { return self }
        copy.contexts[i].colorHex = hex
        return copy
    }

    /// `name` must be a plain file name (no path components) or nil to clear.
    public func settingWallpaper(_ contextID: String, name: String?) -> Config {
        var copy = self
        guard let i = copy.contexts.firstIndex(where: { $0.id == contextID }) else { return self }
        if let name {
            guard !name.isEmpty, !name.contains("/"), !name.hasPrefix(".") else { return self }
        }
        copy.contexts[i].wallpaper = name
        return copy
    }
}

extension Config {
    public static let maxContexts = 20

    private static let newProfileColors = ["#3B8BEB", "#FFCC00", "#FF88C0", "#3DDC97",
                                           "#A78BFA", "#22E07A", "#FF9A3C", "#8A8A8A"]

    /// Appends an empty profile with a fresh id, a palette colour and the first free ctrl+opt+digit hotkey.
    /// Returns nil when the profile limit is reached.
    public func addingContext(name: String) -> (config: Config, id: String)? {
        guard contexts.count < Config.maxContexts else { return nil }
        let existing = Set(contexts.map(\.id))
        var number = 1
        while existing.contains(String(format: "%03d", number)) { number += 1 }
        let id = String(format: "%03d", number)

        let usedKeys = Set(contexts.compactMap { $0.hotkey.flatMap(HotkeySpec.parse) }
            .filter { $0.control && $0.option && !$0.command && !$0.shift }.map(\.key))
        let freeKey = "123456789".first { !usedKeys.contains($0) }

        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = Context(id: id, name: trimmed.isEmpty ? "New Profile" : trimmed,
                              colorHex: Config.newProfileColors[contexts.count % Config.newProfileColors.count],
                              slots: [], hotkey: freeKey.map { "ctrl+opt+\($0)" }, wallpaper: nil)
        var copy = self
        copy.contexts.append(context)
        return (copy, id)
    }

    /// Removes a profile. The last remaining profile cannot be removed; unknown id -> unchanged copy.
    public func removingContext(_ contextID: String) -> Config {
        guard contexts.count > 1, contexts.contains(where: { $0.id == contextID }) else { return self }
        var copy = self
        copy.contexts.removeAll { $0.id == contextID }
        return copy
    }
}
