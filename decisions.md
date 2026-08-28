# Decision Record

Architectural and design calls that are **settled**. Each entry says what was decided
and why, so it isn't re-derived or re-litigated later.

Rules for this file:
- One entry per decision. Newest section at the top.
- Record the *reason*, not the narrative. Quote the user verbatim where their words
  settled it (`CLAUDE.md` §2).
- If a decision is later reversed, edit the entry in place and note what changed —
  don't leave two contradictory records.
- Consequences that were knowingly accepted belong here too. A decision without its
  cost is half a record.

---

## 2026-08-27 — Zombie population & infestation model

Settled across a 30-question design review. Full spec in `design_doc.md` §2.1.

**D1. Infestation is derived, never stored.** `zombie_count / total_zombie_pop * 100`.
One mutable number per hex; everything else computed. Killing zombies lowers
infestation as arithmetic rather than as a rule. Replaces an earlier draft where
infestation was its own stored scalar.
*Why:* one source of truth, no drift, nothing extra in the save. Same
derived-never-stored pattern as `UnitUpgrades.gd`.

**D2. `is_cleared` is `infestation < 5.0`, derived.** Not `== 0.0`, and not a stored
boolean.
*Why, verbatim:* "I was just trying to be a bit lenient so players could still build
things even if theyre getting attacked by zombies/clearing out zombies etc."

**D3. Capacity is baked from real 1890s population.** Wikidata (CC0) → OSM `place`
tags (ODbL, already in the pipeline) → floor of 1,000.
*Why:* capacity **is** the difficulty curve, so real history gates the map with no
hand-authored region locks, and Manchester → London ramps automatically.
*Rejected:* Great Britain Historical Database parish statistics — copyright
Southall/Gregory/Ell/Gatley via UK Data Service, not downloadable from its own
repository, silent on commercial use.
*Accepted consequence:* some regions are effectively closed until very late, decided
by population data rather than by design.

**D4. The source term is spawning, gated at >75%.** A hex above the Hive Core
threshold breeds at a flat percentage of its own capacity per day; at 100% it exports
roaming hordes but never drops itself below 75%. Only player killing goes lower.
*Why:* the first draft's propagation model was pure diffusion with no source, so total
infestation was non-increasing and the whole map decayed to zero on its own. This
makes a self-regulating pump — breed to 100, export to 75, repeat — so a city left
alone ships hordes indefinitely and a city ground down stops.

**D5. The diffusion PDE is deleted. Spread is emergent.** Zombies are entities that
walk, so infestation moves because they moved.
*Why:* keeping both would be two systems modelling the same phenomenon — the
double-source-of-truth problem `CLAUDE.md` exists to prevent.

**D6. Zombies ignore all infrastructure speed modifiers.**
*Why, verbatim:* "zombies shouldn't travel faster over roads or rails or canals
because they can't drive or take the train lol"
*Consequence, deliberately taken:* infrastructure becomes a pure asymmetric advantage
— the player moves fast on rail, hordes don't — which makes rail-borne response a real
strategy and gives hordes a predictable cross-country travel time, so early warning
means something.
*Implementation trap, corrected when it was actually built (2026-08-27):* the note here
used to say the modifiers are read by three neighbour-expansion loops. They are not.
Infrastructure reaches a mover through TWO mechanisms: `get_step_cost()` decides which
way it goes, `get_movement_speed_multiplier()` decides how fast it moves. Only the pair
is the rule — a horde denied the routing discount alone still sprints down any road its
drift happens to cross, and that second site is in `HordeManager._movement_speed()`,
which the old note did not mention. `_replan_cheap()` needed no change at all: it
applies no cost or speed modifier, only `is_water_crossing_blocked()`.
*Bridges are NOT covered by this.* A Bridge is passability, not speed: a zombie crosses
one, and crosses it at walking pace. The tempting implementation — pass a null
`LogisticsNetwork` for hordes — removes bridges too, since that is the same object
`is_water_crossing_blocked()` consults, and would silently make every river in the game
uncrossable for zombies. Hence an explicit `uses_infrastructure` flag rather than
withholding the network.

**D7. Worldgen seeds 0 / 25 / 50 / 75 / 100% in rings from the start hex.**
*Why:* "zombies everywhere except the start hex" taken literally would put six Hive
Core hexes adjacent to the player on day one. Ring three sits exactly at the spawn
threshold so the bleed and export mechanics are visible near home from the start.

**D8. Killing is the only suppression.** All passive suppression rates
(Watchtower +5/day, Garrison +20/day, Searchlight +10/day) and the "Phase 2: Border
Suppression" stage are deleted.
*Why, verbatim:* "Zombies create infestation. Suppressing infestion means getting rid
of zombies."
*Accepted consequence:* holding ground costs a standing garrison with real Food and
Population upkeep, which makes overextension self-limiting — and creates a late-game
management load that is acknowledged and deliberately unsolved (`vision.md` P3).

**D9. Re-infestation is real; build rights are checked at placement only.** Standing
buildings are destroyed by zombies attacking them, never by the ratio crossing 5%.
*Why:* otherwise one horde wandering past bricks an industrial hex without a fight.

**D10. Attraction build order: noise → light → blood.** Noise attraction already
works; only emission needs replacing. Light gets a crude `lit_at_night` version before
full §6 line-of-sight. Blood is deferred and undesigned.

**D11. Buildings can be switched off** — no production, no upkeep, no noise, no light,
with a restart delay proportional to tier.
*Why:* free instant toggling makes going dark a no-brainer spammed on sight. A restart
cost makes it a decision, and banking a Victorian furnace is a real operation.

---

## 2026-08-27 — Simulation scale

**D12. Every zombie is a real entity (not an abstract stock).**
*Why, verbatim:* "I want this to truly be TABs on an absolutely massive scale."

**D13. Entity instantiation is bounded by observation, counts stay literal.** A hex is
live if it holds the camera, neighbours the camera hex, or contains player units or
buildings; live hexes instantiate up to a shared ~60,000 budget, nearest the observer
first. Outside, counts still breed, bleed and export as numbers.
*Why:* measured, not argued — `scripts/test/bench_zombie_scale.gd` puts the hard
ceiling at 250,000 packed movers using the *entire* frame for movement alone, so ~60k
is the realistic budget. A hex is 5 mi x 5 mi; the player can never observe enough
ground to detect the boundary. In London this yields ~60k real zombies with ~1.84M
behind them streaming in as you kill — the endless-tide feel falls out of the design.

**D14. Two classes: `Horde` (strategic aggregate, saved) and a new packed tactical
layer.** A horde dissolves into entities on entering a live hex and re-condenses on
exit, conserving its count.
*Why:* `Array[Resource]` — what `Horde` is today — caps at 50,000 in the benchmark.
Refactoring `Horde` into packed arrays would drag save-compat and `CombatCoordinator`
along for no gain. Two responsibilities, two classes (`CLAUDE.md` §1).

**D15. Tactical zombie positions ARE saved**, as packed float32 (~500 KB for the whole
live set).
*Why:* not size — correctness. Saving mid-siege and reloading must not teleport 60,000
attackers into fresh positions, which reads as broken and is trivially save-scummable.
Affordable only because of D14's packed layout; per-Resource would have been 20x.

---

## 2026-08-27 — Walls and bleed

**D16. Walls block passive bleed proportionally** — 60% border coverage = 40% bleed.
Chosen over binary sealed/unsealed.
*Why, verbatim:* "do percentage based I think it's more fun".

**D17. Walls do NOT stop hordes.** A horde still sieges, exactly as
`HordeManager._siege_wall()` already does.
*Why:* 12,000 Wood for permanent immunity would make "wall in and never fight" beat
the game, contradicting P1 and P2. Walls buy time, never safety — matching *They Are
Billions*. Division of labour: walls stop the seep, units stop the hordes.

**D18. A gate is a wall friendly units can pass through, and nothing else.** Blocks
bleed and sieges identically.
*Why, verbatim:* "for all intents and purposes walls and gates are the same, the only
difference is friendly units can pass through gates."

**D19. Coverage is measured at sub-hex resolution and cached per hex-pair**, extending
`SubHexPortalGraph.has_any_crossing()`, invalidated on `WallManager`'s place / remove /
breach / repair signals.
*Why:* proportional coverage can't early-out, so it walks the whole edge — the exact
cost pattern `CLAUDE.md` §3 warns about. Walls change rarely and already emit a signal
for all four mutations, so caching makes it roughly as cheap as the binary version.

**D20. Walls stay freehand; hex-border snapping is a placement aid only.**
*Why:* freehand chain-of-pieces was itself a fix for user-reported behaviour
(`WallSegment.gd` quotes it). But drawing ~50 pieces along an invisible edge accurately
enough to seal it is pixel-hunting. Snap when a drawn line runs near a border, with a
modifier key to refuse. No data-model change.
*Reference figure:* one hex edge = 512 world units ≈ 4,992 m; a wall piece caps at
100 m. Sealing one border ≈ 50 pieces = 2,000 Wood; all six ≈ 300 pieces = 12,000 Wood.

---

## 2026-08-27 — Logistics

**D21. One Town Hall = one settlement = one stockpile.** Not per-hex.
*Why:* `is_settlement` is a per-hex flag and cities span many hexes (Manchester 4,
London 12), which would shatter one city into a dozen competing pools. Also makes the
existing Town Hall founding feature load-bearing: founding a second settlement is
where the logistics problem begins.
*Scope warning:* the most invasive change in the project — `ResourceManager`, every
producer and consumer, every affordability check, every UI counter, and saves. Own PR,
nothing else in it. Prerequisite for §2.1's Contested band.

**D22. Links pool stockpiles, throughput-limited by the weakest link.** No simulated
goods entities.
*Why:* delivers "concrete and visible" — you see the line, its capacity, and the
bottleneck — without building a train simulation. Full physical transport is a later
upgrade on these numbers, not a rewrite.

**D23. Throughput is aggregate tonnage per day, not per-resource.**
*Why:* one number reads as a bottleneck at a glance; fifteen per-resource limits are
fifteen invisible numbers and no decisions. A shortage then forces a real choice about
what to ship today.

**D24. `SupplyLineSegment` gets real geometry**, reusing
`WallManager.place_wall_line()`'s drawn-line-to-pieces path.
*Why:* it has no world-space points today, so there is nowhere to put a curve. Walls
already solved chopping, per-piece state and spatial indexing — don't write it twice.
Closes todo.md's "supply lines still whole-edge" architecture-debt item.

**D25. Terminals are required, one at each end.** Railway stations, canal docks, road
depots — all three net-new.
*Why:* a railway with no station is track trains can't stop at. Gives the player a
diagnosable failure mode rather than a silent tax.

**D26. Canals are flat and climb only through locks.**
*Why:* the most characteristically Victorian mechanic available, and it turns the
elevation bake into visible gameplay. Gives the three infrastructure types genuinely
different placement puzzles: rail wants gentle gradients, canals want locks, roads go
anywhere.

**D27. A fine elevation bake is a hard prerequisite** for the ±1-level gradient rule.
The mechanical raster is ~3,510 m/px — under one sample per hex edge.
*Why it's worth doing now:* `fetch_terrarium.py` already pulls the tiles and
`bake_fine_relief.py` already reads them at 30 m, discarding the values. **The same
bake unblocks §6 line-of-sight and vector-terrain epic phase 4.** One job, three
features.

**D28. Lines are severed by infestation (>25%), not by attack.**
*Why:* needs no deliberate-target AI (`HordeManager`'s header lists building-siege
targeting as unbuilt), one rule serves two systems, and the failure is legible — the
line dies exactly where the map goes red. "Protect your supply lines" becomes the
garrison-and-wall game rather than a parallel mechanic.

**D29. An isolated settlement stagnates; it does not die.**
*Why:* death spirals from a severed line would punish the player for a horde wandering
across a road while they looked elsewhere — the same unfairness D9 exists to avoid.

---

## 2026-08-27 — Process

**D30. `vision.md` is the check every backlog item passes**, and `design_doc.md`
remains the numbers spec. Docs split into `backlog.md` (what's next),
`decisions.md` (this file), and `devlog/` (history).
*Why:* `todo.md` was 203 KB doing six jobs at once — spec addendum, roadmap, dev log,
defect tracker, ADR, and design rationale — so answering "what should I work on" cost
~50k tokens before opening a single `.gd` file, and its own roadmap section carried a
warning not to let it drift while being nine days stale.

---

## 2026-08-27 — Fine elevation

**D31. Fine elevation ships as Terrarium RGB with the fractional channel zeroed**,
in per-hex 333x333 tiles beside the relief tiles, not as a new format.
*Why:* the coarse `elevation.png` is already Terrarium-packed and already has two
decoders in GDScript (`RealTerrainSampler.sample_at()`,
`ReliefImageBuilder._decode_elevation_metres()`), so reusing the packing means no
third one. Terrarium's blue channel is 1/256 m of precision that nothing here wants —
the canal rule is "one elevation level", line-of-sight is metres over kilometres — and
it is high-entropy noise no compressor shrinks. Zeroing it costs 1 m of precision and
about a third of the bake. *Measured:* 106 MB (26.8 KB/tile) and 19.6 min for the 3,876-hex corridor,
entirely from tiles already in `cache/terrarium`; round-trip error is 0.5 m worst case,
which is rounding and nothing else.

**D32. The bake does NOT change how hexes are classified as mountains.**
`SubHexTerrainQuery.elevation_metres()` is the new fine read path;
`sample()["elevation_m"]` stays on the coarse raster.
*Why:* `RealTerrainSampler.majority_biome()` takes the MAX elevation of a 5x5 grid,
and its own comment records that this is only safe because the coarse raster holds 4x4
identical blocks — the max means "some substantial upland part of this hex is above the
line", not a point maximum, and it says outright that this stops being true if the
source gets finer. Pointing `_sample_fine()` at the new tiles is a one-line change that
would silently reclassify mountains, re-carve `MountainPassCarver`'s passes and alter
passability across the map. *Consequence, accepted:* two elevation answers coexist
until that item is taken, and the finer one is opt-in.
