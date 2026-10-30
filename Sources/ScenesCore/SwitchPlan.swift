import Foundation

public struct Placement: Equatable, Sendable {
    public var bundleID: String
    public var displayUUID: String
    /// Browser profile this placement is for; nil means every window of the app.
    public var profile: String?

    public init(bundleID: String, displayUUID: String, profile: String? = nil) {
        self.bundleID = bundleID
        self.displayUUID = displayUUID
        self.profile = profile
    }
}

public struct SwitchPlan: Equatable, Sendable {
    public var show: [Placement]
    public var hide: [String]
    /// Every profile name configured anywhere, per app. Windows of these profiles that the target
    /// does not want get minimized; windows of unknown profiles are left alone.
    public var knownProfiles: [String: [String]] = [:]
}

public enum SwitchError: Error, Equatable {
    case unknownContext(String)
    case noDisplayAvailable
}

public enum Switcher {
    /// Pure decision logic. No AppKit.
    /// - Parameters:
    ///   - runningApps: bundle IDs of running apps that may be hidden (the caller passes regular GUI apps only).
    ///   - availableDisplays: UUIDs of connected displays, in a stable preferred order.
    ///   - protectedApps: never hidden (e.g. this app itself).
    /// With `config.hideOthers`, every running app outside the target profile is hidden, except
    /// `config.keepVisible` and `protectedApps`. A profile with no apps never hides anything this way,
    /// so an empty profile cannot blank the screen. Otherwise only apps owned by other profiles are hidden.
    public static func plan(config: Config,
                            target contextID: String,
                            runningApps: Set<String>,
                            availableDisplays: [String],
                            protectedApps: Set<String> = []) throws -> SwitchPlan {
        guard let target = config.contexts.first(where: { $0.id == contextID }) else {
            throw SwitchError.unknownContext(contextID)
        }
        guard let fallback = availableDisplays.first else {
            throw SwitchError.noDisplayAvailable
        }

        var show: [Placement] = []
        var shown = Set<String>()
        for slot in target.slots {
            let wanted = config.displays[slot.displayRole]
            let display = wanted.flatMap { availableDisplays.contains($0) ? $0 : nil } ?? fallback
            for entry in slot.apps where !shown.contains(entry) {
                let ref = AppRef(entry)
                show.append(Placement(bundleID: ref.bundleID, displayUUID: display, profile: ref.profile))
                shown.insert(entry)
            }
        }

        let shownBases = Set(show.map(\.bundleID))
        var known: [String: Set<String>] = [:]
        for ref in config.contexts.flatMap({ $0.slots.flatMap(\.apps) }).map({ AppRef($0) }) {
            if let profile = ref.profile { known[ref.bundleID, default: []].insert(profile) }
        }
        let knownProfiles = known.mapValues { $0.sorted() }

        let hide: [String]
        if config.hideOthers && !shown.isEmpty {
            let keep = shownBases.union(config.keepVisible).union(protectedApps)
            hide = runningApps.subtracting(keep).sorted()
        } else {
            let owned = Set(config.contexts.flatMap { $0.slots.flatMap { $0.apps } }.map { AppRef($0).bundleID })
            hide = runningApps.intersection(owned).subtracting(shownBases).subtracting(protectedApps).sorted()
        }
        return SwitchPlan(show: show, hide: hide, knownProfiles: knownProfiles)
    }
}
