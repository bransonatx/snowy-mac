import XCTest
@testable import SnowCore

final class ThawTests: XCTestCase {
    private func simulation(budget: SimulationBudget = SimulationBudget(flakes: 0)) -> SnowSimulation {
        SnowSimulation(size: SIMD2(1000, 800), budget: budget, seed: 42)
    }

    private func snow(on simulation: SnowSimulation, height: Float = 8) {
        simulation.updateSurfaces([Surface(id: 1, x: 100, y: 200, width: 400)])
        for i in simulation.drifts[0].heights.indices { simulation.drifts[0].heights[i] = height }
    }

    /// Everything the thaw is responsible for: caps, loose grains, and queued hand-offs.
    private func settledArea(_ simulation: SnowSimulation) -> Float {
        simulation.drifts.reduce(0) { $0 + $1.heights.reduce(0, +) * $1.spacing }
            + simulation.looseSnow.totalMass + simulation.pendingTransferMass
    }

    private func run(_ simulation: SnowSimulation, seconds: Float, dt: Float = 1 / 30,
                     each: () -> Void = {}) {
        for _ in 0..<Int((seconds / dt).rounded()) {
            simulation.step(dt: dt, cursor: nil)
            each()
        }
    }

    func testThawLowersCapsLinearlyAndFinishesOnTime() {
        let simulation = simulation()
        snow(on: simulation)
        simulation.beginThaw(duration: 2)
        XCTAssertTrue(simulation.isThawing)
        run(simulation, seconds: 1)
        XCTAssertEqual(simulation.drifts[0].height(at: 200), 4, accuracy: 0.05)
        XCTAssertTrue(simulation.isThawing)
        run(simulation, seconds: 1.1)
        XCTAssertFalse(simulation.isThawing)
        // Snowfall resumed a moment ago, so only a trace may have settled since.
        XCTAssertLessThan(simulation.drifts[0].height(at: 200), 0.1)
    }

    func testMeshFollowsThawAndEmptiesWhenItEnds() {
        let simulation = simulation()
        snow(on: simulation)
        simulation.rebuildMesh()
        let top = { simulation.mesh.map { $0.position.y }.min() ?? .infinity }
        let before = top()
        simulation.beginThaw(duration: 2)
        run(simulation, seconds: 1)
        // Screen y grows downward: the drawn upper edge has sunk about half of its eight points.
        XCTAssertEqual(top() - before, 4, accuracy: 0.5)
        var steps = 0
        while simulation.isThawing, steps < 100 {
            simulation.step(dt: 1 / 30, cursor: nil)
            steps += 1
        }
        XCTAssertFalse(simulation.isThawing)
        XCTAssertTrue(simulation.mesh.isEmpty)
    }

    func testThawTakesTheSameSimulatedTimeAtLowerFrameRates() {
        let smooth = simulation(), slow = simulation()
        snow(on: smooth)
        snow(on: slow)
        smooth.beginThaw(duration: 2)
        slow.beginThaw(duration: 2)
        run(smooth, seconds: 1, dt: 1 / 30)
        run(slow, seconds: 1, dt: 1 / 20)
        XCTAssertEqual(smooth.drifts[0].height(at: 200), slow.drifts[0].height(at: 200), accuracy: 0.05)
        XCTAssertEqual(smooth.thawRemaining, slow.thawRemaining, accuracy: 0.01)
    }

    func testThawNeverAddsSnowWhileFlakesKeepFalling() {
        // The same thaw with and without falling flakes must leave identical settled snow.
        let quiet = simulation(), snowing = simulation(budget: SimulationBudget(flakes: 300))
        for simulation in [quiet, snowing] {
            simulation.snowfall = .flurry
            // Low enough that ordinary snowfall and flake landings would raise it.
            snow(on: simulation, height: 2)
            simulation.beginThaw(duration: 3)
        }
        let start = settledArea(snowing)
        var previous = start
        run(snowing, seconds: 2.9) {
            quiet.step(dt: 1 / 30, cursor: nil)
            let area = settledArea(snowing)
            XCTAssertLessThanOrEqual(area, previous + 0.001)
            XCTAssertEqual(area, settledArea(quiet), accuracy: 0.001)
            XCTAssertEqual(area, start * snowing.thawRemaining / 3, accuracy: 0.5)
            previous = area
        }
        XCTAssertTrue(snowing.isThawing)
        XCTAssertFalse(snowing.flakes.isEmpty)
        XCTAssertTrue(snowing.drifts[0].heights.allSatisfy { $0 >= 0 && $0.isFinite })
        run(snowing, seconds: 0.2)
        XCTAssertFalse(snowing.isThawing)
    }

    func testSnowSettlesAgainAfterThaw() {
        let simulation = simulation()
        snow(on: simulation)
        simulation.beginThaw(duration: 1)
        run(simulation, seconds: 1.1)
        XCTAssertFalse(simulation.isThawing)
        run(simulation, seconds: 3)
        XCTAssertGreaterThan(simulation.drifts[0].height(at: 200), 0.2)
    }

    func testThawMeltsLooseGrainsWithoutLeavingActiveCells() {
        let simulation = simulation(budget: SimulationBudget(flakes: 0, debris: 8))
        snow(on: simulation)
        simulation.step(dt: 1 / 30, cursor: SIMD2(90, 195))
        simulation.step(dt: 1 / 30, cursor: SIMD2(510, 195))
        XCTAssertGreaterThan(simulation.looseSnow.totalMass, 0)
        simulation.beginThaw(duration: 1)
        var previous = settledArea(simulation)
        run(simulation, seconds: 0.9) {
            let area = settledArea(simulation)
            XCTAssertLessThanOrEqual(area, previous + 0.05)
            previous = area
        }
        XCTAssertTrue(simulation.isThawing)
        // Snowfall resumes once the thaw ends, so only the loose field is checked after it.
        run(simulation, seconds: 0.2)
        XCTAssertFalse(simulation.isThawing)
        XCTAssertTrue(simulation.looseSnow.active.isEmpty)
        XCTAssertEqual(simulation.looseSnow.totalMass, 0)
        XCTAssertEqual(simulation.pendingTransferMass, 0)
    }

    func testClearCancelsThaw() {
        let simulation = simulation()
        snow(on: simulation)
        simulation.beginThaw(duration: 4)
        run(simulation, seconds: 0.5)
        simulation.clear()
        XCTAssertFalse(simulation.isThawing)
        XCTAssertEqual(settledArea(simulation), 0)
        // With the thaw cancelled, snowfall settles straight away instead of waiting it out.
        run(simulation, seconds: 2)
        XCTAssertGreaterThan(simulation.drifts[0].height(at: 200), 0.1)
    }

    func testReducedMotionThawSnapsToClear() {
        let simulation = simulation()
        simulation.reducedMotion = true
        snow(on: simulation)
        simulation.beginThaw()
        XCTAssertFalse(simulation.isThawing)
        XCTAssertEqual(settledArea(simulation), 0)

        // Turning Reduced Motion on part-way through finishes the thaw at the next tick.
        let running = self.simulation()
        snow(on: running)
        running.beginThaw(duration: 4)
        run(running, seconds: 0.5)
        XCTAssertGreaterThan(settledArea(running), 0)
        running.reducedMotion = true
        running.step(dt: 1 / 30, cursor: nil)
        XCTAssertFalse(running.isThawing)
        XCTAssertEqual(running.drifts[0].height(at: 200), 0)
    }

    func testBadDurationsClearAtOnceAndLongOnesAreBounded() {
        for duration in [Float.nan, .infinity, 0, -3] {
            let simulation = simulation()
            snow(on: simulation)
            simulation.beginThaw(duration: duration)
            XCTAssertFalse(simulation.isThawing)
            XCTAssertEqual(settledArea(simulation), 0)
        }
        let simulation = simulation()
        snow(on: simulation)
        simulation.beginThaw(duration: 10_000)
        XCTAssertEqual(simulation.thawRemaining, 60)
    }

    func testGranularMeltScalesAreaAndIgnoresGrowth() {
        let field = GranularSnow(size: SIMD2(200, 200), maxCells: 4096, maxActive: 512)
        XCTAssertEqual(field.add(mass: 180, at: SIMD2(60, 60)), 0)
        let revision = field.revision
        field.melt(by: 0.5)
        XCTAssertEqual(field.totalMass, 90, accuracy: 0.01)
        XCTAssertNotEqual(field.revision, revision)
        field.melt(by: 2)
        field.melt(by: .nan)
        XCTAssertEqual(field.totalMass, 90, accuracy: 0.01)
        field.melt(by: 0)
        XCTAssertTrue(field.active.isEmpty)
        XCTAssertEqual(field.totalMass, 0)
    }
}
