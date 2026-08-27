# Backlog

Everything not yet built. **Read the index; grep the detail.** Full detail for
inherited items is preserved below the index under "Detail (inherited from todo.md)".

**Tags** — what it takes to know an item is done:
- `[gated]` — a script or test can verify it. **These are the only items an unattended
  loop may take.**
- `[visual]` — only a render or screenshot can verify it. Human or playtest agent.
- `[design]` — needs a user decision before any code.

**Sections** — from `vision.md` §5's three checks. An item fails check 3 (solves a
problem that only exists after the core loop works) → Deferred, however well specified.

---

## Now — the core loop (P1, P2)

Everything here traces to `design_doc.md` §2.1/§2.2 and `decisions.md` D1-D29. Rough
dependency order.

- [ ] `[gated]` **Fine elevation bake.** 30 m elevation values from the Terrarium
  tiles `fetch_terrarium.py` already pulls and `bake_fine_relief.py` already reads and
  discards. Current mechanical raster is ~3,510 m/px — under one sample per hex edge.
  **Unblocks three things**: §6 line-of-sight, vector-terrain epic phase 4, and §2.2's
  canal/rail gradient rules. Long-running bake — start it early. (D27)
- [ ] `[gated]` **Fix `geo_projection.CALIBRATION_POINTS`.** At least one bad row.
  Promoted from polish: population capacity is baked *through* this projection, so a
  bad row misplaces a city's entire zombie population. Detail below.
- [ ] `[gated]` **Bake `total_zombie_pop` per hex.** Wikidata historical population
  (CC0) → OSM `place` tags (ODbL) → floor 1,000. Verify Wikidata coverage at bake
  time; it is good for cities and towns, patchy for villages. (D3)
- [ ] `[gated]` **Infestation core.** `zombie_count` per hex; `infestation` and
  `is_cleared` derived. Band states, >75% spawn at flat %-of-capacity/day, 100% export
  with a 75% floor, worldgen rings 0/25/50/75/100. `infestation` appears nowhere in
  the code today. (D1, D2, D4, D7, D8)
- [ ] `[gated]` **Zombies ignore infrastructure modifiers** in all three
  neighbour-expansion loops — `find_path()`, `HordeFlowField._build_field()`, and
  `HordeManager._replan_cheap()`. The third goes through neither real search and is
  the one missed last time. (D6)
- [ ] `[gated]` **Tactical zombie layer + live-hex LOD.** New packed-array class,
  separate from `Horde`. Live hex = camera hex + 6 neighbours + any hex with player
  units/buildings, ~60,000 global budget, nearest-observer-first. Horde dissolves on
  entry, re-condenses on exit. Positions saved as packed float32. Benchmark:
  `scripts/test/bench_zombie_scale.gd`. (D12-D15)
- [ ] `[gated]` **Evict `SubHexTerrainQuery._cache`.** Unbounded, static,
  String-keyed, never evicted. Detail below — but it moves from "no urgency" to Now,
  because the live-hex system fans out sub-hex queries far harder than anything that
  has run against it so far. Benchmark before and after
  (`scripts/test/bench_portal_blocking.gd` is the template).
- [ ] `[gated]` **Buildings can be switched off.** No production, no upkeep, no noise,
  no light; restart delay proportional to tier. The most direct expression of P2 and
  probably the smallest piece of work in it. (D11)
- [ ] `[gated]` **Noise emission rewrite.** The consumer already works — `HordeManager`
  ATTRACTED + `_pick_attraction_target()` + `NoiseManager`. Emission is a flat 2-hex
  building-only aura, ~40x the reach of §6's loudest listed sound. Replace with §6's
  per-source dB and attenuation model. (D10, and the §6 item below)
- [ ] `[gated]` **Walls block bleed proportionally.** Sub-hex coverage extending
  `SubHexPortalGraph.has_any_crossing()`, cached per hex-pair, invalidated on
  `WallManager`'s place/remove/breach/repair signals. Hordes still siege. (D16-D19)
- [ ] `[visual]` **Hex-border snapping as a wall placement aid.** Freehand model
  unchanged; snap when a drawn line runs near a border, modifier key to refuse.
  Sealing a border is ~50 pieces over ~4,992 m and is pixel-hunting without it. (D20)
- [ ] `[gated]` **Gate pass-through.** Now specified rather than open: a gate is a wall
  friendly units can pass through, and nothing else. Detail below. (D18)

## Next — earns its place, but not the core loop

- [ ] `[gated]` **Per-settlement stockpiles.** One Town Hall = one stockpile.
  **Own PR, nothing else in it** — touches `ResourceManager`, every producer and
  consumer, every affordability check, every UI counter, and saves. Prerequisite for
  §2.1's Contested band. (D21)
- [ ] `[gated]` **Logistics geometry + throughput.** `SupplyLineSegment` gains
  `point_a`/`point_b` reusing `WallManager.place_wall_line()`; throughput-limited
  pooling at aggregate tonnage/day; severance by infestation >25%; isolated settlements
  stagnate rather than die. (D22-D24, D28, D29)
- [ ] `[gated]` **Terminals: railway stations, canal docks, road depots.** All three
  net-new. Required, one at each end of a line. (D25)
- [ ] `[gated]` **Canal locks.** Canals dead flat; locks cost resources and reduce
  throughput. Needs the fine elevation bake. (D26, D27)
- [ ] `[visual]` **Placed-segment renderer for Infrastructure.** No persistent visual
  exists once a segment is placed. Now part of the §2.2 rework. Detail below.
- [ ] `[gated]` **Epic phase 2 — mechanics read the vector layer.** Detail below.
- [ ] `[visual]` **Epic phase 4 — vertex-displaced elevation relief.** Unblocked by the
  fine elevation bake. Detail below.
- [ ] `[gated]` **`HordeManager` stuck-detection/bypass.** Shares `MovementStepper`
  clearance math with `UnitOrderController` but has no bypass at all. Detail below.
- [ ] `[gated]` **`portal_offset_for_step()` is still the expensive path.** Detail below.
- [ ] `[visual]` **6 of 15 resource counters have no icon, name or tooltip.** Detail below.
- [ ] `[gated]` **Placement status line is never cleared**, so no-op clicks read as
  successes. Detail below.
- [ ] `[visual]` **Tech Tree panel drew as an empty black rectangle** (unconfirmed).
  Detail below.
- [ ] `[gated]` **Relief tiles will not load in an exported build.**
  `ReliefTileView._load_tile()` calls `Image.load()` on a `res://` path, and Godot
  warns on every one: *"Loaded resource as image file, this will not work on export.
  Instead, import the image file as an Image resource and load it normally as a
  resource."* On export the source PNGs are not shipped, only the imported `.ctex`, so
  all 3,876 tiles would fall into `_missing` and elevation relief would silently
  disappear from a built game. Found 2026-08-27 by the first full run of
  `tools/ci/run_verifications.py` — the warnings were always in the log, nothing read
  the log. Verify by exporting, not by reasoning.

## Deferred — fails `vision.md` §5 check 3

Not forgotten. Not worked on until the core loop works. Do not justify work by these.

- [ ] `[design]` **§6 line-of-sight and light propagation, full version.** The crude
  `lit_at_night` attraction increment is in Now; full LoS/illumination waits. Needs the
  fine elevation bake. Detail below.
- [ ] `[design]` **Blood/smell attraction.** Raised by the user, explicitly undesigned.
- [ ] `[design]` **Late-game settlement-count management + automation/governors.** The
  acknowledged consequence of "killing is the only suppression" (D8).
- [ ] `[design]` **Physical goods transport** with travelling carts and trains. §2.2's
  throughput numbers are the upgrade path.
- [ ] `[visual]` Coastline/minimap still trace `_LAND_RLE`'s hex-quantized boundary.
- [ ] `[visual]` Epic 3b — blending across biome boundaries.
- [ ] `[visual]` Epic 5 — escarpment cliff faces + coastline detail.
- [ ] `[gated]` Epic 6 — `SubHexTerrainOverride` runtime patch path.
- [ ] `[gated]` Epic 7 — LOD / caching / perf pass.
- [ ] `[gated]` Real 1890s main roads baked from geographic data.
- [ ] `[visual]` Ambient ruins from real settlement data.
- [ ] `[visual]` Countryside features outstanding from the 2026-08-19 request.
- [ ] `[design]` Resource-tick pacing/balancing.
- [ ] `[design]` Famine-severity input to Morale.
- [ ] `[design]` Game time runs unattended while the playtester thinks (harness artifact).
- [ ] **Phase 3 — Sewers/Underground** (3.1, 3.2, 3.3). Cut order #1.
- [ ] **Phase 7 — Narrative Campaign** (7.1-7.7). Ships in v1.0, started only once the
  core game works. 7.5 Naval/Ireland is cut order #2.

## Closed by design, not by code

- **"Nothing escalates over time; the colony was unthreatened for 149 consecutive
  days"** (playtest, 2026-08-17). This was the structural gap that drove the entire
  §2.1 design. It is answered by the infestation model, not by a separate escalation
  feature. Detail retained below for the original observation.

---

## Detail (inherited from todo.md)

Verbatim, for the items above that reference it.

- [ ] **Placed-segment renderer for Infrastructure (Road/Railway/Canal/Bridge) — no persistent visual exists once a segment is placed.** `LogisticsNetwork.place_segment()` stores the segment and emits none of `network_recomputed`/`placement_rejected`/`segment_upgraded`/`upgrade_rejected` as a "just placed, draw me" signal a renderer could hydrate off — unlike `WallManager.wall_segment_placed`, which `StrategicOverlayManager`/`LocalDetailManager` already both listen to. Needs: a `segment_placed` signal on `LogisticsNetwork`, a `SupplyLineMarkerRenderer` (mirrors `WallMarkerRenderer`, using `SupplyLineVisuals.line_texture()` + `WallVisuals.apply_line_geometry()`'s UV_SCALE tiling trick verbatim — same `Line2D`-along-a-hex-edge shape a supply-line segment already is), and `LocalDetailManager` hydration on the new signal so a Tactical-zoom view repaints when a segment is placed nearby, same as `_on_wall_segment_placed()` already does for walls.

- [ ] **`SeaView`/`CoastlineOutlineView`/minimap still trace `_LAND_RLE`'s hex-quantized boundary, not the real coastline 1b baked.** Split out of 1b (2026-08-20). `SeaView`'s big under-everything fill stays correct regardless (it only needs to be big enough, not shaped right), but `CoastlineOutlineView`'s drawn line and the minimap's coastline both now visibly disagree with `TerrainMeshView`'s real mesh edge — the outline is coarser than the terrain it is supposed to be outlining. Needs the outline geometry to come from `coastline.land_polygon_world()` (or a cached derivative of it) instead of `HexCoord.coastline_segments()`.

- [ ] **`geo_projection.CALIBRATION_POINTS` has at least one bad row.** Found while validating 1b (2026-08-20): "Midlands Farmland (Warwick)" fits at 6.50 hex radii of residual, far outside every other row (0.44–2.34 for the 3 web-verified city anchors, mostly 1-3 for the rest per the file's own doc comment). Likely a transcription error in that row's lon/lat or q/r, not a property of the affine itself. Not fixed alongside 1b because re-fitting the affine means re-verifying every bake product that already depends on it (fine relief, fine tiles, raster landcover, vector landcover, and now the coastline) — a focused re-check of that one row's source, then one shared re-verification pass, not a coastline change.

- [ ] **2: mechanics read the vector layer.** `SubHexTerrainQuery`'s cache-miss body (`SubHexTerrainQuery.gd:53`) swaps from `RealTerrainSampler.sample_at_hex()` to point-in-polygon against the vector set. **The seam is exactly one call site** — the class already memoizes per 30m sub-cell address and caches misses (`{}`) too, so point-in-polygon runs once per cell ever touched and every hot-path caller (`HexPathfinder`, `HordeFlowField`, `SubHexPortalGraph`, `BuildingManager` placement) still hits a dictionary lookup. Same signature, same return shape, so all four existing readers are untouched. The real risk is not steady state but **cold-cache spikes** — a fresh `HordeFlowField` build or a long path over never-visited ground triggers many first-touch misses at once; mitigation is a per-hex polygon bucket index so a test only considers polygons overlapping that hex rather than all of GB+Ireland. Gate the merge on a measured before/after, not on the argument above. Two invariants must survive: overrides are applied to a DUPLICATE never in place, and the urban disc must keep not overwriting OCEAN/WATERWAY (load-bearing) or `terrain_feature` (`ReclamationManager` owns draining as a costed action).

- [ ] **3b: blending across biome boundaries.** Today a boundary is a hard edge — correct in shape, abrupt in appearance. Needs an N-texture weighted blend shader on real-geography vertices (~3 per vertex). `assets/shaders/terrain_blend.gdshader` was the 2-texture directional blend the square ground used and was **deleted with it on 2026-08-18** — it had no other consumer, and it blended one sprite against one neighbour, which is not the shape this needs. Recover it from git history for reference if useful (it records a real gotcha: Godot rejects a plain `return` inside `fragment()`), but expect to write this one fresh.

- [ ] **4: vertex-displaced elevation relief.** `HexCell.elevation` exists and has **zero rendering consumers today** (grepped). Camera is confirmed a flat orthographic `Camera2D`, so no projection change is needed. New `ElevationVisuals.gd` owns the single displacement formula; needs `y_sort_enabled` on the Tactical layer (only static `z_index -1/-2` exists today); and a cross-cutting sweep so every entity sitting on terrain (units, buildings, props, walls, zombies, resource nodes) takes the same offset and doesn't float or sink. Gameplay logic stays on flat logical coordinates throughout.

- [ ] **5: escarpment cliff faces + coastline detail.** `GameEnums.TerrainFeature.ESCARPMENT` exists with no visual; trigger it off steep vertex deltas.

- [ ] **6: runtime patch path.** `SubHexTerrainOverride` writes trigger local re-triangulation in-engine (`Geometry2D.triangulate_polygon`, ear-clipping — the local-patch quality compromise the missing native CDT forces), preserving the Town Hall urban-disc growth. Worth a test that the patch and the offline bake produce equivalent classification for the same region, since the two paths must stay in agreement.

- [ ] **7: LOD / caching / perf pass.**

- [ ] **Real 1890s main roads baked from geographic data** (user request, 2026-08-19: "implementing some main roads that existed in the 1890s based on geographic data"). Scoped, not built. The map already renders real rivers, real woods and real cities from OSM; the one thing a Victorian traveller would have navigated by that is still missing is the road network.
  **The data exists and is unusually good for this period.** Britain's 1890s main roads are essentially the turnpike network, whose trusts were wound up between roughly 1870 and 1895 with the alignments passing to county councils largely unchanged — so the modern A-road classification is a close descendant. Two sources, in preference order: (a) the **Cambridge Group's vectorised turnpike layer** (Satchell et al., *Candling the Turnpike*, via the UK Data Service) is an actual dated 19th-century road network and is the only option that answers "did this road exist in 1890" rather than inferring it; check its licence before assuming it can ship. (b) **OSM `highway=trunk|primary`, minus motorways**, as the pragmatic fallback. Also worth pulling `historic=roman_road`, since a good share of the trunk network still runs on it and it is explicitly tagged.
  **The fallback's known error, stated up front so it is not discovered late:** OSM carries no construction date, so a 20th-century bypass is tagged identically to the 1750 turnpike it bypasses. That systematically *adds* roads around every town — precisely where the player is, and precisely where a road matters most. Partial mitigations: prefer alignments that pass through a settlement's `landuse=residential` polygon over ones that skirt it, and drop `highway=trunk_link`/dual-carriageway geometry (`oneway=yes` pairs) outright, since nothing in 1890 was built as one. Neither is a substitute for a dated source; if (a) is usable, use it.
  **Both fetchers need extending and the tile cache is not reusable.** `fetch_overpass.py`'s query (`way["landuse"]`, `way["natural"]`, `way["waterway"]`) and `extract_pbf.py`'s `_matches_way()` both filter to land-cover tags, so **no `highway` way exists anywhere in the ~3 GB of cached tiles** — this is a re-extract from the source PBF, not a re-bake. Budget that before scoping the rest.
  **Two options for how a road is carried, and they are not equivalent.** As a **new mesh class**, following the WATERWAY precedent exactly (a LINE buffered to a real width, priority above the built environment, `_BIOME_CODE` 9 append-only with matching entries in `RealTerrainSampler._BIOME_BY_CODE` and `GameEnums.BiomeType`) — cheapest, reuses the whole existing pipeline including `_despeckle`'s WATERWAY exemption, but a road is not a biome and every consumer that switches on biome would have to learn to ignore it. Or as a **separate baked line layer** with its own renderer — more work, but a road keeps its centreline, which is what a movement bonus wants to follow and what a buffered ribbon throws away. A real 1890 main road is ~6–9 m wide, i.e. **0.6–0.9 wu** — a *seventh* of the 4.62 wu river ribbon and well under the 1.0 wu quantization grid — so the mesh-class option cannot represent one at true width and would have to draw it deliberately oversized. That alone probably decides it: take the line layer.
  **The gameplay question is the real decision and needs the user, not a default.** `LogisticsNetwork` already has a ROAD `SupplyLineType` with tiers in `SupplyLineCatalog`, and `HexPathfinder` has no road-cost term at all today. If pre-existing roads act as free Tier-0 supply line, the player starts connected to everywhere a turnpike went and the early-game logistics build is largely skipped; if they are only decoration, the map gains detail and nothing else; the middle option — roads give a movement bonus but carry no supply until the player invests in upgrading the segment — is probably what "main roads that existed" should mean, but it is a balance change either way and should be asked rather than assumed. Note the horde uses the same graph: a road that speeds the player's units up speeds an attacking swarm along the same corridor.
  Per CLAUDE.md §3, whichever representation wins must be readable at sub-hex resolution — a road is a ~7 m feature crossing a 5 km hex, so "this hex has a road" is not a usable answer to any question about it. Depends on nothing else in this epic and could be done before 1b.

- [ ] **3.1 Subterranean Layer System** — urban hex underground toggle (Victorian Sewers, London Underground tunnels).

- [ ] **3.2 Sewer Zombie Ecosystem & Outbreak System** — subterranean infestation density tracking, outbreak risk, doubled eruption risk at night if un-sanitized.

- [ ] **3.3 Sanitation & Political Interventions** — decree-style influence actions (Sanitation Act, Nerve-Gas Purge, Militia Sewer Sweep).

- [ ] **7.1 "The Southern Expedition" Campaign Arc (Manchester to London)**
  - [ ] **Act I: The Cottonopolis & The Pennine Barrier:** Secure Manchester (4 macro-hexes), clear the Chat Moss bogs, establish defenses across the Peak District passes.
  - [ ] **Act II: The Trent Valley & Fenland Corridors:** Rebuild rail infrastructure through Birmingham, cross the River Trent, defend supply routes against hordes from the East Anglian Fens.
  - [ ] **Act III: The Thames Basin Citadel:** Breach the Chiltern Hills, secure outer London's 12 macro-hex perimeter, navigate the flooded London Underground, reclaim Imperial headquarters.
  - [ ] Horde size/frequency should escalate roughly Act to Act — Manchester's small starting hordes are the tutorial-difficulty end of the same curve.
  - [ ] Acts I-III stay open/organic, same as the persistent map around them — only content beyond London gets an actual access lock.

- [ ] **7.2 Major Milestone Objectives System (`CampaignManager.gd`, not yet built)**
  - [ ] **Primary Objective:** Establish a continuous, defended rail/road logistics link from Manchester to London.
  - [ ] **Secondary Objective:** Investigate regional relic sites (wrecked observatories, strange craters, underground testing facilities, captured UFOs) revealing alien spore origins — optional lore, does not gate anything.
  - [ ] **Final Mystery:** Uncover the fate of Queen Victoria and the Imperial Cabinet in the sealed Tower of London bunker. Leave it open-ended for an expansion. Triggers the Wales/Scotland unlock (7.2.1) — a legitimate seat of government being re-established is the in-fiction justification for authority extending past England. The Secondary Objective is explicitly not required for this.
  - [ ] **7.2.1 Region Locking (extends Fog of War):** Wales, Scotland, Ireland (+ surrounding sea hexes) start `is_locked = true`, checked before Fog of War runs — forces `UNSEEN` regardless of vision, blocks pathfinding both directions. Wales+Scotland unlock together on the Final Mystery resolving; Ireland stays locked until Seafaring is researched (which itself needs Wales+Scotland actually retaken, not just unlocked). Unlocking is one-way and permanent.

- [ ] **7.3 Playtesting & Steam Integration**
  - [ ] Balance multi-week campaign progression from Manchester down to London, and onward through Wales/Scotland/Ireland.
  - [ ] Steam Cloud Saves (synced per-Campaign), Achievements, Steam Deck controller layout support.

- [ ] **7.4 Wales & Scotland Reclamation** — plan only. Two separate Acts (Act IV: Wales, Act V: Scotland), unlocked together by 7.2.1, tackled in either order — both more remote/resource-poor than England. Each gets its own geography seed content and campaign-style milestones; reuses every system built through Phase 6 as-is.

- [ ] **7.5 Naval Logistics & Seafaring (Ireland Unlock)** — plan only, biggest net-new system in this list, in scope for v1.0. Ireland is only reachable by sea: ports (new building, payoff of the Seafaring tech node), ships (new unit-like entity, own pathfinding over open-water hexes), sea supply lines as a `LogisticsNetwork` segment type alongside road/rail/canal. Locked until Wales and Scotland are both retaken.
  - [ ] Act VI: Ireland — same escalating-difficulty/milestone pattern as 7.1/7.4, the far end of the campaign's difficulty curve.

- [ ] **7.6 Difficulty, Win/Loss & New Game Setup** — plan only.
  - [ ] **Decided: defeat is an economic/capability elimination check, not territorial.** Game ends only when the player has (a) not enough stockpiled resources to create new units or retake lost land, (b) no total daily production from anything still standing, and (c) no remaining building capable of recruiting a unit or expanding onto a new hex. Holding even one settlement able to recruit/expand means the player still has a chance.
  - [ ] Recovering from near-total loss is meant to be possible in principle but hard in practice: Territory Capture/Loss lets a lost district be recaptured at all; Casualty Conversion makes it genuinely hard — a densely populated settlement that falls converts its own people into the zombies now defending it.
  - [ ] Difficulty presets (horde aggression/frequency, upkeep drain rates) and starting-map/seed choice at New Game (naming a Campaign).

- [ ] **7.7 Future Expansion Hook (Continental Europe)** — plan only, the one deliberate v1.0 exclusion. Architecture already supports it without rework: axial hex coordinates are unbounded, `BritishGeographyData.MAP_BOUNDS` is a single adjustable constant, named geography is entirely data — a future Europe expansion is "author a new seed data file and raise the bounds," not a rewrite. Naval logistics (7.5) is the actual prerequisite, since Europe is sea-separated from Great Britain. Framed as a future paid expansion (~£5) if the base game finds an audience.

- [ ] **Resource-tick pacing/balancing** (flagged by the user 2026-08-11, needs more thought before touching): production ticks once per in-game day; default game speed is 5x. Should this move to multiple ticks/day (e.g. "4 might reduce to 2 ticks a day and 2 ticks a night")? Any change has to solve the same catch-up-safety problem the existing flat day/night average multiplier was built to sidestep — `TickManager.day_completed` can fire multiple times in one frame during a large-delta catch-up burst at high speed, so a naive per-phase accumulator would double/under-count.

- [ ] **Ambient ruins from real settlement data** (user request, 2026-08-11, scoped not built): pre-existing rubble scattered across unowned/uncontrolled land based on where real UK settlements actually exist, distinct from the player-built-then-destroyed ruin mechanic. Needs `tools/geo_bake/fetch_overpass.py`'s query extended with a `building=*` tag (currently only pulls `landuse`/`natural`/`waterway`), a new settlement-footprint raster or density channel, and a consumer (likely `LocalDetailGenerator`) that places ruin props where real OSM data says a building used to stand and the hex isn't currently player-controlled. No mechanics decided for what a ruin actually does beyond visual dressing (loot? salvage? horde spawn bias?) — deferred until a follow-up decides.

- [ ] **Gate pass-through behavior:** gates currently block identically to a plain wall until breached — no special ally-pass-through mechanic yet.

- [ ] **Countryside features still outstanding from the same request (2026-08-19).** The user asked for four things beyond thick forests and picked them explicitly: **drystone walls & hedgerows** along real field boundaries (the boundary-edge data `TerrainBoundaryBlend.find_crossings()` already computes is the natural input), **ruins & abandoned cottages** that can be selected and demolished when inside a ZoC (overlaps the existing "ambient ruins from real settlement data" item above), **crags/scree/boulder fields** concentrated on steep ground (the 30 m relief tiles bake shade, and `|shade - 128|` is a direct slope proxy — no new bake needed), and **real resource deposits that gate mine placement** (user chose "real deposits that gate mines" over decorative-only, so this touches `BuildingCatalog` placement rules, save data and map balance — it is a gameplay change, not a visual one). None are started.

- [ ] **Famine-severity input to Morale:** a fifth input (units undersupplied but not dying) would need `UnitMorale` to take a live `BuildingManager` reference it's currently deliberately free of — reasonable extension, not wired.

- [ ] **`SubHexPortalGraph.portal_offset_for_step()` is still the expensive path.** `has_any_crossing()` (added for the boundary rule) early-outs at the first passable sample and measured 0.02 ms/edge, but `portal_offset_for_step()` — called per hex-to-hex leg by `UnitOrderController` and `HordeManager` — still goes through `find_portals()`, which sweeps the whole edge at 30 m (~167 positions, measured 2.18 ms cold per edge and ~178 stranded `SubHexTerrainQuery` cache entries). Cached per hex pair so it is paid once per edge per session, but it is the remaining unbounded-cache contributor. Pre-existing, not introduced by the boundary rule.

- [ ] **`SubHexTerrainQuery._cache` is unbounded and never evicted.** One entry per queried 30 m sub-cell under a String key, static for the process lifetime. Fine at today's query volume; `cache_size()` exists to measure it. A FIFO/LRU cap like `HordeFlowField.MAX_CACHED_FIELDS` is the obvious fix if a long session ever shows it growing.

- [ ] **Line of sight, sound propagation & light — `design_doc.md` §6, the largest wholly unimplemented section of the spec** (user request, 2026-08-19: "trees and elevation etc. blocking line of sight plus other line of sight and noise reduction mechanics we need to implement"). Scoped, not built.
  **This is not a new design — §6 ("Vision, Sound, Light & Zombie AI Systems") plus §5's per-level LoS rules already specify all of it, and nothing in this file tracked any of it.** Grepping todo.md for `shadowcast`, `height_level` or `pheromone` returned nothing before this entry. The user-confirmed implementation order (Resources → Buildings → Units → ~~Biomes~~ → Infrastructure → Town Hall) never contained §6, which is why "the doc order is complete" and "§6 is unbuilt" are both true at once. Per the standing directive above, implement what §6 says rather than inventing a parallel model.
  **What exists today, precisely.** Vision is a radial disk with *no occlusion of any kind*: `FogOfWarManager._compute_visible_set()` marks every hex returned by `HexCoord.sub_hex_disk()`. There is no LoS, raycast or shadowcast code anywhere in `scripts/` (grepped). The only terrain term is `HexCell.get_vision_penalty()` — WOODLAND −2 rings, MOORLAND/WETLAND/HEATHLAND −1 — keyed to the **source's own hex only**, so trees the viewer stands in shrink the disk while trees *between* viewer and target do nothing. `FogOfWarManager`'s own comment states the current contract outright: "reduces, never blocks (no stealth mechanic)". Elevation contributes nothing to vision at all. Night is a flat ±1 ring (`NIGHT_VISION_PENALTY`/`NIGHT_LIT_BONUS`) against the doc's percentage model (dusk −25%, night −60% unlit) and its separate zombie-detection figures (unchanged at dusk, −30% at night), which have no concept in code. `NoiseManager` is buildings-only: a flat `BuildingDefinition.noise_output` (17 of 42 buildings set one) applied to every hex in a 2-hex disk and summed, with no distance falloff and no attenuation.
  **`ElevationLevels.gd` is already the seam for §5/§6's elevation rules and its own doc comment says so** — "whatever picks up §5's vision/LoS/range modifiers later" is the named missing consumer. `height_level` 0–4 is derived from `HexCell.elevation`, never stored; keep it that way rather than adding a field.
  **Settle the scale mismatch before writing any code.** `design_doc.md` measures everything in 10 m tiles; the mechanical layer is 30 m sub-cells (`HexCoord.SUB_HEX_CELL_SIZE_METERS`) and a macro hex is ~5 km circumradius (`HEX_SIZE` 512 wu ÷ `WORLD_UNITS_PER_REAL_METER` 0.10256), i.e. ~8.6 km centre-to-centre. Divide the doc's tile figures by 3 to get sub-cells: rifle shot 10–15 tiles → 3–5 sub-cells (100–150 m), Maxim 25 → ~8, steam engine 12 → 4, artillery 40+ → 13+, construction 8 → ~3. **Every sound in §6's table is smaller than a fifth of one macro hex.** Against that, `NOISE_RADIUS = 2` reaches two hex rings ≈ 17 km — roughly 40x the doc's loudest event and 100x its rifle — and `HordeManager.ATTRACTION_AWARENESS_RADIUS = 6` scans ~50 km. The per-hex noise `Dictionary` cannot represent a single §6 sound event, so this is a rewrite onto the sub-hex layer, not a tuning pass.
  **Nothing but buildings makes noise, which inverts the genre's central tension.** §6's table makes gunfire the loudest routine event (rifle 10–15 tiles, Maxim 25) and melee near-silent (1–2) — in *They Are Billions* that trade is the core decision, and the standing directive above points straight at it. Today firing a Maxim is completely silent and only a foundry is audible. Needs noise events emitted from unit attacks (`CombatCoordinator`) and vehicle movement, not just `BuildingDefinition.noise_output`. `CombatCoordinator`'s own "Not implemented yet" list already names the other half: a horde choosing a target on purpose still needs the ATTRACTED/noise system to drive it.
  **Noise reduction: what the doc gives, and the decision it leaves open.** §6 gives *attenuation* only — open terrain/waterway 100%, woodland/structures/walls −2 tiles per obstacle tile traversed, Level 2/3 Highland −50%, Level 4 Mountain blocks completely. That is a propagation rule needing the same terrain traversal the LoS raycast needs, so write **one** traversal and have both read it (the shared-source-of-truth extraction that paid off for `is_water_crossing_blocked()` — and enumerate every caller before wiring an exclusion in). What §6 does *not* give is any player-facing noise-reduction lever: no muffled machinery, no silenced weapon, no blackout order. If reduction should be something the player *builds* rather than a property of the ground, that is an addition to the doc and wants an explicit decision — the candidates that fit 1890 are siting industry behind woodland (already free under the attenuation rule), a Tier-4 muffled-plant building/upgrade, and gas-lamp discipline at night (`lit_at_night` + `NIGHT_LIGHT_ATTRACTION` already exist and already cost attraction, so that lever is half-built).
  **CLAUDE.md §3 applies hard, and one prerequisite is genuinely missing.** LoS occlusion and sound attenuation are exactly "read terrain to make a gameplay decision", so they go through `SubHexTerrainQuery`, never `HexCell.biome_type` — and `get_vision_penalty()`'s single per-macro-hex value is one of the flattening cases §3 exists to catch, since what matters is the vegetation *along the ray*. **But elevation is not available at sub-hex resolution at all:** `RealTerrainSampler._sample_fine()` takes biome/feature from the 30 m fine tile and elevation always from the coarse raster, which `bake_landcover.py` writes with `step = 4` plus a nearest-neighbour upsample — ~3.5 km blocks, about 15 distinct values per hex. The 30 m relief tiles baked 2026-08-19 are greyscale *hillshade*, a derived look, not sampleable heights. So an elevation LoS raycast has nothing to trace today; **a fine elevation bake is a hard prerequisite**, and it is the same blocker `majority_biome()`'s comment flags for its max-vs-percentile question. Carry the named exception forward too: MOUNTAIN is decided per macro hex (`SubHexPortalGraph._is_mountain_blocked()`) because `MountainPassCarver`'s carve exists only in hex data and nowhere in the raster — §6's "Level 4 blocks all LoS" must follow the same rule for the same reason, or a carved pass becomes a sight-line that is blocked while remaining walkable.
  **Cost is a real risk, and the doc already prescribes the mitigations:** symmetric shadowcasting at O(N) per source, a 16×16 spatial hash, `LightMap[x][y]` as a `uint8` field, a ring-buffer `SoundQueue` ticked rather than propagated per frame, and distance-based AI throttling. Note what that lands on: `FogOfWarManager.recompute()` rebuilds the *entire* visible set from scratch on every change and already needed a per-frame coalescer to survive units crossing hexes at 1000x speed — a per-ray occlusion test multiplies that by the ray count, and its own comment already names the fix ("a dirty-region incremental recompute would be the real fix if per-frame coalescing ever stops being enough"). A shadowcast fans out across an area by definition, so benchmark against `SubHexTerrainQuery`'s unbounded String-keyed cache before wiring it in (`scripts/test/bench_portal_blocking.gd` is the template — the naive boundary check cost 2.18 ms/edge and ~178 cache entries/edge before an early-out rewrite took it to 0.02 ms and ~1).
  **Suggested split, so this isn't one unshippable PR:** (a) fine elevation bake; (b) shadowcasting + terrain/elevation occlusion for vision only, consuming `ElevationLevels`; (c) sound as real sub-hex events with attenuation over the same traversal, replacing `NoiseManager`'s flat aura; (d) unit/combat/vehicle noise sources; (e) light emitters and the doc's ambient-percentage model replacing the ±1 ring; (f) §6's 4-state zombie perception machine, which is the consumer that gives (b)–(e) their point. (a) blocks (b) and (c); (f) depends on all of them.

- [ ] **6 of the 15 resource counters render with no icon, and none has a name or tooltip** (user-observed + verified on screen, 2026-08-17): the top bar reads `100/∞ 50/∞ 0/∞ 0/∞ 150/∞ 0/∞ 0/∞ 0/∞ 0/∞ 0/∞ 100/∞ 40/∞ 0/∞ 0/∞ 20/∞` — six entries are a bare `0/∞` with no art at all, and no counter carries a text label or a hover tooltip. After a 153-day session only 3 of 15 could be identified, and only by differencing the bar across build actions. Two separable pieces: the icons, and the absence of any name/rate affordance on the bar at all. No counter shows a per-day rate either, so a build card's `+200 Wood/day` is never reflected anywhere in the HUD.
  - **The icon half is fixed, and the diagnosis above was wrong (2026-08-18).** No icon art was ever missing: all 15 `ResourceType` values map through `ResourceVisuals._icon_key()` to a `.png` that exists on disk, checked one by one. What the playtester saw was the Blender pipeline's framing — `render_common.add_camera()` framed every asset at a fixed `ortho_scale = 3.0` aimed at the world origin, so `cast_iron.png` carried 310px of ink on a 2048px canvas, and `ResourceBarView` aspect-fits that whole canvas into a 20x20 slot. Measured displayed size of the committed art: **8 of the 15 rendered under 4px** (cast_iron/steel 3.0px, concrete 3.1px, gunpowder/iron_ore/limestone/sulfur 3.6px, bricks 3.9px) and the *largest*, coal, reached only 9.2px. "No art at all" and "a 3px smudge" are indistinguishable at that size, which is why the count landed at six. Fixed at the source by re-rendering the category with `render_category.py --category icons --fit per-asset`; see the framing item below. **Generalizable: a UI-only playtester reports symptoms, and its guess at a cause is worth re-deriving from the code before it is written down as one** — this one sent the fix at the asset *inventory* when the defect was in the asset *framing*.

- [ ] **The placement status line is never cleared, so no-op clicks read as successes** (observed, 2026-08-17): Wood `2188` → click → `2088` with `Smallholding Farm under construction — ready in 2 days.`; two further clicks left Wood at `2088` while re-displaying the identical success line. Reproduced with Lumber Yard: 10 consecutive clicks all reported `under construction`, Wood moved 110 → 60, i.e. exactly one was real. `Escape` does not clear the line either — it survived into the next building's selection. Cheap fix independent of the placement bug above: blank the line on every placement-mode map click before writing the new result, so a no-op leaves an empty line rather than the previous success.

- [ ] **Tech Tree panel drew as an empty black rectangle for most of the session** (observed, unconfirmed, 2026-08-17): from first open until roughly in-game day 130 the panel rendered as a black box in the bottom-right with no content and no reachable `Close`, then began rendering correctly with no input to trigger it. Panel is also semi-transparent — the map's black hexes show through the tech names. Not reproduced deliberately and not traced; recorded so it isn't lost, needs a repro attempt before any fix.

- [ ] **Game time runs unattended while the playtester thinks** (user-observed, 2026-08-17): the visible "idling" during the session is the observe→decide→act loop — the game sits at whatever speed was last set while the agent reasons about the previous screenshot, which at 1000x means ~12 in-game days can elapse per 30s of thinking, unobserved and unrecorded. Makes sessions non-deterministic and is the likely explanation for the two apparent clock stalls the session logged but declined to file as findings. Fix is a `step_days(n)` command that pauses, advances exactly n days, and pauses again, plus auto-pausing whenever the harness is idle waiting for a command — so game time only moves when the playtester asks for it.

- [ ] **Nothing escalates over time; the colony was unthreatened for 149 consecutive days** (observed, needs a user design decision before any code): across days 1–149 at 1000x the session saw no enemy sprite, alert, counter, bearing or timer, and the HUD carries no wave number, no ETA and no enemy count. The first and only combat text arrived on day 150 (`Smallholding Farm destroyed at (80, 116)!`) — a building the player never saw, at coordinates the UI gives no way to navigate to. Per the standing *They Are Billions* directive above, TAB's actual structure was researched rather than invented: **10 scheduled swarms** at a fixed cadence scaled to map length, each announced **8 game-hours ahead with a compass bearing**, the final swarm given **24 hours'** notice and landing at **~90% of map length** (not the last day, so it must actually be fought), plus unannounced runner trickle from **day 20** so the perimeter is never safe to strip ([Swarms wiki](https://they-are-billions.fandom.com/wiki/Swarms), [Swarm days/size by difficulty](https://steamcommunity.com/app/644930/discussions/0/1849197902656427682/)). Concrete proposal for a 100-day map, as a starting point rather than a spec: swarms on days **12, 22, 31, 39, 47, 55, 63, 72, 81, 90 (final)**, sized **40 / 58 / 84 / 122 / 177 / 257 / 372 / 540 / 783** from one edge and **4,000 from all edges** on day 90; 2–6 infected/day from a random edge from day 20; and a permanent HUD readout (`Swarm 4/10 — 2d 6h — North-East`) turning red at T-8h, T-24h for the final. **This changes what the game fundamentally is — a fixed-length siege campaign rather than an open-ended builder — so it needs an explicit user decision on map length and whether the campaign is fixed-length at all before anything is written.** Today's only day-driven spawn hook (`HordeManager._on_ambient_spawn_day`) takes the day number as an unused `_day_number` parameter, i.e. day 80 is exactly as dangerous as day 3.

- [ ] **`HordeManager` has no equivalent stuck-detection or bypass at all** (found while fixing the above, not touched — out of scope for a player-unit bug report). It shares `MovementStepper.steer_around_obstacles()` and the same `ENTITY_RADIUS`/`ObstacleRadii` clearance math, so a horde routed through dense WOODLAND should get stuck exactly like a unit did pre-fix, with no escape hatch at all — worse, not better. Needs its own decision on whether hordes should path around wooded ground at the strategic level instead (arguably more correct for a horde than clipping through trees) rather than just copying UnitOrderController's bypass mechanism verbatim.
