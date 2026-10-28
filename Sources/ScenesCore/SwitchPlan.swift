import Foundation

public struct Placement: Equatable, Sendable {
    public var bundleID: String
    public var displayUUID: String

    public init(bundleID: String, displayUUID: String) {
        self.bundleID = bundleID
        self.displayUUID = displayUUID
    }
}

public struct SwitchPlan: Equatable, Sendable {
    public var show: [Placement]
    public var hide: [String]
}

public enum SwitchError: Error, Equatable {
    case unknownContext(String)
    case noDisplayAvailable
}

public enum Switcher {
    /// Pure decision logic. No AppKit. Apps that belong to no context are never hidden.
    /// - Parameters:
    ///   - availableDisplays: UUIDs of connected displays, in a stable preferred order.
    public static func plan(config: Config,
                            target contextID: String,
                            runningApps: Set<String>,
                            availableDisplays: [String]) throws -> SwitchPlan {
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
            for app in slot.apps where !shown.contains(app) {
                show.append(Placement(bundleID: app, displayUUID: display))
                shown.insert(app)
            }
        }

        let owned = Set(config.contexts.flatMap { $0.slots.flatMap { $0.apps } })
        let hide = runningApps.intersection(owned).subtracting(shown).sorted()
        return SwitchPlan(show: show, hide: hide)
    }
}
