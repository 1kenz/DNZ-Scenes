import Foundation
import ScenesCore

var total = 0
var failures = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    total += 1
    if condition() {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)")
    }
}

func throwsExactly<E: Error & Equatable>(_ expected: E, _ body: () throws -> Void) -> Bool {
    do { try body(); return false } catch let error as E { return error == expected } catch { return false }
}

let config = Config(
    displays: ["left": "UUID-L", "right": "UUID-R", "laptop": "UUID-M"],
    contexts: [
        Context(id: "work1", name: "Work 1", colorHex: "#3366FF", slots: [
            Slot(displayRole: "left", apps: ["com.apple.Terminal"]),
            Slot(displayRole: "laptop", apps: ["com.tinyspeck.slackmacgap"])
        ]),
        Context(id: "watch", name: "Watch", colorHex: "#CC3344", slots: [
            Slot(displayRole: "right", apps: ["com.apple.TV"])
        ])
    ])
let all = ["UUID-L", "UUID-R", "UUID-M"]

// --- Switcher ---
let p1 = try? Switcher.plan(config: config, target: "work1", runningApps: [], availableDisplays: all)
check("shows target apps on their displays", p1?.show == [
    Placement(bundleID: "com.apple.Terminal", displayUUID: "UUID-L"),
    Placement(bundleID: "com.tinyspeck.slackmacgap", displayUUID: "UUID-M")
])

let p2 = try? Switcher.plan(config: config, target: "work1",
                            runningApps: ["com.apple.TV", "com.apple.Terminal", "com.unrelated.App"],
                            availableDisplays: all)
check("hides only running apps owned by other contexts", p2?.hide == ["com.apple.TV"])

let p3 = try? Switcher.plan(config: config, target: "work1", runningApps: [], availableDisplays: ["UUID-M"])
check("missing display falls back to first available",
      p3 != nil && p3!.show.allSatisfy { $0.displayUUID == "UUID-M" })

check("unknown context throws", throwsExactly(SwitchError.unknownContext("nope")) {
    _ = try Switcher.plan(config: config, target: "nope", runningApps: [], availableDisplays: all)
})
check("no display throws", throwsExactly(SwitchError.noDisplayAvailable) {
    _ = try Switcher.plan(config: config, target: "work1", runningApps: [], availableDisplays: [])
})

// --- Config codec ---
let roundTrip = (try? ConfigCodec.decode(ConfigCodec.encode(config)))
check("config round trip", roundTrip == config)

var bad = config
bad.schemaVersion = 99
check("unsupported schema is rejected", throwsExactly(ConfigError.unsupportedSchema(99)) {
    _ = try ConfigCodec.decode(ConfigCodec.encode(bad))
})

// --- Hotkeys ---
let spec = HotkeySpec.parse("Ctrl+Opt+3")
check("hotkey parses modifiers and digit",
      spec?.control == true && spec?.option == true && spec?.command == false && spec?.key == "3")
check("hotkey rejects invalid input",
      HotkeySpec.parse("3") == nil && HotkeySpec.parse("ctrl+a") == nil
      && HotkeySpec.parse("ctrl+foo+1") == nil && HotkeySpec.parse("") == nil)

// --- Starter / profile editing ---
let starter = Config.starter(displays: ["left": "A"])
check("starter has eight profiles 001...008 with unique valid hotkeys",
      starter.contexts.map(\.id) == ["001", "002", "003", "004", "005", "006", "007", "008"]
      && Set(starter.contexts.compactMap(\.hotkey)).count == 8
      && starter.contexts.allSatisfy { HotkeySpec.parse($0.hotkey ?? "") != nil })
check("starter wallpapers are plain file names",
      starter.contexts.allSatisfy { ($0.wallpaper ?? "").contains("/") == false && $0.wallpaper != nil })

let updated = starter.settingSlots(contextID: "003", appsByRole: ["right": ["b.app", "a.app"], "left": ["c.app"]])
check("settingSlots sorts and replaces only the target context",
      updated.contexts[2].slots == [Slot(displayRole: "left", apps: ["c.app"]),
                                    Slot(displayRole: "right", apps: ["a.app", "b.app"])]
      && updated.contexts[0] == starter.contexts[0]
      && starter.settingSlots(contextID: "nope", appsByRole: ["x": ["y"]]) == starter)

let added = starter.addingApp("x.app", role: "left", toContext: "001")
check("addingApp creates the slot", added.contexts[0].slots == [Slot(displayRole: "left", apps: ["x.app"])])
let moved = added.addingApp("x.app", role: "right", toContext: "001")
check("addingApp moves an app between screens without duplicating",
      moved.contexts[0].slots == [Slot(displayRole: "right", apps: ["x.app"])])
let removed = moved.removingApp("x.app", fromContext: "001")
check("removingApp drops the app and empty slots", removed.contexts[0].slots.isEmpty)
check("add/remove on unknown profile is a no-op",
      starter.addingApp("x", role: "left", toContext: "nope") == starter
      && starter.removingApp("x", fromContext: "nope") == starter)


// --- Editing: name, color, wallpaper ---
let renamed = starter.renamingContext("001", to: "Mission Control")
check("renamingContext changes only the name",
      renamed.contexts[0].name == "Mission Control" && renamed.contexts[0].id == "001"
      && renamed.contexts[1] == starter.contexts[1])
check("blank name falls back to the id in displayName",
      starter.renamingContext("001", to: "  ").contexts[0].displayName == "001")
check("settingColor stores the hex value", starter.settingColor("002", hex: "#112233").contexts[1].colorHex == "#112233")
check("settingWallpaper accepts plain names, rejects paths, nil clears",
      starter.settingWallpaper("001", name: "x.png").contexts[0].wallpaper == "x.png"
      && starter.settingWallpaper("001", name: "../x.png") == starter
      && starter.settingWallpaper("001", name: ".hidden.png") == starter
      && starter.settingWallpaper("001", name: nil).contexts[0].wallpaper == nil)

// --- Add / remove profiles ---
let base = Config.starter(displays: [:])
if let added = base.addingContext(name: "  Reading ") {
    check("add profile: appended with fresh id 009, trimmed name, free hotkey",
          added.config.contexts.count == 9 && added.id == "009"
          && added.config.contexts.last?.name == "Reading"
          && added.config.contexts.last?.hotkey == "ctrl+opt+9")
    let removed = added.config.removingContext("003")
    let reAdded = removed.addingContext(name: "")
    check("remove profile drops it; next add reuses the free id and hotkey key",
          removed.contexts.count == 8 && !removed.contexts.contains(where: { $0.id == "003" })
          && reAdded?.id == "003" && reAdded?.config.contexts.last?.name == "New Profile"
          && reAdded?.config.contexts.last?.hotkey == "ctrl+opt+3")
} else {
    check("add profile returns a result", false)
}
var single = base
single.contexts = [base.contexts[0]]
check("last profile cannot be removed; unknown id ignored",
      single.removingContext("001") == single && base.removingContext("nope") == base)
var full = base
while let next = full.addingContext(name: "x") { full = next.config }
check("profile count is capped", full.contexts.count == Config.maxContexts)

print("\n\(total - failures)/\(total) checks passed")
exit(failures == 0 ? 0 : 1)
