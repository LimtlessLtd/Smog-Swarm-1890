# The Smog & The Swarm - Master Development Todo & Technical Specification
> **Project Title:** `The Smog & The Swarm`
> **Project Code:** `SMOG-SWARM-1890`  
> **Github Url:** https://github.com/LimtlessLtd/Smog-Swarm-1890
> **Engine & Language:** Godot Engine 4.x (GDScript)  
> **Target Release:** PC / Steam (£5–£10 target price point)  
> **Genre:** Persistent Background Real-Time Strategy & Base-Building  
> **Setting:** 1890 Victorian Britain Post-Apocalypse (Grounded Industrial Revolution Tech, Zombies, Hidden Alien Origins)

---

## 🔧 Technical Summary
Godot 4.x/GDScript RTS on a continuous axial hex map of real UK+Ireland geography (Natural Earth coastline, ~25 sq mi/hex, ~4,700 land hexes). Terrain inside the playable England corridor (Manchester/Midlands/London) is real data baked from OpenStreetMap land-cover + SRTM elevation (`tools/geo_bake/`), rendered at both a coarse whole-corridor resolution and per-hex fine tiles near the camera. A two-tier camera (Strategic hex-icon / Tactical true-scale, `HexCoord.HEX_SIZE` = 512 world units/hex) drives everything from country-scale strategy to individual soldiers. **Phases 1 → 2.12, 4, 5 (core), 6, and 6.3 are built and playable end to end** — full economy, building tree, tech tree, 18-unit roster with combat/morale/veterancy, horde AI, walls/ZoC/supply lines, Fog of War, Day/Night, save/load, and a complete code-drawn HUD. **Not built:** the sewer/underground layer (Phase 3), late-game reclamation and the campaign (Phase 5.11, Phase 7). Godot binary: `E:\Program Files\GoDot\Godot_v4.7.1-stable_win64_console.exe`.

---

## 📖 The Setting
January 1890. Something came down over the Pennines in the night, and within a week the dead of Manchester were walking. The city sealed itself hard — gaslit checkpoints, a militia raised from constables and navvies, whatever the Industrial Revolution could throw up in a fortnight — and held. Beyond the wire, the rest of Britain went dark: no telegraph, no trains, no light after sundown, just the slow drift of the hungry across a country that used to be the workshop of the world. You inherit that quarantine: one lit town in an island of soot and silence, armed with nothing but cast iron, coal smoke, and Victorian grit — no borrowed future technology, just the Industrial Revolution pushed as far as it will go. South of you, Queen Victoria and the Imperial Cabinet are sealed in a bunker under the Tower of London, and nobody above ground knows if they're still alive. Scattered through the wreckage are stranger traces still — wrecked observatories, craters that don't match any war, rumours of things that didn't fall from the sky by accident. Your job isn't rescue. It's to hold the light, push roads and rail south hex by hex, and find out — expedition by expedition — whether Manchester's quarantine was the last sane decision the old world made, or the first sign that whatever did this was already here.

---

## 🏛️ Project Architecture & Design Overview
- **Core Loop:** Continuous persistent expansion across Victorian Britain hex sectors. Build defenses, automate patrols, manage daily resource upkeeps (Food/Energy/Gunpowder), and protect supply lines while working in the background.
- **Aesthetic Direction:** Grounded late-18th/19th-century Industrial Revolution (brick, cast iron, coal smoke, authentic Victorian architecture)—explicitly **no** retro-futuristic steampunk tropes, including top-tier "mechanized" units (heavy steam engineering, never a humanoid battle-mech).
- **Dual Perspective Engine:** Camera toggle between Top-Down Orthographic and 2.5D Isometric.
- **Multi-Layer Macro-Hex System:** Each hex = a ~25 sq mi macro-region. Cities scale across multiple macro-tiles — Manchester spans 4 hexes, Greater London spans 12. Internal district partitioning and subterranean layers (Sewers/Underground) planned.
- **Time Controls & Day/Night Cycle:** Global `TickManager` supporting `0x`/`1x`/`2x`/`3x`/`5x` speeds. 40-minute real-time day/night cycle at 1x.
- **Accessibility:** Every color-coded piece of state (biome, ZoC, fog-of-war, building category, alerts) is paired with a distinct shape/icon, never color alone.
- **World State Framing:** Outside player-held ground, 1890 Britain is dark and roamed by hordes with no fixed home. Player settlements are the only lit, defended points on the map. Arc runs from defensive "hold the light" early-game toward reclaiming and re-lighting the country late-game (Phase 5.11, Phase 7.4/7.5).

---

## 🚫 Explicitly Out of Scope
> Considered and declined, not merely forgotten — worth stating plainly so nobody re-litigates these mid-project. Revisit only if the game's commercial scope changes.
- **Multiplayer / co-op.** Single-player only; the persistent-background hook and the whole design (one player's colony) assumes it.
- **Steam Workshop / mod support.** Not for initial release.
- **Rival human factions / diplomacy.** The threat is zombies (plus the alien-origin mystery); no competing AI colonies or negotiation systems.
- **Full localization.** English only for initial release.
- **Mainland Europe.** Everything else — including Naval Logistics and Ireland (Phase 7.5) — ships in the initial release. Europe (Phase 7.7) is a future paid expansion if the game finds an audience, not built for v1.0.

---

## 🧩 Known Architecture Constraint: Hex-Grid Over-Coupling
> One hex is ~25 sq. miles — most fields below are still a single scalar value for that entire area, which doesn't match real terrain. Biomes/elevation and wall geometry are already real sub-hex resolution (closed 2026-08-10 and earlier). Still hex-locked today:
- **Supply lines** (`SupplyLineSegment.hex_a`/`hex_b`) — whole-edge only, the same shape walls used to have before their rework.
- **Zone of Control, Noise, Fog of War** (`LogisticsNetwork`, `NoiseManager`, `FogOfWarManager`) — flat per-hex `Dictionary` state, no gradient across the hex's own area.
- **Districts** (`District.gd`/`DistrictPartitioner.gd`) — fixed categorical template per hex (always exactly Urban Center + Industrial Estate + Uncleared Wilderness for a settlement hex), no real position/shape/geography.

Revisit if/when a dedicated sub-hex spatial partition gets designed for these — Districts' `Array[District]` per hex is the closest existing seam to extend, though terrain's own fix used a sampled raster instead of a partition since it's read-heavy/write-never data, not the same shape as ZoC/Districts' write-heavy contested-flag-flips-at-runtime need.

**Also disclosed:** the full map span (~214,600×136,700 world units) is past the ~100,000-unit range where single-precision float jitter typically starts (`HexCoord.HEX_SIZE`'s doc comment) — no jitter observed live so far; a floating-origin camera rebase is the real fix if it ever surfaces.

---

## 📐 Standing Directive: Design Against *They Are Billions*, Don't Invent New Mechanics
> User feedback, 2026-08-09, verbatim in spirit: "This is all built in They Are Billions but for some reason I'm having to spec it out again... you aren't basing these mechanics on what I am [referencing] and instead inventing your own mechanics." **Before designing or redesigning wall placement/destruction, zombie movement/AI, or siege behavior, research how *They Are Billions* actually implements it first, and match that model** rather than deriving a new one from first principles.

---

## 📎 Design Doc & Implementation Note
`design_doc.md` (v4.5) is now the authoritative spec for biome/terrain movement rules, the resource economy, the building tree, tech unlock thresholds, ZoC/field-supply rules, and the unit roster — it supersedes the equivalent detail that used to live in this file. Implementation order (user-confirmed 2026-08-13): **Resources → Buildings → Units → Biomes → Infrastructure → Town Hall founding → Tech upgrades**, one PR per item, reviewed/playtested between each before the next starts.

- [x] **Resource economy rework (2026-08-13).** `GameEnums.ResourceType` now carries all 15 of `design_doc.md` §2's types (6 raw: Wood/Clay/Coal/Limestone/Iron Ore/Sulfur; 5 processed: Bricks/Iron/Steel/Concrete/Gunpowder — Iron/Concrete renamed from Cast Iron/Reinforced Concrete; 4 capacity/yield: Food/Energy/Population/Research). **User-decided design fork, resolved before implementing:** Population changes from a Food-driven headcount that could starve to death and regrow into a pure capacity pool exactly like Energy — housing grants capacity once at construction, consumers reserve a flat share once, both refunded on ruin/demolish/death (`BuildingCapacityAllocator`, generalized from the old Energy-only `BuildingEnergyAllocator`). The starvation-death/regrowth mechanic (`BuildingSustenanceController`) and its `civilians_starved` signal are removed entirely; Food shortfall now only reduces production via the existing ratio-based multiplier, it no longer kills anyone. `BuildingInstance.current_population` survives as housing occupancy (fixed at `population_provided` once built, zeroed on ruin) since `HordeManager`'s ruin-to-casualties conversion still needs a "how many were housed here when it fell" snapshot — that mechanic is unaffected. `DiscontentManager`'s overcrowding driver (reads the same `current_population` field) is unaffected too; only its now-orphaned starvation-casualty pressure input was removed. **Deliberately NOT in this pass** — actual non-housing Pop costs on buildings/units (every building past the 2 existing housing types, every unit) and the 6 new raw resources' real extraction buildings/recipes: the mechanism exists (`BuildingCapacityAllocator`, the new enum values, `ResourceManager.STARTING_STOCKPILE` all seeded at 0.0) but nothing produces/consumes them yet — that wiring is the Building/Unit tree reworks' job, next in the order above. Existing 21 buildings/18 units mechanically unchanged (Cast Iron→Iron/Reinforced Concrete→Concrete renamed in place, same costs). Not save-compatible with pre-rework saves (`ResourceType`'s ordinal layout changed) — expected, given the buildings/units rework ahead breaks saves further anyway.
- **Building tree rework (next).** Current `BuildingCatalog.gd`'s 21 buildings (Housing & Civil / Industry & Extraction / Agriculture / Defense Works categories, e.g. Timber Camp, Clay Brickworks) need reconciling against `design_doc.md` §3's tier-0-to-5 building list (Lumber Yard, Clay Pit, Brickworks, etc. — different names, costs, and a real tier-gated unlock structure tied to Research thresholds). This is also where the 6 new raw resources get real extraction buildings and the 5 processed-resource recipes (§2) get built, and where non-housing buildings start actually costing Population capacity.
- **Biome movement rules rework.** `HexPathfinder`'s current per-biome multipliers (Highland 1.6x, Wetland 1.8x, Waterway 1.4x) use a different biome set and different numbers than `design_doc.md` §1 (Farmland 0.9x, Moorland 0.5x, Highland 0.75x, Wetland 0.5x, Woodland 0.75x, Heathland 0.5x, Waterway impassable). Needs a real reconciliation pass, not just a constant swap, since the biome list itself differs.
- **Town Hall / second-settlement founding.** `design_doc.md` §3 (Tier 3 Town Hall) answers the previously-open design question ("no player-driven way to ever found a second settlement" — `HexMapGenerator`'s `is_settlement`/`URBAN` are currently only ever set once, at map-gen) — a new Town Hall becomes a real, tier-3-gated, buildable structure that founds a new ZoC hex. This is new gameplay, not currently built at all.
- **Per-unit tech upgrades.** `design_doc.md` §4 specifies "2 research upgrades per unit type, auto-applies to active & future units" — `TechManager`/`TechCatalog` currently only unlock whole unit tiers, no per-unit upgrade nodes exist yet.
- **Infrastructure (road/rail/canal/bridge) costs & speed bonuses.** `design_doc.md` §2/§3 gives real per-tier costs and speed multipliers matching `GameEnums.SupplyLineType`'s existing ROAD/RAILWAY/CANAL enum, but there's still no player-facing placement controller for any of them (unlike walls' `WallPlacementController`) — building that placement UI is a prerequisite for any of this mattering in play.
- Unit roster naming/stats (`UnitCatalog.gd`) already broadly match `design_doc.md` §4's Tier 0/1/3/4/5 lists — Tier 2 differs (`Rifleman` in-game vs. `Bayoneteer` in the design doc) and needs a rename/rebalance pass against the doc's exact cost/cap/upkeep numbers.

---

## 🔭 Long-Term Goals / Not Yet Built

### Phase 3: Urban Underground & Sewer Outbreak Mechanics
> Deferred — nothing else in the roadmap has a hard dependency on it existing early. Two loose threads to remember when picking it back up:
> - Phase 5.1's "Sewer infestation eruption rate increases 2x by night" is contingent on this phase.
> - Phase 7.1's Act III beat ("navigate the flooded London Underground") depends on this phase's subterranean layer existing by then.
> - Phase 2.11's Discontent system feeds this phase's political-decree mechanics (Sanitation Act, etc.) once it exists.
- [ ] **3.1 Subterranean Layer System** — urban hex underground toggle (Victorian Sewers, London Underground tunnels).
- [ ] **3.2 Sewer Zombie Ecosystem & Outbreak System** — subterranean infestation density tracking, outbreak risk, doubled eruption risk at night if un-sanitized.
- [ ] **3.3 Sanitation & Political Interventions** — decree-style influence actions (Sanitation Act, Nerve-Gas Purge, Militia Sewer Sweep).

### Phase 5.11: Countryside Reclamation (Late-Game Offense)
Plan only, not started. Mid/late-game shift from purely defensive play to actively hunting and thinning ambient horde population — the mechanic underneath Phase 7's campaign corridor-clearing. A cleared hex isn't permanently safe — ambient spawning continues.

### Phase 7: Narrative Campaign, Objectives & Steam Polish
> **Scope decided:** everything in this phase ships in the v1.0 Steam release **except mainland Europe** (7.7, a future paid expansion). One continuous chain — Manchester → Trent Valley → London (open/organic, no gating) → Wales & Scotland (hard-gated, unlock together once the Final Mystery resolves) → Ireland (hard-gated, unlocks once Seafaring is researched, which itself needs Wales+Scotland retaken).
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

---

## 🔩 Other Open Items (not covered by design_doc.md)
- [ ] **Resource-tick pacing/balancing** (flagged by the user 2026-08-11, needs more thought before touching): production ticks once per in-game day; default game speed is 5x. Should this move to multiple ticks/day (e.g. "4 might reduce to 2 ticks a day and 2 ticks a night")? Any change has to solve the same catch-up-safety problem the existing flat day/night average multiplier was built to sidestep — `TickManager.day_completed` can fire multiple times in one frame during a large-delta catch-up burst at high speed, so a naive per-phase accumulator would double/under-count.
- [ ] **Ambient ruins from real settlement data** (user request, 2026-08-11, scoped not built): pre-existing rubble scattered across unowned/uncontrolled land based on where real UK settlements actually exist, distinct from the player-built-then-destroyed ruin mechanic. Needs `tools/geo_bake/fetch_overpass.py`'s query extended with a `building=*` tag (currently only pulls `landuse`/`natural`/`waterway`), a new settlement-footprint raster or density channel, and a consumer (likely `LocalDetailGenerator`) that places ruin props where real OSM data says a building used to stand and the hex isn't currently player-controlled. No mechanics decided for what a ruin actually does beyond visual dressing (loot? salvage? horde spawn bias?) — deferred until a follow-up decides.
- [ ] **Gate pass-through behavior:** gates currently block identically to a plain wall until breached — no special ally-pass-through mechanic yet.
- [ ] **Famine-severity input to Morale:** a fifth input (units undersupplied but not dying) would need `UnitMorale` to take a live `BuildingManager` reference it's currently deliberately free of — reasonable extension, not wired.
