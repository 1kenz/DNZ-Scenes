import Foundation

/// Parsed form of "ctrl+opt+1". Requires at least one modifier and a single digit key.
public struct HotkeySpec: Equatable, Sendable {
    public var control = false
    public var option = false
    public var command = false
    public var shift = false
    public var key: Character

    public init(key: Character) {
        self.key = key
    }

    public static func parse(_ text: String) -> HotkeySpec? {
        let parts = text.lowercased().split(separator: "+").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 2, let last = parts.last, last.count == 1,
              let key = last.first, key.isASCII, key.isNumber else { return nil }
        var spec = HotkeySpec(key: key)
        for modifier in parts.dropLast() {
            switch modifier {
            case "ctrl", "control": spec.control = true
            case "opt", "option", "alt": spec.option = true
            case "cmd", "command": spec.command = true
            case "shift": spec.shift = true
            default: return nil
            }
        }
        return spec
    }
}
