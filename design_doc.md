# Technical Specifications & Game Design Document: The Smog & The Swarm (1890s-1920s Era Post-Zombie Apocalypse Industrial Revolution British Empire) - v4.6

> **v4.6 (2026-08-18)** reconciles §5 with what the terrain pipeline actually does.
> Biomes are a real vector polygon partition, not a splatmap; the land-cover source is
> OpenStreetMap rather than CORINE; elevation comes from AWS/Mapzen Terrain Tiles rather
> than SRTM directly; and the pipeline is deterministic geometry, not "AI terrain
> synthesis". Everything else is unchanged. Where the doc still describes something not
> yet built, it is marked **PLANNED**; `todo.md` remains the authority on status.

---

## 1. Biomes & Terrain Rules

### Movement Modifiers
* **FARMLAND** - Movement reduced for ground units & zombies by 10% (0.9x speed)
  * **Clay:** Abundant | **Wood:** Common | **Limestone:** Rare
* **MOORLAND** - Movement reduced for ground units & zombies by 50% (0.5x speed)
  * **Coal:** Common | **Iron Ore:** Common | **Limestone:** Rare | **Wood:** Rare
* **HIGHLAND** - Movement reduced for ground units & zombies by 25% (0.75x speed)
  * **Iron Ore:** Abundant | **Coal:** Common | **Limestone:** Common | **Sulfur:** Rare | **Wood:** Rare
* **WETLAND** - Movement reduced for ground units & zombies by 50% (0.5x speed)
  * **Clay:** Abundant | **Wood:** Common | **Coal:** Rare
* **WOODLAND** - Movement reduced for ground units & zombies by 25% (0.75x speed)
  * **Wood:** Abundant | **Clay:** Common | **Iron Ore:** Rare | **Coal:** Rare
* **HEATHLAND** - Movement reduced for ground units & zombies by 50% (0.5x speed)
  * **Wood:** Common | **Clay:** Common | **Limestone:** Rare | **Sulfur:** Rare
* **WATERWAY** - IMPASSABLE for all ground units & zombies. Traversable ONLY via Bridges.
  * **Resources:** None
* **OCEAN** - IMPASSABLE for all ground units & zombies
  * **Resources:** None
* **URBAN** - No modifier defined. **OPEN DECISION** — the land-cover bake classifies and renders real OSM built-up area as its own biome, but this list never gave it a movement rule, so `HexPathfinder._BIOME_COST_MULTIPLIER` falls through to its 1.0 default and units cross a city at full speed.
  * **Resources:** None
* **INDUSTRIAL** - No modifier defined. **OPEN DECISION**, same as URBAN — real OSM industrial land is classified, rendered, and currently free to cross.
  * **Resources:** None

### Terrain vs. Infrastructure Speed Stacking Rule
Constructed transit corridors (**Dirt Road, Cobblestone Road, Concrete Road, Railway, Bridges**) increase base movement speed by their respective tier multiplier while **completely ignoring underlying biome movement speed reductions** (terrain penalties do not apply while units are actively traversing directly on the infrastructure tile itself). These movement bonuses and biome immunity do not apply broadly to off-road movement within the surrounding biome.

*For example, a unit traveling directly along a Concrete Road (+100% base speed) through a Wetland (normally 0.5x speed) moves at the full +100% speed bonus (2.0x base speed), completely ignoring the native 50% Wetland movement penalty. However, stepping off the road into the adjacent Wetland tile immediately applies the native 0.5x Wetland movement penalty.*

---

## 2. Core Resource System, Extraction Gating & Logistics Rules

### Streamlined Resource Pool
To maintain deep industrial strategy without overwhelming player management, resources are streamlined into:

* **Raw Resources (6):** Wood, Clay, Coal, Limestone, Iron Ore, Sulfur.
* **Processed Resources (5):** Bricks, Iron, Steel, Concrete, Gunpowder.
* **Capacity & Yield Pools (4):** Population, Energy, Food, Research.

### Resource Tier Extraction Hierarchy
* **Tier 0 (Wood Base):** Wood (Lumber Yard), Clay (Clay Pit)
* **Tier 1 (Brick Base):** Coal (Coal Mine), Limestone (Limestone Quarry)
* **Tier 2 (Iron Base):** Iron Ore (Iron Ore Mine)
* **Tier 3 (Steel Base):** Sulfur (Sulfur Mine), Coal/Wood high-output consolidators (Deep Coal Shafts, Sawmills) & **City Expansion** (Remote specialized outposts)
* **Tier 4 (Traction Era):** Advanced Extraction (Steam Excavator Depot boosts node yields by +50%)
* **Tier 5 (Armament Era):** Mass Synthesis & Automation (Bessemer Smelting Complexes & Synthetic Refineries)

### Processed Resource Recipes
* **Bricks** — Produced at Brickworks (Inputs: Clay).
* **Iron** — Produced at Iron Foundry (Inputs: Iron Ore, Coal).
* **Steel** — Produced at Steelworks / Bessemer Complex (Inputs: Iron Ore or Iron + Coal).
* **Concrete** — Produced at Concrete Plant (Inputs: Limestone, Clay, Coal).
* **Gunpowder** — Produced at Gunpowder Mill / Synthetic Refinery (Inputs: Sulfur, Coal).

### Capacity Systems & Research Pacing
* **Population** — Provided by housing. Reserved as flat cost by facilities and military units. Fully refunded upon demolition or unit death.
* **Energy** — Provided by power generators. Reserved as flat cost by active infrastructure and industrial facilities.
* **Food** — Daily upkeep produced by agricultural structures. Deducted continuously based on housing and facility demands.
* **Research** — Daily yield produced by research facilities.
  * **Tech Unlock Thresholds:**
    * Tier 1 (Borough): 50 Research
    * Tier 2 (Industrial District): 200 Research
    * Tier 3 (Rail Network): 500 Research
    * Tier 4 (Automation Era): 1,200 Research
    * Tier 5 (Super-Complex Era): 2,500 Research

### Unified Zone of Control (ZoC) & Field Supply Rules
* **ZoC Emission & Expansion:** Players begin with **1 Pre-built Starter Town Hall** emitting a 5 mi x 5 mi ZoC circle. Constructing new Town Halls to establish far-flung cities and expand global network coverage is **locked until Tier 3**. Linked ZoCs pool global stockpiles; unlinked ZoCs remain local.
* **Infantry Gunpowder Logistics:** Units inside ZoC draw seamlessly from stockpiles. Units exiting ZoC reserve **20 rounds of Gunpowder**. Re-entering any ZoC or visiting an Supply Dump automatically re-arms reserves.
* **Steam Vehicle Fuel Logistics:** Steam-powered combat vehicles draw Coal directly from pooled stockpiles inside ZoC. When leaving ZoC, steam vehicles reserve **50 Coal** (enabling independent field operations). Re-entering ZoC or visiting a Supply Dump refuels reserves automatically.

### Infrastructure Velocity Modifiers
Each tier of road/transit infrastructure increases base movement speed while ignoring all native biome movement speed reductions:
* **Dirt Road:** +25% Speed (Ignores Biome Reductions)
* **Cobblestone Road:** +50% Speed (Ignores Biome Reductions)
* **Concrete Road:** +100% Speed (Ignores Biome Reductions)
* **Railway:** +300% Speed (Primary heavy bulk freight line; Ignores Biome Reductions)
* **Canal:** +200% Speed (Bulk aquatic freight route; Ignores Biome Reductions)

---

## 2.1 Strategic Hex Infestation

> Settled with the user 2026-08-27 across a 30-question design review. This
> section's first draft carried a diffusion PDE, four suppression-building rates,
> and three mutually contradictory band definitions. All are deleted and superseded
> by what follows. `decisions.md` records why each call was made.

### Infestation is derived, never stored

Each 5-mile strategic hex carries one mutable number and one static capacity.
Everything else is computed:

* `total_zombie_pop` *(int, static per hex)*: how many zombies this hex can hold,
  baked from real 1890s human population (see "Population capacity" below). Floor of
  1,000, so even the emptiest hex in Britain holds 750 zombies at the Hive Core
  threshold.
* `zombie_count` *(int, saved)*: how many are there right now. The only mutable
  state in the model.
* `infestation` *(derived)*: `zombie_count / total_zombie_pop * 100.0`.
* `is_cleared` *(derived)*: `infestation < 5.0`.

Neither derived value is stored or saved, so the two cannot drift — the same
derived-never-stored pattern `UnitUpgrades.gd` uses. Killing zombies lowers
infestation because it lowers the count; that is arithmetic, not a rule anyone has to
implement. The lenient 5.0 clear threshold is deliberate — the user's reason,
verbatim: "I was just trying to be a bit lenient so players could still build things
even if theyre getting attacked by zombies/clearing out zombies etc."

| State | Infestation | Build Rights | ZoC Network Impact |
| :--- | :--- | :--- | :--- |
| **Hive Core** | 75.0 – 100.0 | None | Total Severance |
| **Contested** | 25.1 – 74.9 | None | Severed / Stockpile Split |
| **Fringe / Outpost** | 5.0 – 25.0 | Defensive / Forts | Degradation (-25% Logistics Efficiency) |
| **Cleared** | < 5.0 | Unrestricted | Full Global Link |

* **Hive Core (75.0 – 100.0):** Spawns new zombies, and at 100.0 exports roaming
  hordes. Completely blocks ZoC propagation.
* **Contested (25.1 – 74.9):** No construction. Severs global ZoC pooling; a
  settlement cut off this way falls back to its own local stockpile (§2.2). Existing
  non-defensive structures decay while the hex is Contested. **Spreads nothing** —
  see "Only Hive Core bleeds" below.
* **Fringe / Outpost (5.0 – 25.0):** Construction restricted to Defensive Tier
  structures (Watchtowers, Garrisons, Walls, Supply Dumps). ZoC projects through, at
  -25% logistics efficiency.
* **Cleared (< 5.0):** Unrestricted construction, including a Town Hall to anchor a
  new settlement and its stockpile.

### Population capacity

`total_zombie_pop` is baked per hex from real 1890s population, in priority order:
Wikidata historical population statements (CC0, good coverage for cities and towns),
then OSM `place` node population tags scaled for the long tail (ODbL, already in the
bake pipeline and already attributed), then the 1,000 floor.

**Capacity is the difficulty curve, and that is the point.** A London hex holding
order 1e6 and a Highland Scotland hex holding 1e3 means real history decides where
the player can go and when, with no hand-authored region gating. The Manchester →
London campaign arc is a difficulty ramp because the census says so. The consequence
accepted with it: some regions are effectively closed until very late, decided by
population data rather than by design.

The Great Britain Historical Database's parish-level 1801-1951 statistics were
evaluated and rejected: copyright Southall/Gregory/Ell/Gatley via UK Data Service,
not downloadable from its own repository, and silent on commercial use.

### Starting state

At worldgen, infestation is seeded in rings out from the player's starting hex: **0%
at the start hex, then 25%, 50%, 75%, and 100% from ring four out.** The player gets
a real opening, and ring three sits exactly at the Hive Core threshold so the bleed
and horde-export mechanics are visible near home from the first day rather than being
a late-game surprise.

### Spawning and export

* A hex above 75.0 breeds at a **flat percentage of its own capacity per day**. One
  constant works from Highland Scotland to Southwark; the exact figure is a balancing
  number, not a design decision.
* A hex at 100.0 **exports roaming hordes**, and export never drops it below 75.0.
  The exported count is sized to respect that floor. Only player killing takes a hex
  below 75.0.
* The result is a self-regulating pump: breed to 100, export down to 75, breed again.
  A city left alone ships hordes at the player indefinitely; a city ground down by
  military force stops.

### Only Hive Core bleeds, and bleeding is just walking

There is no field equation. Zombies are entities that walk, so infestation moves
because they moved. A hex below 75.0 spreads nothing however infested it is, which
makes the Contested band a stable holding zone that never threatens its neighbours.

**Zombies ignore all infrastructure speed modifiers.** The user's reason, verbatim:
"zombies shouldn't travel faster over roads or rails or canals because they can't
drive or take the train lol". This makes the player's road and rail network a pure
asymmetric advantage, gives hordes a predictable cross-country travel time, and makes
early warning meaningful. **Implementation note:** `HexPathfinder`'s infrastructure
modifiers are read by three separate neighbour-expansion loops — `find_path()`,
`HordeFlowField._build_field()`, and `HordeManager._replan_cheap()`. Zombie pathing
must skip them in all three. `_replan_cheap()` goes through neither real search and
is the caller that was missed when `is_water_crossing_blocked()` was added; do not
miss it again.

### Walls block bleed proportionally

Wall coverage along a shared hex boundary reduces passive bleed across it in
proportion: 60% of the border walled means 40% of the bleed. Fully sealed means none.

* **Walls stop the seep. They do not stop hordes.** A horde still sieges the wall
  exactly as `HordeManager._siege_wall()` already implements. Walls buy time, never
  immunity — matching *They Are Billions*, and preventing "wall in and never fight"
  from beating the game.
* **A gate is a wall that friendly units can pass through**, and nothing else. It
  blocks bleed and sieges identically; `WallManager.damage_segment()` already makes
  no distinction.
* **Coverage is measured at sub-hex resolution**, extending
  `SubHexPortalGraph.has_any_crossing()`'s 30 m sampling along the shared edge rather
  than adding a second boundary check (CLAUDE.md §3).
* **Coverage must be cached per hex-pair.** Proportional coverage cannot early-out
  the way the passability check does, so it walks the whole edge. Walls change only
  on place / remove / breach / repair, and `WallManager` emits a signal for all four
  — invalidate on those, never recompute per query.
* Cost check, for balance: a hex edge is 512 world units (`HexCoord.HEX_SIZE` is the
  circumradius, so edge == circumradius, ~4,992 m). A wall piece caps at 100 m (10.26
  world units). **Sealing one border is ~50 pieces = 2,000 Wood; sealing all six is
  ~300 pieces = 12,000 Wood.**
* Walls stay freehand (`WallSegment.point_a`/`point_b`, not hex-edge-snapped).
  Snapping is added as a **placement aid** when a drawn line runs near a hex border,
  with a modifier key to refuse — sealing a border must be achievable without pixel
  hunting, but the chain-of-pieces freehand model the user asked for is unchanged.

### Killing is the only suppression

There are no passive suppression rates. The Watchtower `+5.0/day`, Garrison
`+20.0/day` and Searchlight `+10.0/day` figures from this section's first draft are
deleted, along with its "Phase 2: Border Suppression" stage. The user's rule,
verbatim: "Zombies create infestation. Suppressing infestion means getting rid of
zombies."

Holding ground therefore costs a standing garrison of real military units with real
Food and Population upkeep, plus walls to stop the seep between fights. That is the
intended price of territory, and it makes overextension self-limiting without an
artificial rule. The late-game management load this implies across many hexes is
acknowledged and deliberately not solved yet (see `vision.md` P3).

### Re-infestation

A roaming horde crossing a Cleared hex raises its count and can push it back over
5.0. **Build rights are checked at placement only.** Standing buildings are destroyed
by zombies attacking them, never by the ratio crossing a threshold — otherwise one
horde wandering past would brick an industrial hex without a fight.

### Attraction

Zombies are drawn to noise, light, and the smell of blood, in that build order:

1. **Noise** — already built. `HordeManager`'s ATTRACTED state and
   `_pick_attraction_target()` read `NoiseManager` and path toward the loudest hex
   within `ATTRACTION_AWARENESS_RADIUS`. The consumer is sound; what needs replacing
   is the emission model — a flat 2-hex building-only aura, roughly 40x the reach of
   §6's loudest listed sound.
2. **Light** — second increment. A crude version costs almost nothing: buildings
   already carry `lit_at_night`, so lit buildings add to their hex's attraction score
   after dark. Full §6 line-of-sight illumination follows later and is not a
   prerequisite.
3. **Blood** — raised by the user, explicitly deferred, not designed.

### Going dark: buildings can be switched off

The player's primary counterplay to a horde too large to fight. An off building
produces nothing, consumes no upkeep, emits no noise and no light. **Restarting costs
a delay proportional to building tier** — free instant toggling would make going dark
a no-brainer spammed on sight, and banking a Victorian furnace and bringing it back
up is a real operation, not a light switch.

### Simulation model: every zombie is a real entity

The user's requirement, verbatim: "I want this to truly be TABs on an absolutely
massive scale." Counts are literal — a London hex genuinely holds order 1e6 — and
what the player sees is individual zombies, not abstractions.

**Measured before it was trusted** (`scripts/test/bench_zombie_scale.gd`, headless,
median of 10 frames, movement only — no rendering, AI, or combat):

| entities | packed arrays | `Array[Dictionary]` | `Array[Resource]` |
| ---: | ---: | ---: | ---: |
| 50,000 | 2.90 ms | 16.40 ms | 13.11 ms |
| 100,000 | 5.83 ms | 33.01 ms | 26.32 ms |
| 250,000 | 14.69 ms | 82.45 ms | 66.67 ms |
| 500,000 | 29.44 ms | — | — |
| 2,000,000 | 118.33 ms | — | — |

250,000 is the hard ceiling, and only with packed arrays spending the entire 16.6 ms
frame on movement alone. **Realistic budget is ~60,000 live movers.** For scale,
*They Are Billions*' endgame swarm is ~20,000.

The count stays literal; **entity instantiation is bounded by observation.** A hex is
5 mi x 5 mi, so the player can never see more than a fraction of one:

* **A hex is live** if it contains the camera, is one of the camera hex's six
  neighbours, or contains player units or buildings.
* A live hex instantiates up to its share of the ~60,000 budget, **placed nearest the
  observer first**. In London that is ~60,000 real zombies with ~1.84 million more
  behind them, streaming in as the player kills — the endless-tide feel falls out of
  the design rather than being scripted.
* Outside live hexes the count still breeds, bleeds and exports as a number. The
  player cannot detect the difference, because they cannot observe 60,000 zombies'
  worth of ground at once.

**Two classes, not one:**

* `Horde` stays what it is — the strategic aggregate: a count with a position,
  roaming the map, saved as a `Resource`.
* A **new tactical layer** holds individual zombies in packed arrays. Never a
  `Resource` per zombie: at `Array[Resource]` the ceiling is 50,000, which the
  benchmark above rules out.
* A horde **dissolves into live entities on entering a live hex and re-condenses on
  exit**, conserving its count. The seam is a pure representation change, so the
  player never sees a horde "pop" — it arrives as individuals.

**Tactical positions are saved**, as packed float32 (~8 bytes per zombie, so the
whole ~60,000 live set is under 500 KB). Not for size reasons but for correctness:
saving mid-siege and reloading must not teleport 60,000 attackers into fresh
positions, which would both read as broken and be trivially save-scummable.

**As built (2026-08-29).** `ZombieSwarm` / `ZombieSwarmManager` / `LiveHexTracker`,
measured on the real map with `scripts/test/diagnose_tactical_zombies.gd`:

| camera hex | zombies on it | wanted across the live set | instantiated |
| :--- | ---: | ---: | ---: |
| starting settlement | 0 | 113,674 | 60,000 |
| Manchester | 68,075 | 153,033 | 60,000 |
| Birmingham | 321,008 | 671,937 | 60,000 |
| Greater London | 446,729 | **2,123,376** | 60,000 |

The London row is this section's own claim, measured rather than estimated:
60,000 real zombies with **2,063,376 behind them**. The save is **468.8 KB** for a
full live set, against the estimate above. The step costs **2.79 ms** at the full
budget (`bench_zombie_swarm.gd`), and one decision the estimate did not anticipate
is worth carrying: how finely that step is sliced must be decided from the whole
live population rather than per crowd, or the same 60,000 split across 30 crowds
costs 11.11 ms instead of 2.79 (`decisions.md` D45).

---

## 2.2 Logistics, Stockpiles & Infrastructure

> Settled with the user 2026-08-27. Replaces the single global stockpile and the
> whole-edge supply-line model. The user's framing: "I think we need to relook at
> logistics as a whole... those logistics links need to be more concrete and visible
> to the user."

### One Town Hall, one stockpile

Resources are no longer a single global pool. **Each Town Hall owns one stockpile**,
and that is the unit of ownership — not the hex, because `is_settlement` is a per-hex
flag and cities span many hexes (Manchester 4, London 12), which would shatter one
city into a dozen competing pools. A 12-hex London has one Town Hall and therefore
one stockpile.

This makes the existing Town Hall founding feature load-bearing rather than
decorative: founding a second settlement is the moment the player acquires a
logistics problem.

**This is the most invasive change in the project.** It touches `ResourceManager`
(`_stockpile` is one flat `Dictionary` today), every producer and consumer, every
affordability check, every UI counter, and saves. It is also a prerequisite for
§2.1's Contested band. It belongs in its own PR with nothing else in it.

### Links pool stockpiles, throughput-limited

Connected settlements share their stockpiles, **but transfer rate is capped by the
weakest link on the path**. No goods entities are simulated — there are no carts or
trains to watch — but a dirt road bottlenecks what a railway would not, so upgrading
a line is a real decision and a bottleneck is a visible fact rather than an invisible
one.

**Throughput is aggregate tonnage per day, shared across all resource types**, not a
per-resource allowance. One number per line, so the player reads a bottleneck at a
glance instead of auditing fifteen counters — and a shortage forces a real choice
about what to ship today.

This is deliberately the smallest step that delivers "concrete and visible." Full
physical transport with travelling goods and latency is a later upgrade on top of
these numbers, not a rewrite of them.

### Infrastructure gets real geometry

`SupplyLineSegment` today is `hex_a`/`hex_b`/`tier`/`is_severed` with no world-space
points at all, so there is nowhere to put a curve. It gains `point_a`/`point_b` and
drawn runs are chopped into pieces, **reusing `WallManager.place_wall_line()`'s
existing path** rather than writing a second implementation — walls already solved
drawn-line-to-segments, per-piece state, and spatial indexing. `hex_a`/`hex_b`
survive as a spatial-index convenience with the same caveat `WallSegment` carries: it
is not a claim the piece runs along that hex pair's shared edge.

This closes the "supply lines are still whole-edge, the same shape walls used to have
before their rework" item in todo.md's architecture-debt list.

### Terminals are required, one at each end

Railway stations for railways, loading and unloading docks for canals, depots for
roads. **None of these exist yet** — the `DEPOT` entries in `GameEnums.BuildingType`
are High Command & Cavalry Depot, Steam Excavator Depot and Mechanized Maintenance
Depot, all unit and vehicle buildings. All three terminal types are net-new.

A line with no terminal at one end moves nothing. That is historically right — a
railway with no station is track trains cannot stop at — and it gives the player a
diagnosable failure mode: the track is built, nothing is moving, because the far end
has no station.

### Gradients, and canals need locks

Placement respects real terrain. A route may not climb or descend more than one
elevation level per step.

**Hard prerequisite: a fine elevation bake, which does not exist.** The mechanical
elevation raster is ~3,510 m/px, under one sample per hex edge — there is nothing to
read a gradient from. `fetch_terrarium.py` already pulls the source tiles and
`bake_fine_relief.py` already reads them at 30 m, discarding the values after
shading. **The same bake also unblocks §6 (line-of-sight needs sub-hex elevation) and
the vector-terrain epic's phase 4 (vertex-displaced relief)** — one job, three
features.

**Canals are dead flat and climb only through locks**, which cost resources to build
and reduce the line's throughput. This gives the three infrastructure types genuinely
different placement puzzles over the same terrain: rail wants gentle gradients,
canals want locks, roads go anywhere.

### Severance is infestation, not attack

A line is severed while a hex it runs through is **Contested (>25.0 infestation)** —
the same rule §2.1 already applies to ZoC pooling. No deliberate-target AI is
required (`HordeManager`'s own header lists building-siege targeting as unbuilt), one
rule serves two systems, and the failure is instantly legible: the supply line dies
exactly where the map goes red. Repairing it means clearing the ground, not
dispatching a repair cart. `is_severed` and `ReclamationManager`'s existing
un-severing path are unchanged.

**An isolated settlement stagnates; it does not die.** It keeps producing whatever its
own hexes support and goes short only of what it cannot make itself — a cut rail line
to an iron-poor settlement halts its foundries without killing its population. Death
spirals from a severed line would punish the player for a horde wandering across a
road while they were looking elsewhere, which is the same unfairness the
placement-time build-rights check exists to avoid.

---

## 3. Tiered Building Specifications

### Tier 0: Wood Base / Settlement
* **Town Hall** — **Pre-built at Game Start (1 Max at T0-T2)** | **Construction of additional Town Halls locked until Tier 3** | **Capacity:** +100 Pop, +20 Energy | **Upkeep:** 10 Food/day | **Output:** 5 Research/day | **ZoC:** 5mi x 5mi. Trains Tier 0 units (*Truncheoneer, Toxophilite, Outrider*).
* **Lumber Yard** — **Cost:** 50 Wood | **Capacity:** -5 Pop, -5 Energy | **Output:** 200 Wood/day | **Time:** 1 day
* **Clay Pit** — **Cost:** 60 Wood | **Capacity:** -15 Pop, -10 Energy | **Upkeep:** 10 Food/day | **Output:** 200 Clay/day | **Time:** 2 days
* **Smallholding Farm** — **Cost:** 100 Wood | **Capacity:** -10 Pop, -5 Energy | **Output:** 150 Food/day | **Time:** 1 day
* **Steam Furnace** — **Cost:** 100 Wood | **Capacity:** -5 Pop, +100 Energy | **Upkeep:** 30 Wood/day | **Time:** 1 day
* **Wooden Houses** — **Cost:** 40 Wood | **Capacity:** +50 Pop, -5 Energy | **Upkeep:** 20 Food/day | **Time:** 1 day
* **Dirt Road** — **Cost:** 10 Wood/seg | **Time:** 0.5 days | **Bonus:** +25% Speed (Ignores Biome Reductions)
* **Wooden Bridge** — **Cost:** 30 Wood/seg | **Time:** 1 day
* **Watchtower** — **Cost:** 80 Wood | **Capacity:** -5 Pop | **Time:** 1 day
* **Wooden Wall & Gate** — **Cost:** 10 Wood/seg | **Time:** 0.25 days

---

### Tier 1: Brick Base / Borough
* **Coal Mine** — **Cost:** 120 Wood, 50 Bricks | **Capacity:** -25 Pop, -20 Energy | **Upkeep:** 20 Food/day | **Output:** 100 Coal/day | **Time:** 2 days
* **Limestone Quarry** — **Cost:** 100 Wood, 50 Bricks | **Capacity:** -20 Pop, -15 Energy | **Upkeep:** 15 Food/day | **Output:** 150 Limestone/day | **Time:** 2 days
* **Brickworks** — **Cost:** 150 Wood | **Capacity:** -10 Pop, -30 Energy | **Upkeep:** 100 Clay/day | **Output:** 100 Bricks/day | **Time:** 2 days
* **Estate Farm** — **Cost:** 180 Wood, 50 Bricks | **Capacity:** -15 Pop, -30 Energy | **Output:** 450 Food/day | **Time:** 2 days
* **Coal Powerplant** — **Cost:** 100 Wood, 250 Bricks | **Capacity:** -15 Pop, +500 Energy | **Upkeep:** 40 Coal/day | **Time:** 3 days
* **Research Institute** — **Cost:** 100 Wood, 200 Bricks | **Capacity:** -50 Pop, -150 Energy | **Upkeep:** 80 Food/day | **Output:** 10 Research/day | **Time:** 4 days
* **Brick Houses** — **Cost:** 50 Wood, 50 Bricks | **Capacity:** +200 Pop, -10 Energy | **Upkeep:** 80 Food/day | **Time:** 2 days
* **Garrison** — **Cost:** 200 Wood, 100 Bricks | **Capacity:** -20 Pop, -20 Energy | **Time:** 2 days
* **Cobblestone Road** — **Cost:** 5 Wood, 10 Bricks/seg | **Bonus:** +50% Speed (Ignores Biome Reductions)
* **Brick Arch Bridge** — **Cost:** 15 Wood, 30 Bricks/seg
* **Brick Wall & Gate** — **Cost:** 10 Wood, 10 Bricks/seg
* **Supply Dump** — **Cost:** 100 Wood, 50 Bricks | Field gunpowder/fuel resupply node.

---

### Tier 2: Iron Base / Industrial District
* **Iron Ore Mine** — **Cost:** 200 Wood, 100 Bricks | **Capacity:** -30 Pop, -40 Energy | **Upkeep:** 25 Food/day | **Output:** 100 Iron Ore/day | **Time:** 3 days
* **Iron Foundry** — **Cost:** 200 Wood, 100 Bricks | **Capacity:** -40 Pop, -150 Energy | **Upkeep:** 100 Iron Ore/day, 25 Coal/day, 30 Food/day | **Output:** 100 Iron/day | **Time:** 3 days
* **Concrete Plant** — **Cost:** 100 Wood, 100 Bricks | **Capacity:** -30 Pop, -80 Energy | **Upkeep:** 100 Limestone/day, 50 Clay/day, 20 Coal/day, 30 Food/day | **Output:** 150 Concrete/day | **Time:** 3 days
* **Industrial Farm** — **Cost:** 400 Wood, 200 Bricks, 50 Iron | **Capacity:** -30 Pop, -20 Energy | **Output:** 1,200 Food/day | **Time:** 3 days
* **Tower Blocks** — **Cost:** 150 Wood, 100 Bricks, 50 Iron, 50 Concrete | **Capacity:** +500 Pop, -25 Energy | **Upkeep:** 200 Food/day | **Time:** 3 days
* **Armory & Barracks** — **Cost:** 250 Wood, 150 Bricks, 50 Iron | **Capacity:** -30 Pop, -40 Energy | **Time:** 3 days
* **Concrete Road** — **Cost:** 5 Wood, 10 Bricks, 10 Iron/seg | **Bonus:** +100% Speed (Ignores Biome Reductions)
* **Iron Girder Bridge** — **Cost:** 10 Wood, 20 Bricks, 20 Iron/seg
* **Concrete Wall & Gate** — **Cost:** 10 Wood, 10 Bricks, 10 Concrete/seg
* **Search Light** — **Cost:** 80 Wood, 50 Bricks, 30 Concrete, 20 Iron | **Capacity:** -5 Pop, -50 Energy | Large area of visibility.

---

### Tier 3: Steel Base / Rail Network
* **Town Hall** — **Unlocked at Tier 3** | **Cost:** 300 Wood, 200 Bricks, 150 Concrete, 100 Steel | **Capacity:** +100 Pop, +20 Energy | **Upkeep:** 10 Food/day | **Time:** 3 days | **Function:** Establishes a new 5mi x 5mi ZoC hex. Allows players to found far-flung cities specialized in extracting specific resource nodes. Only 1 can be built per hex tile.
* **Sulfur Mine** — **Cost:** 250 Wood, 150 Bricks, 100 Concrete, 50 Iron | **Capacity:** -35 Pop, -60 Energy | **Upkeep:** 30 Food/day | **Output:** 60 Sulfur/day | **Time:** 3 days
* **Deep Coal Shafts** — **Cost:** 300 Wood, 200 Bricks, 150 Concrete, 100 Iron | **Capacity:** -40 Pop, -100 Energy | **Upkeep:** 40 Food/day | **Output:** 500 Coal/day | **Time:** 4 days. High-output consolidator — one Deep Coal Shaft replaces roughly 5 Tier 1 Coal Mines' worth of output, keeping the late-game map from being tiled with small extractors.
* **Sawmills** — **Cost:** 300 Wood, 200 Bricks, 150 Concrete, 100 Iron | **Capacity:** -35 Pop, -80 Energy | **Upkeep:** 30 Food/day | **Output:** 1,000 Wood/day | **Time:** 4 days. Same role as Deep Coal Shafts, for Wood — replaces roughly 5 Tier 0 Lumber Yards.
* **Gunpowder Mill** — **Cost:** 150 Wood, 100 Bricks, 50 Iron | **Capacity:** -15 Pop, -40 Energy | **Upkeep:** 60 Sulfur/day, 40 Coal/day, 20 Food/day | **Output:** 120 Gunpowder/day | **Time:** 3 days
* **Steelworks** — **Cost:** 300 Wood, 200 Bricks, 150 Concrete, 100 Iron | **Capacity:** -40 Pop, -300 Energy | **Upkeep:** 100 Iron/day, 50 Coal/day, 40 Food/day | **Output:** 75 Steel/day | **Time:** 4 days
* **Mechanised Farm** — **Cost:** 800 Wood, 400 Bricks, 300 Concrete, 100 Steel | **Capacity:** -40 Pop, -50 Energy | **Output:** 3,500 Food/day | **Time:** 4 days
* **Advanced Coal Powerplant** — **Cost:** 400 Wood, 400 Bricks, 200 Concrete, 200 Steel | **Capacity:** -20 Pop, +3,000 Energy | **Upkeep:** 150 Coal/day | **Time:** 4 days
* **High Command & Cavalry Depot** — **Cost:** 300 Wood, 200 Bricks, 100 Concrete, 100 Steel | **Capacity:** -40 Pop, -80 Energy
* **Railway** — **Cost:** 15 Wood, 15 Bricks, 15 Concrete, 15 Steel/seg | **Bonus:** +300% Speed (Ignores Biome Reductions)
* **Canal** — **Cost:** 20 Wood, 20 Bricks, 20 Concrete, 10 Steel/seg | **Bonus:** +200% Speed (Ignores Biome Reductions)
* **Steel Truss Bridge** — **Cost:** 10 Wood, 10 Bricks, 20 Concrete, 20 Steel/seg
* **Steel Wall & Gate** — **Cost:** 10 Wood, 10 Bricks, 10 Concrete, 10 Steel/seg

---

### Tier 4: Advanced Engineering / Automation & Maintenance Era
* **Steam Excavator Depot** — **Cost:** 300 Wood, 300 Bricks, 250 Concrete, 150 Steel | **Capacity:** -20 Pop, -150 Energy | **Upkeep:** 40 Coal/day | **Function:** +50% raw node extraction yield across sector.
* **Heavy Coal Washery & Pulverizer** — **Cost:** 350 Wood, 400 Bricks, 300 Concrete, 200 Steel | **Capacity:** -30 Pop, -200 Energy | **Upkeep:** 150 Coal/day | **Function:** Boosts output of connected smelters/foundries by +100%.
* **Mechanized Maintenance Depot** — **Cost:** 250 Wood, 250 Bricks, 200 Concrete, 150 Steel | **Capacity:** -25 Pop, -100 Energy | **Upkeep:** 20 Iron/day, 10 Steel/day | Continuous auto-repair in ZoC.
* **Macadamized Transport Hub** — **Cost:** 200 Wood, 200 Bricks, 200 Concrete, 100 Steel | **Capacity:** -20 Pop, -100 Energy | **Upkeep:** 20 Food/day | +50% transfer throughput and speed.
* **Steam Turbine Power Plant** — **Cost:** 300 Wood, 500 Bricks, 400 Concrete, 400 Steel | **Capacity:** -30 Pop, +7,500 Energy | **Upkeep:** 300 Coal/day | **Time:** 6 days
* **Traction Works & Workshop** — **Cost:** 400 Wood, 300 Bricks, 200 Concrete, 200 Steel | **Capacity:** -50 Pop, -150 Energy
* **Reinforced Heavy Rampart** — **Cost:** 10 Wood, 15 Bricks, 20 Concrete, 15 Steel/seg

---

### Tier 5: Heavy Industrial / Super-Complex Era
* **Bessemer Smelting Complex** — **Cost:** 500 Wood, 600 Bricks, 500 Concrete, 400 Steel | **Capacity:** -50 Pop, -600 Energy | **Upkeep:** 150 Iron Ore/day, 50 Coal/day | **Output:** 250 Steel/day
* **Automated Freight Marshalling Yard** — **Cost:** 400 Wood, 500 Bricks, 400 Concrete, 300 Steel | **Capacity:** -40 Pop, -300 Energy | **Upkeep:** 50 Coal/day | Global rail speed +500%, zero transfer delay.
* **Synthetic Chemical Refinery** — **Cost:** 400 Wood, 400 Bricks, 300 Concrete, 300 Steel | **Capacity:** -40 Pop, -400 Energy | **Upkeep:** 150 Coal/day, 100 Sulfur/day | **Output:** 350 Gunpowder/day
* **Central High-Voltage Grid Station** — **Cost:** 500 Wood, 800 Bricks, 600 Concrete, 600 Steel | **Capacity:** -40 Pop, +18,000 Energy | **Upkeep:** 500 Coal/day
* **Ordnance & Armament Complex** — **Cost:** 600 Wood, 500 Bricks, 500 Concrete, 500 Steel | **Capacity:** -60 Pop, -300 Energy
* **Armored Bunker Fortification** — **Cost:** 20 Wood, 20 Bricks, 40 Concrete, 30 Steel/seg | **Capacity:** -10 Energy

---

## 4. Units

### Progression & Retraining Rules
* **Tech Hierarchy:** T0 -> T1 -> T2 -> T3 -> T4 -> T5. Unlocked via Research thresholds.
* **Upgrades:** 2 research upgrades per unit type (auto-applies to active & future units).
* **Retraining Mechanics:** Same archetype only (Melee/Ranged/Special). Retrain cost = **50% of target unit's resource cost**.

---

### Tier 0 Units (Town Hall)
* **Truncheoneer** (Melee) — **Cost:** 20 Wood | **Cap:** -1 Pop | **Upkeep:** 1 Food/day
* **Toxophilite** (Ranged) — **Cost:** 30 Wood | **Cap:** -1 Pop | **Upkeep:** 1 Food/day (No gunpowder needed)
* **Outrider** (Special) — **Cost:** 50 Wood | **Cap:** -1 Pop | **Upkeep:** 2 Food/day (Scout)

### Tier 1 Units (Garrison)
* **Navvy** (Melee) — **Cost:** 40 Wood, 10 Bricks | **Cap:** -1 Pop | **Upkeep:** 2 Food/day
* **Yeoman Marksman** (Ranged) — **Cost:** 40 Wood, 10 Bricks, 5 Gunpowder | **Cap:** -1 Pop | **Upkeep:** 2 Food/day, 1 Gunpowder/shot
* **Grenadier** (Special) — **Cost:** 50 Wood, 20 Bricks, 15 Gunpowder | **Cap:** -1 Pop | **Upkeep:** 3 Food/day, 2 Gunpowder/throw

### Tier 2 Units (Armory & Barracks)
* **Bayoneteer** (Melee) — **Cost:** 50 Wood, 20 Bricks, 10 Iron | **Cap:** -1 Pop | **Upkeep:** 3 Food/day
* **Redcoat** (Ranged) — **Cost:** 50 Wood, 20 Bricks, 15 Iron, 10 Gunpowder | **Cap:** -1 Pop | **Upkeep:** 3 Food/day, 1 Gunpowder/volley
* **Chasseur** (Special) — **Cost:** 80 Wood, 30 Bricks, 25 Iron, 10 Gunpowder | **Cap:** -2 Pop | **Upkeep:** 5 Food/day, 1 Gunpowder/shot

### Tier 3 Units (High Command & Cavalry Depot)
* **Highlander** (Melee) — **Cost:** 60 Wood, 30 Bricks, 30 Steel | **Cap:** -1 Pop | **Upkeep:** 4 Food/day
* **Sharpshooter** (Ranged) — **Cost:** 60 Wood, 30 Bricks, 40 Steel, 20 Gunpowder | **Cap:** -1 Pop | **Upkeep:** 4 Food/day, 1 Gunpowder/shot
* **Dragoon** (Special) — **Cost:** 100 Wood, 40 Bricks, 50 Steel, 15 Gunpowder | **Cap:** -2 Pop | **Upkeep:** 6 Food/day, 1 Gunpowder/shot

### Tier 4 Units (Traction Works & Workshop)
* **Traction Ram** (Melee Vehicle) — **Cost:** 150 Wood, 100 Bricks, 100 Concrete, 100 Steel | **Cap:** -3 Pop, -20 Energy | **Upkeep:** 10 Food/day, 10 Coal/day | **Fuel Reserve:** 50 Coal
* **Maxim Quadricycle** (Ranged Vehicle) — **Cost:** 100 Wood, 100 Bricks, 80 Concrete, 120 Steel, 40 Gunpowder | **Cap:** -2 Pop, -10 Energy | **Upkeep:** 8 Food/day, 5 Coal/day, 1 Gunpowder/burst | **Fuel Reserve:** 50 Coal
* **Searchlight Tender** (Special Vehicle) — **Cost:** 120 Wood, 80 Bricks, 100 Concrete, 80 Steel | **Cap:** -2 Pop, -15 Energy | **Upkeep:** 8 Food/day, 5 Coal/day | **Fuel Reserve:** 50 Coal

### Tier 5 Units (Ordnance & Armament Complex)
* **Holt Breaker** (Melee Vehicle) — **Cost:** 300 Wood, 200 Bricks, 200 Concrete, 300 Steel | **Cap:** -5 Pop, -50 Energy | **Upkeep:** 15 Food/day, 20 Coal/day | **Fuel Reserve:** 50 Coal
* **Howitzer Gun Tractor** (Ranged Vehicle) — **Cost:** 200 Wood, 200 Bricks, 200 Concrete, 400 Steel, 80 Gunpowder | **Cap:** -4 Pop, -40 Energy | **Upkeep:** 12 Food/day, 15 Coal/day, 3 Gunpowder/shell | **Fuel Reserve:** 50 Coal
* **Armoured Command Car** (Special Vehicle) — **Cost:** 250 Wood, 150 Bricks, 150 Concrete, 250 Steel, 30 Gunpowder | **Cap:** -4 Pop, -30 Energy | **Upkeep:** 12 Food/day, 10 Coal/day | **Fuel Reserve:** 50 Coal

---

## 5. Map Architecture & Terrain Generation (2D Top-Down)

### Dual-Layer View System

The map covers the British Isles (Ireland and Great Britain) using a two-tier 2D top-down camera architecture:

* **World View (Strategic Tier)**
  * **Grid Unit:** Uniform 5mi × 5mi hexagonal grid.
  * **Visual Display:** Strategic overview rendering overall Zone of Control (ZoC) networks, macro Fog of War, sector threat levels, regional resource totals, major transit corridors (Railways/Canals), macro elevation contours, and aggregated army/horde icons.
  * **Purpose:** Macro logistics, empire planning, and regional military movement.

* **Tactical View (Operational Tier)**
  * **Transition:** Smooth camera zoom from World View down to ground level.
  * **Visual Display:** High-resolution 2D top-down environment rendering individual buildings, animated industrial lines, distinct resource nodes, micro-infrastructure (roads/walls), individual combat units, and zombie hordes.
  * **Purpose:** Base layout, defense micro-management, tactical combat, and localized resource extraction.

---

### Logical Elevation System

Rather than using complex 3D terrain meshes, height is managed via discrete 2D integer flags (`height_level` 0 to 4) assigned to map coordinates:

* **Level 0 — Sea-level:** The lowest level possible, sea level should be applied everywhere the sea biome is present.
* **Level 1 — Lowland:** Standard baseline elevation. No vision or range modifiers.
* **Level 2 — Hill:** Minor elevated terrain.
  * **Combat Bonus:** +15% Weapon Firing Range and +15% Line of Sight (LoS) targeting Level 0 or 1.
  * **Movement:** Standard biome rules apply.
* **Level 3 — Highland:** Major elevated terrain.
  * **Combat Bonus:** +25% Weapon Firing Range and +25% Line of Sight (LoS) targeting Level 0, 1, or 2.
  * **LoS Block:** Occludes vision to lower elevation tiles directly behind it.
* **Level 4 — Mountain:** Extreme peak elevation.
  * **Passability:** **IMPASSABLE** for all ground units, vehicles, and zombies.
  * **LoS Block:** Completely opaque; blocks all Line of Sight and projectable vision across its boundary regardless of viewer elevation.

---

### Sub-Hex Granular Biomes

Biome boundaries operate completely independently of the 5mi hex grid:

* **Real Vector Boundaries:** Biomes (Farmland, Moorland, Highland, Wetland, Woodland, Heathland, Urban, Industrial, Waterway) are stored as a **continuous triangle mesh carrying the real OpenStreetMap polygon geometry** — a wood is wood-shaped, a river is a river-shaped ribbon, and neither is quantised to a sample grid nor cut off at a hex edge.
  * **This supersedes the splatmap plan earlier versions of this document specified, and the reason matters:** a weightmap is still a raster. Rasterising the source polygons is exactly what produced the visible square artefacts the user reported ("still obviously squares"), and no amount of blending at render time can recover a boundary that was destroyed at bake time. The boundary is now preserved as geometry from OSM all the way to the GPU.
  * Boundaries between biomes are currently **hard edges** — correct in shape, abrupt in appearance. Weighted multi-texture blending across them is **PLANNED**.
* **Multi-Biome Hexes:** A single 5mi hex tile can seamlessly blend multiple biomes (e.g., a Wetland valley transitioning into Highland ridges bordered by Woodland).
* **Coordinate-Based Modifiers:** Movement speed and terrain mechanics evaluate the exact sub-hex biome directly beneath a unit's current position, on a persistent 30m mechanical grid.
  * **Known divergence:** rendering reads the vector mesh, while the mechanical queries still read the 30m raster. The two can disagree near a boundary by up to the raster's own cell size. Moving mechanics onto the same vector data is **PLANNED**; until then the mesh is authoritative for what the player SEES and the raster for what the rules DO.
* **The sea** is drawn as its own layer beneath the landmass rather than as hexes — most of a UK+Ireland bounding box is water, and it carries no per-hex detail. It stays partly legible through Fog of War on the same "a coastline is public knowledge" principle the coastline outline already follows.

---

### Open-Source Data "Baking" Pipeline

Map generation uses real-world open geospatial data, pre-processed offline into game data by a deterministic geometry pipeline (`tools/geo_bake/`). No AI synthesis is involved — the output is a function of the input data and the tolerances below, and re-running it reproduces the same bytes.

#### Input Sources
* **Land Cover (Biomes):** **OpenStreetMap** `landuse` / `natural` / `waterway` vector geometry, read from Geofabrik `.osm.pbf` country extracts (Great Britain + Ireland). OSM is used rather than CORINE because it carries the waterway network the game needs as real vector lines, at a resolution that survives being rendered at true scale.
* **Topography (Elevation):** **AWS/Mapzen Terrain Tiles** (Terrarium RGB encoding), sampled and thresholded into the 0–4 integer `height_level` masks §5 defines. A DEM is a continuous field already sampled on a grid at source, so it stays raster — only categorical boundaries suffer from rasterisation.
* **Coastline / Landmass:** **Natural Earth** 10m Admin-0 (GBR + IRL), which decides which hexes are land and which are OCEAN.
* **Geology (Resource Nodes):** BGS / GSI spatial data — **PLANNED, not implemented.** Resource placement is not currently data-driven.

#### Baking Process
1. **Land-cover arrangement (per 4,096-world-unit chunk).** Union the raw OSM features per class, then simplify the merged blob — in that order, because simplifying each feature first destroys anything near the tolerance. Node the entire boundary network into a single planar arrangement, polygonise it into faces, label each face by its highest-priority class, and constrained-Delaunay-triangulate. Building the partition as one arrangement rather than by differencing class against class is what guarantees adjacent faces share bit-identical vertices, so no seams or T-junctions exist to crack open under displaced relief later.
2. **Waterways are lines, not areas.** A river or canal centreline is simplified and smoothed *before* being buffered to a real-world width, so the ribbon comes out at constant width along a rounded course. Buffering first and simplifying after inflates the ribbon, pinches it below the mechanical sub-cell size, and breaks the bridge-crossing barrier that width floor exists to guarantee.
3. **Elevation raster.** Terrarium samples → discrete `height_level` masks, plus the highland/escarpment override applied on top of the land-cover class rather than stored in it.
4. **Hex aggregation.** Majority-vote a single dominant biome per 5mi hex to drive the World View's strategic tile, alongside regional resource potentials and base travel speeds.

Chunks containing no land hex are not baked at all — most of a UK+Ireland bounding box is open sea, and a chunk with no land-cover evidence would otherwise fill with a default biome and paint over the sea.

---

## 6. Vision, Sound, Light & Zombie AI Systems

### Line of Sight (LoS) & Elevation Rules

Vision uses a **2D Symmetric Shadowcasting** algorithm calculated from the unit's tile origin out to its maximum Vision Radius.

#### Elevation Interaction
* **Vision Advantage (+1 Tile Radius per level):** Units on a higher `height_level` gain +1 tile vision radius per elevation level above the target tile. (Note: Percentage range bonuses apply specifically to weapon firing distances as defined in Sec 5).
* **Occlusion Rules:**
  * **Level 4 (Mountain):** Completely opaque. Blocks all LoS, rays, and vision fields regardless of viewer elevation.
  * **Level N Obstacle:** Occludes all tiles behind it that have an elevation lower than Level N, unless the viewer is on an elevation higher than Level N.
* **Biome Vision Modifiers:**
  * **Woodland:** 50% Vision Penetration. Vision range looking into or through Woodland is reduced by 50%.
  * **Searchlight / High Ground Synergy:** Ranged units targeting enemies on lower elevations or inside illuminated zones gain +15% Accuracy.

---

### Light & Illumination System

The game features a dynamic ambient light state (Day / Dusk / Night cycle) overlaid with local point/cone light emitters.

#### Dynamic Ambient Light Levels
* **Day (100% Ambient):** Standard vision ranges apply for all units.
* **Dusk/Dawn (50% Ambient):** Human vision range reduced by 25%. Zombie detection range unchanged.
* **Night (15% Ambient):** Human vision range reduced by 60% without light sources. Zombie detection range reduced by 30%.

#### Light Source Emitters
* **Radial Emitters (Lanterns, Fires):** Emits a 360-degree light pool (Radius: 3 to 8 tiles).
* **Cone Emitters (Searchlights):** Emits a 60-degree forward cone (Radius: 15 tiles). Uncovers fog of war and illuminates units within the cone.
* **Transient Emitters (Muzzle Flashes, Flares, Explosions):** Brief light pulses lasting 0.1 to 2.0 seconds. 

#### Combat & Aggro Modifiers in Light
* **Target Acquisition:** Ranged units cannot lock onto targets in pitch darkness unless revealed by a light source or muzzle flash.
* **Light Attraction:** Idle zombies within 12 tiles of a static/moving light source at night will enter *Investigate* state and drift toward the light origin.

---

### Sound & Acoustic Propagation System

Sound travels as dynamic wave impulses across the tile grid, triggering Zombie AI reaction vectors.

#### Sound Generation & Decibel (dB) Ratings
Each action emits an acoustic impulse with a specific base radius (`R_sound` in tiles):

| Action Type | Base Sound Radius (Tiles) | Primary Attractors |
| :--- | :--- | :--- |
| **Melee / Bow Strike** | 1–2 | Immediate adjacent zombies only |
| **Pistol / Rifle Shot** | 10–15 | Local patrol groups |
| **Maxim Machine Gun** | 25 | Regional sector zombies |
| **Steam Vehicle Engine** | 12 (Continuous) | Pulls wandering zombies into transit corridors |
| **Artillery / Explosions** | 40+ | Triggers sector-wide horde aggregations |
| **Building Construction** | 8 | Local wandering threat |

#### Sound Attenuation Rules
* **Open Terrain / Waterways:** Sound travels at 100% nominal distance.
* **Woodland / Structures / Walls:** Dampens sound propagation by -2 tiles per obstacle tile traversed.
* **Elevation Barriers (Level 2/3):** Level 4 Mountains block sound completely. Level 2/3 Highlands reduce sound propagation radius by 50%.

---

### Zombie Perception & AI State Machine

Zombies process sensory inputs through a prioritized 4-state behavioral logic tree:

* **State 1: Idle / Wander**
  * **Base Behavior:** Wanders randomly at 30% movement speed. Evaluates perception triggers every 1.0 second.
  * **Transitions:**
    * **To Investigate:** Triggered upon detecting a sound impulse or seeing an illuminated tile outside direct Line of Sight (LoS).
    * **To Aggro / Chase:** Triggered immediately upon acquiring direct LoS to a target or hearing a high-volume sound (`R_sound` <= 3 tiles).

* **State 2: Investigate (Suspicious)**
  * **Base Behavior:** Pathfinds directly toward the target Acoustic Centroid or Light Source Coordinate at 60% movement speed.
  * **Transitions:**
    * **To Aggro / Chase:** Triggered immediately upon acquiring direct LoS to a valid target unit.
    * **To Idle / Wander:** Triggered if the zombie reaches the source coordinate and finds no active target.

* **State 3: Aggro / Chase**
  * **Base Behavior:** Locks onto a specific target unit and pathfinds along the shortest route at 100% movement speed.
  * **Transitions:**
    * **To Swarm Vector:** Automatically triggers every 1.0 second while active in combat.
    * **To Investigate:** Triggered if target unit is lost in Fog of War / darkness for > 5 seconds.

* **State 4: Swarm Vector (Horde Cascading)**
  * **Base Behavior:** Broadcasts a 3-tile radial Pheromone Pulse every 1.0 second.
  * **Cascade Attenuation Rules:**
    * **Line-of-Sight Check:** Pulse only triggers nearby zombies if unblocked by Level 4 Mountain terrain or solid fortifications.
    * **Hop Depth Limit:** Pheromone pulse cascade depth is capped at **3 max hops** (originating zombie -> Hop 1 -> Hop 2 -> Hop 3) to prevent runaway map-wide loops.
    * **Cooldown:** Each zombie has a 5.0-second cooldown on triggering or re-broadcasting a Swarm Vector pulse.

---

### Technical Implementation & Data Structures

To handle thousands of active zombies and pathing/perception calls at high performance:

#### Spatial Hash Grid & Bitmask Layers
* **Spatial Partitioning:** The tactical view map is divided into 16 x 16 tile spatial hash buckets (160m × 160m) to instantly retrieve units and sound events within perception queries.
* **Light & Sound Grid (Bitfield Matrix):**
  * Light and Noise levels are calculated on a coarse grid overlaid on the tile map.
  * `LightMap[x][y]` stores a single `uint8` illumination value (0-255).
  * `SoundQueue` processes noise events ring-by-ring using a ring-buffer event list updated on tick intervals rather than continuous per-frame propagation.

#### Zombie AI Tick Throttling
To optimize CPU usage during large horde events:
* **Distance-Based Ticking:**
  * **Off-screen / Far (>50 tiles from player):** AI state evaluated once every 2.0s.
  * **Mid-range (20-50 tiles):** AI state evaluated once every 0.5s.
  * **Combat Range (<20 tiles):** AI state evaluated every frame (16ms / 60Hz). Fits within 1-2 spatial hash bucket queries.

---

## 7. Technical Glossary & Spatial Specifications

### Spatial Scale & Unit Grid Hierarchy

To eliminate ambiguity between macro strategy and micro tactics, spatial dimensions are locked to the following real-world equivalent metrics:

* **Strategic Hex (World View Cell):**
  * **Dimensions:** Regular hexagon with a 5 mi width (flat-to-flat distance).
  * **Bounding Area:** ~21.65 mi²
  * **Purpose:** Primary unit for regional Zone of Control (ZoC), empire pathfinding, resource distribution, and macro fog of war.

* **Tactical Tile (Operational View Cell):**
  * **Dimensions:** Uniform 10 m x 10 m square grid cell.
  * **Scale Conversion:** 1 Strategic Hex ≈ 500 x 500 Tactical Tiles in bounding area.
  * **Movement Velocity:** Unit movement rates use floating-point sub-tile velocities (tiles/sec) rather than integer steps (e.g., standard infantry walking at ~5 mi/h translates to ~0.22 tiles/sec) to ensure smooth interpolation.
  * **Purpose:** Fundamental atomic unit for pathfinding, building placement, weapon ranges, collision detection, and LoS shadowcasting.

---

### Core Technical Definitions

* **Tile:** The atomic 10 m x 10 m square grid coordinate (x, y) in Tactical View. All unit speeds, vision radii, explosion effects, and building footprints are measured in tiles.

* **Splatmap / Biome Weightmap:** A resolution-independent 2D texture array mapping normalized float values (0.0 to 1.0) for each biome type per coordinate. Used to render smooth visual transitions and compute exact weighted movement penalties at sub-tile resolution.

* **Logical Height Level (`height_level`):** An integer byte flag (`uint8`: 0, 1, 2, 3, or 4) assigned per 10 m x 10 m tile. Controls vision occlusion, range bonuses, and passability without requiring 3D mesh height calculations.

* **Zone of Control (ZoC):** A strategic and tactical supply aura centered on key infrastructure. Graphically represented on the World View as a 5 mi x 5 mi circle area. Unlocks local building placement and seamlessly connects resources to global logistics pools.

* **Symmetric Shadowcasting:** A grid-based 2D Line of Sight (LoS) algorithm that casts light rays outward from a tile center to determine visible vs. occluded tiles in O(N) time, where N is the number of tiles in the vision radius.

* **Acoustic Impulse (`R_sound`):** A temporary radial event generated at an origin tile coordinate upon firing a weapon, starting an engine, or triggering an explosion. Measured in Tile radius, decaying outward frame-by-frame or tick-by-tick.

* **Acoustic Centroid:** The calculated focal coordinate (x, y) of noise propagation that a zombie in the *Investigate* state pathfinds towards.

* **Spatial Hash Bucket:** A 16 x 16 Tile grid partition (160 m x 160 m) used by the engine to chunk entity spatial data, allowing rapid proximity queries without iterating over every unit on the map.

* **Pheromone Pulse:** A recurring 3-Tile radial event broadcasted by active *Aggro* zombies that forces adjacent *Idle* or *Investigating* zombies to acquire the target vector (bounded by a 3-hop cascade depth limit and 5s cooldown).