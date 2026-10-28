import XCTest
@testable import ScenesCore

final class SwitchPlanTests: XCTestCase {
    private let config = Config(
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
    private let all = ["UUID-L", "UUID-R", "UUID-M"]

    func testShowsTargetAppsOnTheirDisplays() throws {
        let plan = try Switcher.plan(config: config, target: "work1", runningApps: [], availableDisplays: all)
        XCTAssertEqual(plan.show, [
            Placement(bundleID: "com.apple.Terminal", displayUUID: "UUID-L"),
            Placement(bundleID: "com.tinyspeck.slackmacgap", displayUUID: "UUID-M")
        ])
    }

    func testHidesRunningAppsOfOtherContextsOnly() throws {
        let running: Set<String> = ["com.apple.TV", "com.apple.Terminal", "com.unrelated.App"]
        let plan = try Switcher.plan(config: config, target: "work1", runningApps: running, availableDisplays: all)
        XCTAssertEqual(plan.hide, ["com.apple.TV"])
    }

    func testMissingDisplayFallsBackToFirstAvailable() throws {
        let plan = try Switcher.plan(config: config, target: "work1", runningApps: [], availableDisplays: ["UUID-M"])
        XCTAssertTrue(plan.show.allSatisfy { $0.displayUUID == "UUID-M" })
    }

    func testUnknownContextThrows() {
        XCTAssertThrowsError(try Switcher.plan(config: config, target: "nope", runningApps: [], availableDisplays: all)) {
            XCTAssertEqual($0 as? SwitchError, .unknownContext("nope"))
        }
    }

    func testNoDisplayThrows() {
        XCTAssertThrowsError(try Switcher.plan(config: config, target: "work1", runningApps: [], availableDisplays: [])) {
            XCTAssertEqual($0 as? SwitchError, .noDisplayAvailable)
        }
    }

    func testConfigRoundTripAndSchemaGuard() throws {
        let data = try ConfigCodec.encode(config)
        XCTAssertEqual(try ConfigCodec.decode(data), config)

        var bad = config
        bad.schemaVersion = 99
        let badData = try ConfigCodec.encode(bad)
        XCTAssertThrowsError(try ConfigCodec.decode(badData)) {
            XCTAssertEqual($0 as? ConfigError, .unsupportedSchema(99))
        }
    }
}
