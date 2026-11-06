import XCTest
@testable import MergeKit

final class SchedulerTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeScheduler() -> Scheduler {
        Scheduler(now: { self.clock })
    }

    private func link(
        _ name: String,
        weight: Double? = nil,
        v4: Bool = true,
        v6: Bool = true,
        enabled: Bool = true
    ) -> LinkCandidate {
        LinkCandidate(
            id: LinkID(name),
            kind: .other,
            supportsV4: v4,
            supportsV6: v6,
            isEnabled: enabled,
            manualWeightMbps: weight
        )
    }

    func testNoLinksAcquiresNothing() {
        XCTAssertNil(makeScheduler().acquire(.v4))
    }

    func testSingleLinkIsAlwaysChosen() {
        let scheduler = makeScheduler()
        scheduler.setCandidates([link("en0")])
        for _ in 0..<10 {
            XCTAssertEqual(scheduler.acquire(.v4), LinkID("en0"))
        }
        XCTAssertEqual(scheduler.activeFlowCount(), 10)
    }

    func testDisabledLinkIsSkipped() {
        let scheduler = makeScheduler()
        scheduler.setCandidates([link("en0", enabled: false), link("feth0")])
        for _ in 0..<5 {
            XCTAssertEqual(scheduler.acquire(.v4), LinkID("feth0"))
        }
    }

    func testFamilyFiltering() {
        let scheduler = makeScheduler()
        scheduler.setCandidates([link("en0", v6: false), link("feth0", v6: true)])
        for _ in 0..<5 {
            XCTAssertEqual(scheduler.acquire(.v6), LinkID("feth0"))
        }
    }

    func testNoUsableFamilyReturnsNil() {
        let scheduler = makeScheduler()
        scheduler.setCandidates([link("en0", v6: false)])
        XCTAssertNil(scheduler.acquire(.v6))
    }

    func testWeightedDistributionRoughlyProportional() {
        let scheduler = makeScheduler()
        scheduler.setCandidates([link("en0", weight: 300), link("feth0", weight: 100)])
        var counts: [String: Int] = [:]
        for _ in 0..<400 {
            if let id = scheduler.acquire(.v4) { counts[id.name, default: 0] += 1 }
        }
        let fast = Double(counts["en0"] ?? 0)
        XCTAssertGreaterThan(fast, 250, "fast link should take about three quarters")
        XCTAssertLessThan(fast, 340)
    }

    func testReleaseReturnsFlowToThePool() {
        let scheduler = makeScheduler()
        scheduler.setCandidates([link("en0")])
        let id = scheduler.acquire(.v4)
        XCTAssertEqual(scheduler.activeFlowCount(), 1)
        scheduler.release(id!, family: .v4)
        XCTAssertEqual(scheduler.activeFlowCount(), 0)
    }

    func testFailuresTakeALinkDownThenRecoverAfterCooldown() {
        let scheduler = makeScheduler()
        scheduler.setCandidates([link("en0", weight: 100), link("feth0", weight: 100)])

        for _ in 0..<3 {
            scheduler.probeResult(LinkID("en0"), ok: false)
        }
        XCTAssertEqual(scheduler.tier(LinkID("en0")), .down)
        for _ in 0..<20 {
            XCTAssertEqual(scheduler.acquire(.v4), LinkID("feth0"), "down link must not be chosen")
        }

        clock = clock.addingTimeInterval(16)
        XCTAssertEqual(scheduler.tier(LinkID("en0")), .down, "tier only changes on use or probe")
        XCTAssertNotNil(scheduler.acquire(.v4))
        XCTAssertEqual(scheduler.tier(LinkID("en0")), .degraded, "expired cooldown revives as degraded")

        scheduler.probeResult(LinkID("en0"), ok: true)
        XCTAssertEqual(scheduler.tier(LinkID("en0")), .up)
    }

    func testSingleFailureDegradesWithoutTakingDown() {
        let scheduler = makeScheduler()
        scheduler.setCandidates([link("en0")])
        scheduler.probeResult(LinkID("en0"), ok: false)
        XCTAssertEqual(scheduler.tier(LinkID("en0")), .degraded)
        XCTAssertNotNil(scheduler.acquire(.v4))
    }

    func testSuccessRestoresWeight() {
        let scheduler = makeScheduler()
        scheduler.setCandidates([link("en0", weight: 100)])
        scheduler.probeResult(LinkID("en0"), ok: false)
        let degraded = scheduler.snapshot().first!.weightMbps
        scheduler.probeResult(LinkID("en0"), ok: true)
        let healthy = scheduler.snapshot().first!.weightMbps
        XCTAssertLessThan(degraded, healthy)
        XCTAssertEqual(healthy, 100, accuracy: 0.001)
    }

    func testMeasuredThroughputUpdatesWeight() {
        let scheduler = makeScheduler()
        scheduler.setCandidates([link("en0")])
        let id = scheduler.acquire(.v4)!
        // 10 MB in 1 second is 80 Mbit/s.
        scheduler.release(id, family: .v4, bytesIn: 10_000_000, elapsed: 1.0)
        let weight = scheduler.snapshot().first!.weightMbps
        XCTAssertEqual(weight, 80, accuracy: 0.5)
    }

    func testCountersPersistAcrossCandidateRefreshes() {
        let scheduler = makeScheduler()
        scheduler.setCandidates([link("en0")])
        let id = scheduler.acquire(.v4)!
        scheduler.release(id, family: .v4, bytesIn: 1_000, bytesOut: 500)
        scheduler.setCandidates([link("en0")])
        let snapshot = scheduler.snapshot().first!
        XCTAssertEqual(snapshot.bytesIn, 1_000)
        XCTAssertEqual(snapshot.bytesOut, 500)
    }

    func testRemovedLinkDropsItsState() {
        let scheduler = makeScheduler()
        scheduler.setCandidates([link("en0"), link("feth0")])
        _ = scheduler.acquire(.v4)
        scheduler.setCandidates([link("en0")])
        XCTAssertEqual(scheduler.snapshot().map(\.id.name), ["en0"])
    }

    func testMaxFlowsPerLink() {
        var config = Scheduler.Config()
        config.maxFlowsPerLink = 2
        let scheduler = Scheduler(config: config, now: { self.clock })
        scheduler.setCandidates([link("en0")])
        XCTAssertNotNil(scheduler.acquire(.v4))
        XCTAssertNotNil(scheduler.acquire(.v4))
        XCTAssertNil(scheduler.acquire(.v4))
    }

    func testConcurrentAcquireReleaseLeavesNoLeakedFlows() {
        let scheduler = makeScheduler()
        scheduler.setCandidates([link("en0", weight: 100), link("feth0", weight: 50)])
        let group = DispatchGroup()
        for _ in 0..<8 {
            DispatchQueue.global().async(group: group) {
                for _ in 0..<500 {
                    if let id = scheduler.acquire(.v4) {
                        scheduler.release(id, family: .v4, bytesIn: 100, elapsed: 0.01)
                    }
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success)
        XCTAssertEqual(scheduler.activeFlowCount(), 0)
    }
}
