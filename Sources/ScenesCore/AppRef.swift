import Foundation

/// A profile entry is either a plain bundle ID ("com.apple.Terminal") or a bundle ID plus a
/// browser profile name ("com.google.Chrome::Ken (Work)"). Plain IDs keep working unchanged.
public struct AppRef: Equatable, Sendable {
    public static let separator = "::"
    public static let chromeBundleID = "com.google.Chrome"

    public var bundleID: String
    public var profile: String?

    public init(bundleID: String, profile: String? = nil) {
        self.bundleID = bundleID
        self.profile = profile
    }

    public init(_ entry: String) {
        if let range = entry.range(of: AppRef.separator) {
            let name = String(entry[range.upperBound...])
            self.bundleID = String(entry[..<range.lowerBound])
            self.profile = name.isEmpty ? nil : name
        } else {
            self.bundleID = entry
            self.profile = nil
        }
    }

    public var entry: String {
        guard let profile else { return bundleID }
        return bundleID + AppRef.separator + profile
    }
}
