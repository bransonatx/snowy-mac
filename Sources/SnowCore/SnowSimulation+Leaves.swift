import Foundation

/// Fall: leaves ride the snow simulation's supports and heights, but they are light. Anything
/// that disturbs a pile sends its leaves into the air, and they settle wherever they land.
extension SnowSimulation {
    func seasonChanged() {
        flakes.removeAll(keepingCapacity: true)
        leaves.removeAll(keepingCapacity: true)
        gustRemaining = 0
        gustWind = 0
        gustClock = 14
        if tool == .blower && season != .fall { tool = .glove }
        clear()
    }

    private func randomLook() -> Float {
        LeafPile.look(shape: random.unit(), colour: random.unit(), age: leafAge)
    }

    func newLeaf(scattered: Bool) -> LeafParticle {
        // The flake's entry rules already keep new arrivals out of windows and upwind.
        var body = newFlake(scattered: scattered)
        let depth = random.unit()
        body.radius = 2
        body.opacity = 0.62 + depth * 0.38
        body.mass = LeafPile.area * 0.6
        return LeafParticle(
            body: body, size: 4.6 + depth * depth * 4.6, angle: random.value(0, .pi * 2),
            look: randomLook(), shade: 0.82 + depth * 0.18, spin: random.value(-0.9, 0.9),
            flipPhase: random.value(0, .pi * 2), flipRate: random.value(1.2, 3.2),
            swayRate: random.value(1.3, 2.5), sway: 16 + depth * 38, fall: 20 + depth * 36
        )
    }

    func spawnBlownLeaf(at position: SIMD2<Float>, velocity: SIMD2<Float>, mass: Float) {
        guard blownLeaves.count < budget.blownLeaves else { return }
        let body = SnowParticle(position: position, velocity: velocity, radius: 2, opacity: 1,
                                phase: random.value(0, .pi * 2), remainingLife: random.value(6, 9), mass: mass)
        blownLeaves.append(LeafParticle(
            body: body, size: random.value(4.4, 6.6), angle: random.value(0, .pi * 2),
            look: randomLook(), shade: 1, spin: random.value(-12, 12),
            flipPhase: random.value(0, .pi * 2), flipRate: random.value(3, 7),
            swayRate: random.value(1.6, 2.6), sway: random.value(20, 48), fall: 0
        ))
    }

    /// Material a sweep or a moving window pushed into the granular field becomes leaves in
    /// the air. Whatever does not fit the leaf budget stays in the field and flows as before.
    func liftLooseLeaves() {
        guard !looseSnow.active.isEmpty else { return }
        let room = budget.blownLeaves - blownLeaves.count
        guard room > 0 else { return }
        // A large displaced pile shares the remaining leaves, each carrying more area.
        let share = max(LeafPile.area, (looseSnow.totalMass + looseCarry) / Float(room))
        var spawned = 0
        let shove = pointerVelocity * 0.6
        let shoveSpeed = hypot(shove.x, shove.y)
        let carried = shoveSpeed > 420 ? shove * (420 / shoveSpeed) : shove
        looseSnow.drain { [unowned self] position, mass in
            guard spawned < room else { return false }
            looseCarry += mass
            while looseCarry >= share, spawned < room {
                looseCarry -= share
                spawned += 1
                let kick = SIMD2(random.value(-70, 70), random.value(-95, -15))
                spawnBlownLeaf(at: position + SIMD2(random.value(-2, 2), random.value(-2, 2)),
                               velocity: kick + carried, mass: share)
            }
            return true
        }
        if spawned > 0 { meshDirty = true; interactionDirty = true }
    }

    /// The blower works from a distance and only while the pointer moves: a faster pass
    /// lifts more, and leaves leave along the pass and away from it.
    func blow(from start: SIMD2<Float>, to end: SIMD2<Float>, dt: Float) {
        let delta = end - start
        let travel = hypot(delta.x, delta.y)
        let speed = travel / max(dt, 0.001)
        guard speed > 25 else { return }
        let power = min(1, (speed - 25) / 700)
        let heading = delta / max(travel, 0.001)
        let radius = SnowTool.blower.radius
        for drift in drifts {
            guard max(start.x, end.x) + radius >= drift.surface.x,
                  min(start.x, end.x) - radius <= drift.surface.x + drift.surface.width,
                  max(start.y, end.y) + radius >= drift.surface.y - 32,
                  min(start.y, end.y) - radius <= drift.surface.y + drift.surface.drop + 2 else { continue }
            for i in drift.heights.indices where drift.heights[i] > 0.3 {
                let localX = Float(i) * drift.spacing
                guard drift.surface.isExposed(at: localX) else { continue }
                let point = SIMD2(drift.surface.x + localX, drift.surface.baseY(at: localX) - drift.heights[i])
                let offset = point - Geometry.closestPoint(to: point, on: start, end)
                let distance = hypot(offset.x, offset.y)
                guard distance < radius else { continue }
                let falloff = 1 - distance / radius
                let lifted = min(drift.heights[i], (14 + 120 * power) * falloff * falloff * dt)
                drift.heights[i] -= lifted
                blowCarry += lifted * drift.spacing
                meshDirty = true
                interactionDirty = true
                while blowCarry >= LeafPile.area {
                    blowCarry -= LeafPile.area
                    let away = distance > 0.5 ? offset / distance : SIMD2<Float>(0, -1)
                    var direction = away * 0.55 + heading * 0.75
                        + SIMD2(random.value(-0.3, 0.3), random.value(-0.3, 0.3))
                    // Leaves always leave the surface upward, or they would land where they began.
                    direction.y = -(abs(direction.y) * 0.6 + 0.35)
                    direction /= max(0.001, hypot(direction.x, direction.y))
                    let launch = (130 + 420 * power * random.value(0.5, 1)) * (0.5 + 0.5 * falloff)
                    // With every leaf already in the air, the rest is blown clean away.
                    spawnBlownLeaf(at: point - SIMD2(0, 2), velocity: direction * launch, mass: LeafPile.area)
                }
            }
        }
        // Leaves already in the air are shoved along as well.
        let force = (500 + 1500 * power) * dt
        func shove(_ position: SIMD2<Float>) -> SIMD2<Float>? {
            let offset = position - Geometry.closestPoint(to: position, on: start, end)
            let distance = hypot(offset.x, offset.y)
            guard distance < radius else { return nil }
            let away = distance > 0.5 ? offset / distance : SIMD2<Float>(0, -1)
            return (away * 0.6 + heading * 0.6) * (force * (1 - distance / radius))
        }
        for i in leaves.indices {
            guard let push = shove(leaves[i].body.position) else { continue }
            let total = leaves[i].push + push
            let size = hypot(total.x, total.y)
            leaves[i].push = size > 500 ? total * (500 / size) : total
        }
        for i in blownLeaves.indices {
            if let push = shove(blownLeaves[i].body.position) { blownLeaves[i].body.velocity += push }
        }
    }

    /// Every so often the air picks up: falling leaves streak sideways and a few settled ones
    /// are carried off the tops of their piles.
    private func advanceGust(dt: Float) {
        guard !reducedMotion else { gustRemaining = 0; gustWind = 0; return }
        guard gustRemaining > 0 else {
            gustWind = 0
            gustClock -= dt
            if gustClock <= 0 {
                gustDuration = random.value(2.2, 3.6)
                gustRemaining = gustDuration
                gustDirection = abs(wind.velocity.x) > 4 ? (wind.velocity.x > 0 ? 1 : -1)
                    : (random.unit() < 0.5 ? -1 : 1)
                gustClock = random.value(22, 46)
            }
            return
        }
        gustRemaining -= dt
        let envelope = sin(.pi * (1 - max(0, gustRemaining) / gustDuration))
        let strength = envelope * envelope
        gustWind = gustDirection * 150 * strength
        guard !isThawing, !drifts.isEmpty else { return }
        var attempts = Int(strength * 3.2 + random.unit())
        while attempts > 0 {
            attempts -= 1
            liftGustLeaf()
        }
    }

    private func liftGustLeaf() {
        guard blownLeaves.count < budget.blownLeaves else { return }
        let drift = drifts[min(drifts.count - 1, Int(random.unit() * Float(drifts.count)))]
        let count = drift.heights.count
        let centre = min(count - 1, Int(random.unit() * Float(count)))
        let localX = Float(centre) * drift.spacing
        guard drift.heights[centre] > 2.2, drift.surface.isExposed(at: localX) else { return }
        // Take one leaf's worth of area from the chosen column and its neighbours.
        var need = LeafPile.area
        var taken: Float = 0
        for reach in 0..<6 where need > 0.01 {
            for index in (reach == 0 ? [centre] : [centre - reach, centre + reach])
            where index >= 0 && index < count && need > 0.01 {
                let height = min(drift.heights[index], need / drift.spacing)
                drift.heights[index] -= height
                taken += height * drift.spacing
                need -= height * drift.spacing
            }
        }
        guard taken > LeafPile.area * 0.3 else { return }
        meshDirty = true
        let top = SIMD2(drift.surface.x + localX, drift.surface.baseY(at: localX) - drift.heights[centre] - 3)
        spawnBlownLeaf(at: top, velocity: SIMD2(gustDirection * random.value(110, 240), -random.value(50, 150)),
                       mass: taken)
    }

    func stepLeaves(dt: Float, ambient: Float) {
        advanceGust(dt: dt)
        let scale = min(1, snowfall.density / Snowfall.flurry.density) * max(0, min(1, particleScale))
        let desired = reducedMotion ? 0 : min(budget.fallingLeaves, Int(Float(budget.fallingLeaves) * scale))
        if leaves.count > desired { leaves.removeLast(leaves.count - desired) }
        while leaves.count < desired { leaves.append(newLeaf(scattered: true)) }

        let breeze = ambient + wind.velocity.x + gustWind
        for i in leaves.indices {
            var leaf = leaves[i]
            leaf.body.phase += dt * leaf.swayRate
            if leaf.body.phase > .pi * 2 { leaf.body.phase -= .pi * 2 }
            leaf.push *= max(0, 1 - dt * 2.4)
            // A falling leaf swings side to side and drops fastest through the middle of each swing.
            leaf.body.velocity = SIMD2(breeze + leaf.sway * sin(leaf.body.phase),
                                       leaf.fall * (0.78 + 0.22 * cos(leaf.body.phase * 2))
                                           + wind.velocity.y * 0.35) + leaf.push
            let landed = advanceParticle(&leaf.body, dt: dt, recycleOnContact: true)
            leaf.angle += leaf.spin * dt
            leaf.flipPhase += leaf.flipRate * dt
            if landed || leaf.body.position.y > size.y + 8 || leaf.body.position.y < -40 {
                leaf = newLeaf(scattered: false)
            }
            if leaf.body.position.x < -8 { leaf.body.position.x = size.x + 4 }
            if leaf.body.position.x > size.x + 8 { leaf.body.position.x = -4 }
            leaves[i] = leaf
        }

        var index = 0
        while index < blownLeaves.count {
            var leaf = blownLeaves[index]
            leaf.body.remainingLife -= dt
            var velocity = leaf.body.velocity
            velocity += (SIMD2(0, LeafFlight.gravity) - (velocity - SIMD2(breeze * 0.8, 0)) * LeafFlight.drag) * dt
            leaf.body.velocity = velocity
            leaf.body.phase += dt * leaf.swayRate
            if leaf.body.phase > .pi * 2 { leaf.body.phase -= .pi * 2 }
            // Once the launch is spent the leaf flutters down like any other.
            let speed = hypot(velocity.x, velocity.y)
            let flutter = SIMD2(leaf.sway * sin(leaf.body.phase) * max(0, 1 - speed / 160), 0)
            leaf.body.velocity += flutter
            let settled = advanceParticle(&leaf.body, dt: dt)
            leaf.body.velocity -= flutter
            leaf.spin *= max(0, 1 - dt * 1.2)
            leaf.angle += leaf.spin * dt
            leaf.flipPhase += leaf.flipRate * (0.4 + speed / 140) * dt
            if settled || leaf.body.remainingLife <= 0
                || leaf.body.position.y > size.y + 20 || leaf.body.position.y < -400 {
                blownLeaves.swapAt(index, blownLeaves.count - 1)
                blownLeaves.removeLast()
                continue
            }
            blownLeaves[index] = leaf
            index += 1
        }
    }

    /// Airborne leaves for this frame, far and falling first so blown ones draw on top.
    public func writeLeafInstances(to buffer: UnsafeMutablePointer<LeafInstance>, capacity: Int) -> Int {
        var count = 0
        for leaf in leaves where count < capacity { buffer[count] = LeafInstance(leaf); count += 1 }
        for leaf in blownLeaves where count < capacity { buffer[count] = LeafInstance(leaf); count += 1 }
        return count
    }

    /// Resting leaves sit in fixed slots along each support, so a pile keeps its leaves as it
    /// grows, shrinks, or rides a dragged window. Rows are emitted bottom to top.
    func rebuildPileLeaves() {
        pileLeaves.removeAll(keepingCapacity: true)
        elevatedPileLeafCount = 0
        let limit = budget.pileLeaves
        guard limit > 0 else { return }
        // Coarsen the leaf grid as piles grow, so every support gets its share of the budget.
        // A row never thins below one leaf per slot, so the count is not simply area / leaf.
        pileScratch.removeAll(keepingCapacity: true)
        for drift in drifts {
            let width = drift.surface.visibleSpans.reduce(Float(0)) { $0 + max(0, $1.upper - $1.lower) }
            let mean = drift.heights.reduce(0, +) / Float(drift.heights.count)
            if width > 0, mean > 0.5 { pileScratch.append(SIMD2(width, mean)) }
        }
        func needed(_ scale: Float) -> Float {
            pileScratch.reduce(Float(0)) {
                $0 + ($1.x / (LeafPile.step * scale) + 1) * max(1, $1.y / (LeafPile.rise * scale))
            }
        }
        // The grid coarsens in fixed steps and holds each one until the piles clearly outgrow it
        // or fall well short of it. A scale that tracked the piles exactly moved every resting
        // leaf on every rebuild, which showed as flicker once the budget was reached.
        func gridScale(_ level: Int) -> Float { powf(1.25, Float(level)) }
        let most = Float(limit)
        while pileLeafLevel < 20, needed(gridScale(pileLeafLevel)) > most * 0.9 { pileLeafLevel += 1 }
        while pileLeafLevel > 0, needed(gridScale(pileLeafLevel - 1)) < most * 0.6 { pileLeafLevel -= 1 }
        let scale = gridScale(pileLeafLevel)
        for elevated in [true, false] {
            for drift in drifts where drift.surface.isElevated == elevated {
                appendPileLeaves(for: drift, scale: scale, limit: limit)
            }
            if elevated { elevatedPileLeafCount = pileLeaves.count }
        }
    }

    private func appendPileLeaves(for drift: SnowDrift, scale: Float, limit: Int) {
        let surface = drift.surface
        let step = LeafPile.step * scale, rise = LeafPile.rise * scale
        for row in 0..<Int(32 / rise) + 1 {
            var placed = false
            let floor = Float(row) * rise + 0.9
            for span in surface.visibleSpans {
                var slot = Int((span.lower / step).rounded(.up))
                let last = Int((span.upper / step).rounded(.down))
                while slot <= last {
                    defer { slot += 1 }
                    let hash = LeafPile.hash(surface.id, slot, row)
                    let localX = max(span.lower, min(span.upper,
                        (Float(slot) + (LeafPile.unit(hash, 0) - 0.5) * 0.9) * step))
                    let height = drift.height(at: localX)
                    let need = floor + LeafPile.unit(hash, 1) * rise * 0.6
                    guard height >= need else { continue }
                    placed = true
                    guard pileLeaves.count < limit else { return }
                    // A leaf grows in as the pile reaches it; buried leaves sit in shadow.
                    let arrival = min(1, (height - need) / 0.8)
                    let buried = min(1, (height - need) / 9)
                    let size = (4.4 + LeafPile.unit(hash, 2) * 2.2) * scale * (0.45 + 0.55 * arrival)
                    let turn = 0.5 + 0.5 * LeafPile.unit(hash, 6)
                    pileLeaves.append(LeafInstance(
                        position: SIMD2(surface.x + localX, surface.baseY(at: localX) - need - size * 0.2),
                        size: size, angle: LeafPile.unit(hash, 3) * .pi * 2,
                        look: LeafPile.look(shape: LeafPile.unit(hash, 4), colour: LeafPile.unit(hash, 5), age: leafAge),
                        opacity: arrival, shade: 1 - 0.34 * buried,
                        flip: LeafPile.unit(hash, 7) < 0.5 ? -turn : turn
                    ))
                }
            }
            if !placed { break }
        }
    }
}
