import XCTest
@testable import SnowCore

final class FallLeavesTests: XCTestCase {
    private func simulation(_ season: Season = .fall, flakes: Int = 600) -> SnowSimulation {
        let simulation = SnowSimulation(size: SIMD2(1000, 800), budget: SimulationBudget(flakes: flakes), seed: 42)
        simulation.season = season
        return simulation
    }

    /// One window top at y = 300 carrying an even pile.
    private func pile(on simulation: SnowSimulation, height: Float = 10) {
        simulation.updateSurfaces([Surface(id: 1, x: 100, y: 300, width: 400)])
        for i in simulation.drifts[0].heights.indices { simulation.drifts[0].heights[i] = height }
        simulation.rebuildMesh()
    }

    private func area(_ simulation: SnowSimulation) -> Float {
        simulation.drifts.reduce(0) { $0 + $1.heights.reduce(0, +) * $1.spacing }
    }

    private func run(_ simulation: SnowSimulation, seconds: Float, cursor: (Float) -> SIMD2<Float>? = { _ in nil }) {
        let dt: Float = 1 / 30
        for frame in 0..<Int((seconds / dt).rounded()) {
            simulation.step(dt: dt, cursor: cursor(Float(frame) * dt))
        }
    }

    func testLeafInstanceMatchesTheShaderLayout() {
        XCTAssertEqual(MemoryLayout<LeafInstance>.stride, 32)
    }

    func testCalendarPicksFallBetweenEquinoxAndSolstice() {
        XCTAssertEqual(Season.current(month: 9, day: 21), .winter)
        XCTAssertEqual(Season.current(month: 9, day: 22), .fall)
        XCTAssertEqual(Season.current(month: 11, day: 19), .fall)
        XCTAssertEqual(Season.current(month: 12, day: 20), .fall)
        XCTAssertEqual(Season.current(month: 12, day: 21), .winter)
        XCTAssertEqual(Season.current(month: 2, day: 1), .winter)
        XCTAssertEqual(Season.fallProgress(month: 9, day: 22), 0)
        XCTAssertEqual(Season.fallProgress(month: 12, day: 21), 1)
        XCTAssertEqual(Season.fallProgress(month: 6, day: 1), 0.5)
        XCTAssertGreaterThan(Season.fallProgress(month: 11, day: 19), Season.fallProgress(month: 10, day: 1))
    }

    func testWinterNeverMakesLeaves() {
        let simulation = simulation(.winter)
        pile(on: simulation)
        run(simulation, seconds: 2) { SIMD2(100 + $0 * 200, 285) }
        XCTAssertFalse(simulation.flakes.isEmpty)
        XCTAssertTrue(simulation.leaves.isEmpty)
        XCTAssertTrue(simulation.blownLeaves.isEmpty)
        XCTAssertTrue(simulation.pileLeaves.isEmpty)
    }

    func testFallReplacesFlakesWithFewerLeaves() {
        let simulation = simulation()
        simulation.snowfall = .flurry
        run(simulation, seconds: 1)
        XCTAssertTrue(simulation.flakes.isEmpty)
        XCTAssertEqual(simulation.leaves.count, simulation.budget.fallingLeaves)
        XCTAssertLessThan(simulation.budget.fallingLeaves, simulation.budget.flakes)
    }

    func testReducedMotionHasNoFallingLeavesOrGusts() {
        let simulation = simulation()
        simulation.reducedMotion = true
        pile(on: simulation)
        run(simulation, seconds: 60)
        XCTAssertTrue(simulation.leaves.isEmpty)
        XCTAssertTrue(simulation.blownLeaves.isEmpty)
    }

    func testSwitchingSeasonClearsWhatSettled() {
        let simulation = simulation(.winter)
        pile(on: simulation)
        simulation.season = .fall
        XCTAssertEqual(simulation.drifts[0].heights.max() ?? 0, 0)
        XCTAssertTrue(simulation.flakes.isEmpty)
        pile(on: simulation)
        simulation.season = .winter
        XCTAssertEqual(simulation.drifts[0].heights.max() ?? 0, 0)
        XCTAssertTrue(simulation.pileLeaves.isEmpty)
    }

    func testBlowerIsOnlyAvailableInFall() {
        let winter = simulation(.winter)
        winter.tool = .blower
        XCTAssertEqual(winter.tool, .glove)
        let fall = simulation()
        fall.tool = .blower
        XCTAssertEqual(fall.tool, .blower)
        fall.season = .winter
        XCTAssertEqual(fall.tool, .glove)
    }

    func testRestingLeavesSitOnThePileAndFollowItsHeight() {
        let simulation = simulation()
        pile(on: simulation, height: 4)
        let low = simulation.pileLeaves.count
        XCTAssertGreaterThan(low, 0)
        for leaf in simulation.pileLeaves {
            XCTAssertGreaterThanOrEqual(leaf.position.x, 100)
            XCTAssertLessThanOrEqual(leaf.position.x, 500)
            XCTAssertLessThan(leaf.position.y, 300)
            XCTAssertGreaterThan(leaf.position.y, 300 - 4 - leaf.size * 1.4)
        }
        pile(on: simulation, height: 16)
        XCTAssertGreaterThan(simulation.pileLeaves.count, low * 2)
    }

    func testRestingLeavesKeepTheirSlotsAsThePileGrows() {
        let simulation = simulation()
        pile(on: simulation, height: 4)
        let before = simulation.pileLeaves
        pile(on: simulation, height: 12)
        // Rows are emitted bottom-up, so a fully arrived leaf is found again, unmoved.
        for leaf in before where leaf.opacity >= 1 {
            XCTAssertTrue(simulation.pileLeaves.contains { $0.position == leaf.position && $0.look == leaf.look })
        }
    }

    func testRestingLeavesCoarsenInsteadOfExceedingTheBudget() {
        let simulation = SnowSimulation(size: SIMD2(3000, 800),
                                        budget: SimulationBudget(flakes: 0, cells: 256), seed: 1)
        simulation.season = .fall
        simulation.updateSurfaces((0..<6).map { Surface(id: UInt64($0 + 1), x: 0, y: Float(100 + $0 * 100), width: 3000) })
        for drift in simulation.drifts { for i in drift.heights.indices { drift.heights[i] = 18 } }
        simulation.rebuildMesh()
        XCTAssertLessThanOrEqual(simulation.pileLeaves.count, simulation.budget.pileLeaves)
        // Every support still gets leaves rather than the first ones using the whole budget.
        for index in 0..<6 {
            let base = Float(100 + index * 100)
            XCTAssertTrue(simulation.pileLeaves.contains { $0.position.y < base && $0.position.y > base - 60 })
        }
    }

    func testRestingLeavesStayPutWhileAnOverfullDesktopKeepsFilling() {
        let simulation = SnowSimulation(size: SIMD2(3000, 800),
                                        budget: SimulationBudget(flakes: 0, cells: 256), seed: 1)
        simulation.season = .fall
        simulation.updateSurfaces((0..<6).map { Surface(id: UInt64($0 + 1), x: 0, y: Float(100 + $0 * 100), width: 3000) })
        func settled(at height: Float) -> Set<SIMD2<Float>> {
            for drift in simulation.drifts { for i in drift.heights.indices { drift.heights[i] = height } }
            simulation.rebuildMesh()
            XCTAssertLessThanOrEqual(simulation.pileLeaves.count, simulation.budget.pileLeaves)
            return Set(simulation.pileLeaves.filter { $0.opacity >= 1 }.map(\.position))
        }
        // Far more leaves than the budget holds, so the grid is coarsened throughout.
        var before = settled(at: 18)
        XCTAssertGreaterThan(simulation.pileLeafLevel, 0)
        for height in stride(from: Float(18.2), through: 19.4, by: 0.2) {
            let after = settled(at: height)
            // A little more height may add leaves, but must not shuffle the ones already down.
            XCTAssertGreaterThan(Float(before.intersection(after).count), Float(before.count) * 0.97)
            before = after
        }
    }

    func testBlowerLiftsLeavesOnlyWhileThePointerMoves() {
        let still = simulation(flakes: 0)
        pile(on: still)
        still.tool = .blower
        let resting = area(still)
        run(still, seconds: 0.5) { _ in SIMD2(300, 270) }
        XCTAssertTrue(still.blownLeaves.isEmpty)
        XCTAssertGreaterThanOrEqual(area(still), resting)

        let moving = simulation(flakes: 0)
        pile(on: moving)
        moving.tool = .blower
        let before = area(moving)
        run(moving, seconds: 0.5) { SIMD2(120 + $0 * 700, 270) }
        XCTAssertFalse(moving.blownLeaves.isEmpty)
        XCTAssertLessThan(area(moving), before * 0.6)
        // It reaches the pile from above without touching it.
        XCTAssertGreaterThan(SnowTool.blower.radius, 30)
        for leaf in moving.blownLeaves { XCTAssertTrue(leaf.body.position.x.isFinite && leaf.body.position.y.isFinite) }
    }

    func testBlownLeavesComeBackDown() {
        let simulation = simulation(flakes: 0)
        simulation.updateSurfaces([Surface(id: 1, x: 100, y: 300, width: 400),
                                   Surface(id: DesktopSceneBuilder.groundID, x: 0, y: 800, width: 1000)])
        for i in simulation.drifts[0].heights.indices { simulation.drifts[0].heights[i] = 10 }
        simulation.tool = .blower
        run(simulation, seconds: 0.5) { SIMD2(120 + $0 * 700, 270) }
        let lifted = simulation.blownLeaves.count
        XCTAssertGreaterThan(lifted, 20)
        XCTAssertLessThanOrEqual(lifted, simulation.budget.blownLeaves)
        run(simulation, seconds: 12)
        XCTAssertLessThan(simulation.blownLeaves.count, lifted / 4)
        for drift in simulation.drifts { XCTAssertGreaterThanOrEqual(drift.heights.min() ?? 0, 0) }
    }

    func testSweptLeavesTakeToTheAirInsteadOfFlowing() {
        let simulation = simulation(flakes: 0)
        pile(on: simulation)
        simulation.tool = .shovel
        run(simulation, seconds: 0.4) { SIMD2(150 + $0 * 500, 294) }
        XCTAssertFalse(simulation.blownLeaves.isEmpty)
        XCTAssertEqual(simulation.looseSnow.totalMass, 0, accuracy: 0.001)
        // Winter keeps the same sweep in the granular field.
        let winter = self.simulation(.winter, flakes: 0)
        pile(on: winter)
        winter.tool = .shovel
        run(winter, seconds: 0.1) { SIMD2(150 + $0 * 500, 294) }
        XCTAssertGreaterThan(winter.looseSnow.totalMass, 0)
    }

    func testGustsCarrySettledLeavesAway() {
        let simulation = simulation(flakes: 0)
        pile(on: simulation, height: 12)
        var most = 0
        let dt: Float = 1 / 30
        for _ in 0..<Int(40 / dt) {
            simulation.step(dt: dt, cursor: nil)
            most = max(most, simulation.blownLeaves.count)
        }
        XCTAssertGreaterThan(most, 5)
        XCTAssertLessThanOrEqual(most, simulation.budget.blownLeaves)
    }
}
