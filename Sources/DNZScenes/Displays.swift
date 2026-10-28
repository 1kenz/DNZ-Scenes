import AppKit

struct DisplayInfo {
    let uuid: String
    let screen: NSScreen
    let isBuiltin: Bool
}

enum Displays {
    static func current() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = CGDirectDisplayID(number.uint32Value)
            guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            let text = CFUUIDCreateString(nil, uuid) as String
            return DisplayInfo(uuid: text, screen: screen, isBuiltin: CGDisplayIsBuiltin(id) != 0)
        }
    }

    /// role -> UUID. Built-in = "laptop"; external screens left-to-right = "left", "right".
    static func roles(_ displays: [DisplayInfo]) -> [String: String] {
        var result: [String: String] = [:]
        if let laptop = displays.first(where: { $0.isBuiltin }) { result["laptop"] = laptop.uuid }
        let external = displays.filter { !$0.isBuiltin }.sorted { $0.screen.frame.minX < $1.screen.frame.minX }
        if external.count > 0 { result["left"] = external[0].uuid }
        if external.count > 1 { result["right"] = external[1].uuid }
        return result
    }
}
