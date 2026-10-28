import XCTest
@testable import ScenesCore

final class ConfigAndHotkeyTests: XCTestCase {
    func testHotkeyParsesModifiersAndDigit() {
        let spec = HotkeySpec.parse("Ctrl+Opt+3")
        XCTAssertEqual(spec?.control, true)
        XCTAssertEqual(spec?.option, true)
        XCTAssertEqual(spec?.command, false)
        XCTAssertEqual(spec?.key, "3")
    }

    func testHotkeyRejectsInvalid() {
        XCTAssertNil(HotkeySpec.parse("3"))            // no modifier
        XCTAssertNil(HotkeySpec.parse("ctrl+a"))       // letters not supported yet
        XCTAssertNil(HotkeySpec.parse("ctrl+foo+1"))   // unknown modifier
        XCTAssertNil(HotkeySpec.parse(""))
    }

    func testStarterHasFourContextsWithHotkeys() {
        let c = Config.starter(displays: ["left": "A"])
        XCTAssertEqual(c.contexts.map(\.id), ["work1", "work2", "learn", "watch"])
        XCTAssertTrue(c.contexts.allSatisfy { HotkeySpec.parse($0.hotkey ?? "") != nil })
    }

    func testSettingSlotsReplacesOnlyTargetContext() {
        let c = Config.starter(displays: [:])
        let updated = c.settingSlots(contextID: "learn", appsByRole: ["right": ["b.app", "a.app"], "left": ["c.app"]])
        XCTAssertEqual(updated.contexts[2].slots, [
            Slot(displayRole: "left", apps: ["c.app"]),
            Slot(displayRole: "right", apps: ["a.app", "b.app"])
        ])
        XCTAssertEqual(updated.contexts[0], c.contexts[0])
        XCTAssertEqual(c.settingSlots(contextID: "nope", appsByRole: ["x": ["y"]]), c)
    }
}
