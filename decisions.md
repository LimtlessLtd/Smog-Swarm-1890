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

## 2026-08-28 — Infestation core

Settled while building `InfestationManager`. `design_doc.md` §2.1 is unchanged;
these record where the implementation had to answer something the spec left
open, and what was measured before it did.

**D37. A hex's `zombie_count` is its stored resident count PLUS whatever hordes
stand on it, read live.** Not one mirrored ledger.
*Why:* `Horde` is already a saved `Resource` owned by `HordeManager`, so a
second per-hex copy of the same population is the double-source-of-truth D5
deletes the diffusion PDE to avoid — and keeping it in sync means chasing four
separate traps: the combat kill path emits no signal at all, merge and split
both emit `horde_size_changed` while conserving the total,
`CombatCoordinator._knock_back()` moves a horde without emitting `horde_moved`,
and `HordeManager.load_save_state()` replaces every horde silently. A live read
cannot go stale.
*What falls out for free:* killing a horde on a hex lowers that hex's
infestation (D8's only suppression), a horde crossing a Cleared hex re-infests
it while it is there (§2.1's re-infestation), and an export conserves exactly —
the count leaves `_resident` and arrives as a `Horde` on the same hex.

**D38. Export is rate-capped, not one-shot, and the 75% floor is the hard
constraint under it.** `MAX_EXPORT_FRACTION_PER_DAY = 0.025`.
*Why, measured:* §2.1's "breed to 100, export down to 75, breed again" taken
literally ships the whole 25% in one day. On the real map
(`scripts/test/diagnose_infestation_pressure.gd`, 60 days, no player action)
that is **37,582 zombies on day one**, out of a Manchester suburb six hexes from
the player's Town Hall, against a colony holding a Town Hall, a Lumber Yard and
one farm. Capping the rate instead gives **3,758 on day one and 61,459 over 60
days across 7 new hordes** — the same mechanism, an order of magnitude less
lethal on the first morning, and a horde that still grows to ~37,000 if the
player never engages it.
*Why this is a rate and not a redesign:* §2.1 calls the spawn figure "a
balancing number, not a design decision"; this is the same kind of number on the
other side of the same pump. The mechanism it specifies — breed, ship, never
below the floor, only killing goes lower — is untouched.

**D39. A Hive Core farther than 8 hexes from a player building breeds but does
not ship, and at most one hex ships per day.**
*Why:* D7 seeds ring four outward at 100%, which is **4,666 of the map's 4,692
land hexes** on day one — every one an export candidate. The bound is D13's
applied to hordes instead of entities, and the same one PR #90 already applied
to ambient spawns: a horde nobody could ever meet is not simulated. Distance is
measured to a real player BUILDING, not to any `is_settlement` hex, because
Birmingham and London are settlement hexes in the map data from the first frame
and the player holds neither.
*Accepted consequence:* the count on a distant Hive Core is real and rises, but
nothing comes out of it until the player gets within reach — which is what makes
expanding toward London a decision rather than a formality.

**D40. Build rights are gated; ZoC severance is not, and will not be until
§2.2.** `BuildingManager.get_infestation_placement_error()` and
`WallManager._infestation_error()` implement §2.1's Build Rights column;
"Total Severance", the Contested stockpile split and the Fringe -25% logistics
efficiency are deliberately absent.
*Why:* there is no logistics throughput number anywhere in the codebase to
reduce — `SupplyLineCatalog.get_speed_multiplier()` is unit MOVEMENT speed, and
`BuildingCatalog` states outright that no throughput system exists — and the
stockpile split needs per-settlement stockpiles, which `backlog.md` insists is
its own PR. Shipping a -25% that multiplies nothing would be a rule nobody can
observe.
*Also settled:* "Defensive Tier" is a new `BuildingDefinition.is_defensive`
flag, not a `BuildingCategory` test. The category enum splits the four named
structures across three categories (Watchtower and Garrison HOUSING_CIVIL,
Supply Dump INDUSTRY_EXTRACTION, Search Light the sole DEFENSE_WORKS member) and
cannot express walls at all.

**D41. `TerritoryController` is not subsumed and does not derive from the band.**
*Why:* it answers a different question with a different trigger — "did the
player lose a building here to a horde", an event, a boolean, recaptured when no
horde stands there — where infestation is a population ratio that starts at 0%
on the player's hex and falls when they kill. Merging them would be a
save-format change for no gain. *Accepted cost:* two per-hex notions of
"trouble" coexist, and both class doc comments now say which is which so a third
reader does not have to guess.

---

## 2026-08-28 — Baking population capacity

Settled while building `tools/geo_bake/bake_population.py`. Each entry is a
measurement, not a preference; the numbers are reproduced in the bake's own
docstrings so they are readable next to the code they justify.

**D33. Wikidata's 1890s coverage is a few hundred items, not "cities and towns".**
D3's source order is kept; its description of tier 1 is not.
*Measured 2026-08-28,* items in the GB+Ireland bbox with a P1082 population dated to
a census year: 1881 → 377, 1891 → 378, 1901 → 407 (415 distinct). The largest 1891
rows are aggregates — United Kingdom 37,802,400, London 5,565,856, Wales 1,771,451,
Birmingham 478,000 — and the settlement-level rows are dominated by one bulk import of
Isle of Ely / Cambridgeshire parishes. `wd:Q18125` (Manchester) has population
statements for 2011, 2014, 2017 and 2018 and nothing earlier; the same is true of
Liverpool, Leeds, Sheffield, Glasgow, Edinburgh, Bristol, Newcastle and Nottingham.
202 rows join to an OSM place node by QID, which is 0.5% of the 40,398 settlements.
*Consequence:* tier 1 is a correction layer, not the source. Tiers 2 and 3 carry the
map — 2,296 settlements from an OSM `population` tag, 37,900 from the median tagged
population of their place kind.
*Rejected:* dropping Wikidata entirely. Where it has a real 1891 figure — London,
Birmingham, Aberdeen — that figure beats any scaled modern one, and 8x outliers like
Bexhill-on-Sea are exactly the places a national trend gets wrong.

**D34. One national factor converts modern population to 1891, derived from the census
total rather than chosen.** `(1891 census − what tier 1 already contributes) ÷ the
modern subtotal`.
*Why:* tiers 2 and 3 are present-day population and the game is January 1890.
*Measured:* the factor comes out at **0.5105**, against a median modern/1891 ratio of
**1.94** (i.e. 0.515 inverted) over the 80 settlements where a real 1891 figure and a
modern OSM tag are both known. Two independent derivations agreeing to 1% is the
evidence that this is a real historical ratio and not a fudge to hit a target.
*Accepted consequence:* a town that moved against the national trend is wrong by
however far it diverged — Bexhill-on-Sea is 8.3x its 1891 self and is scaled as 1.9x.
*Also settled here:* `place=suburb`/`borough`/`neighbourhood`/`quarter` are excluded
outright, because a suburb sits inside a settlement whose own node already carries the
whole population. Filling the 6,069 untagged suburb nodes from the tagged ones' median
added a phantom 47 million people to a 37 million country — that error is what made the
first cut's factor 0.2855 and crushed every real city.

**D35. The three named cities are placed on their calibration-table hex, not on their
projected position.** Everything else is placed by `geo_projection`'s affine.
*Why:* the affine's residual at Manchester is 1,201 world units, which is 1.6 hex ROWS.
Projecting real Manchester put 253,000 people on an empty moorland hex two rows north
and left the game's own four Manchester hexes — the player's starting settlement — with
84,000 between them. `CALIBRATION_POINTS`' own `q, r` column already states where this
game puts each of those real places, so it is a better key than the fit it feeds.
*Why not for everything:* the other 40,395 settlements have no named footprint to snap
to, and the land-cover raster they must agree with is baked through the same affine —
so for them the projection is the correct answer, residual and all.

**D36. `geo_projection.CALIBRATION_POINTS` has no single bad row to fix; re-fitting it
is a `[design]` call that regenerates the map.** The backlog item's premise is wrong
and it is retagged rather than taken.
*Measured 2026-08-28:*
- Both sides of the "Midlands Farmland (Warwick)" row are faithful. Its lon/lat is
  Warwick (52.2823, −1.5849) and its `q, r` is `Vector2i(80, 131)  # Warwickshire`
  verbatim from `BritishGeographyData._build_features()`.
- It is the worst row but not a different kind of row. Leave-one-out residuals:
  Warwick 3,539, Pennines north 3,111, The Fens 2,541, Mersey 1,976, Oldham 1,647,
  Southend 1,491, Sheppey 1,448. RMS over all 21 is 1,265 world units (~2.5 hex radii).
- The residual is not a projection error. A 12-parameter quadratic reduces RMS only
  1,265 → 1,188; equirectangular-with-cos(lat) and Mercator-y are both slightly worse.
  There is no better model to find — the anchors themselves are noisy.
- Dropping the row does not help and is not free: max city residual improves 1,201 →
  1,075, while the map moves by up to **780 world units (1.5 hexes)** across GB, which
  would need every baked product re-run against it.
- Fitting only the 3 web-verified city anchors (an exact 6-parameter interpolation)
  moves the map by 23 hexes, which proves those three are not mutually consistent with
  the other 18 — 18 hand-drawn region blobs dominate the least squares.
*Why it is `[design]`:* any re-fit shifts land-cover, relief, fine tiles, the vector
mesh and fine elevation relative to `_LAND_RLE`'s coastline, so it regenerates the map.
That is the user's call for the same reason D32's mountain reclassification is.
*Mitigation shipped instead:* D35 above, which fixes the three cities that had a
gameplay-visible consequence.

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
*Premise corrected 2026-08-28 when the bake was built — see D33.* The source ORDER
stands; "good coverage for cities and towns" does not. Wikidata carries a dated 1891
population for 378 items in the whole GB+Ireland bbox, and none at all before 2010 for
Manchester, Liverpool, Leeds, Sheffield, Glasgow, Edinburgh, Bristol, Newcastle or
Nottingham.

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
