# The Smog & The Swarm - Master Development Todo & Technical Specification
> **Project Title:** `The Smog & The Swarm`
> **Project Code:** `SMOG-SWARM-1890`  
> **Github Url:** https://github.com/LimtlessLtd/Smog-Swarm-1890
> **Engine & Language:** Godot Engine 4.x (GDScript)  
> **Target Release:** PC / Steam (£5–£10 target price point)  
> **Genre:** Persistent Background Real-Time Strategy & Base-Building  
> **Setting:** 1890 Victorian Britain Post-Apocalypse (Grounded Industrial Revolution Tech, Zombies, Hidden Alien Origins)

---

## 🏛️ Project Architecture & Design Overview

- **Core Loop:** Continuous persistent expansion across Victorian Britain hex sectors. Build defenses, automate patrols, manage daily resource upkeeps (Food/Coal/Gunpowder), and protect supply lines while working in the background.
- **Aesthetic Direction:** Grounded late-18th/19th-century Industrial Revolution (brick, cast iron, coal smoke, authentic Victorian architecture)—explicitly **no** retro-futuristic steampunk tropes.
- **Dual Perspective Engine:** Dynamic camera toggle between **Top-Down Orthographic** (tactical layout) and **2.5D Isometric** (cinematic viewing).
- **Multi-Layer Macro-Hex System:** Continuous tilemap hiding an underlying axial hex grid `(q, r)`. Each hex represents a 5x5 mile macro-region (~25 sq miles). Cities scale dynamically across multiple macro-tiles—Manchester spans 4 hexes (~100 sq miles), while Greater London spans 12 hexes (~300 sq miles). Features internal district partitioning and subterranean layers (Sewers/London Underground).
- **Time Controls & Day/Night Cycle:** Global `TickManager` supporting `0x` (Pause), `1x`, `2x`, `3x` and `5x` speeds (`Engine.time_scale`). Features a 40-minute real-time day/night cycle (20 minutes Day / 20 minutes Night at 1x speed).
- **Accessibility:** Every color-coded piece of state (biome, soil, Zone of Control, fog-of-war, building category, alerts) is paired with a distinct shape/icon, never color alone — cheap to hold to now, expensive to retrofit once more systems lean on color.
- **World State Framing:** Outside player-held ground, 1890 Britain is functionally dead — dark, unlit, and roamed by hordes with no fixed home (Phase 5.10). Player settlements are the only lit, defended points on the map (Phase 2.6's Fog of War and Phase 5.10's horde roaming are two views of the same idea — a beacon surrounded by darkness). The whole game arc runs from purely defensive "hold the light" play early-to-mid game toward proactively reclaiming and re-lighting the wider country late-game (Phase 5.11, Phase 7.4).

---

## 🚫 Explicitly Out of Scope
> Considered and declined, not merely forgotten — worth stating plainly so nobody re-litigates these mid-project. Revisit only if the game's commercial scope changes.
- **Multiplayer / co-op.** Single-player only; the persistent-background hook and the whole design (one player's colony) assumes it.
- **Steam Workshop / mod support.** Not for initial release — code-drawn placeholder visuals and data-driven building/tech definitions would make this plausible later, but it's not being built for now.
- **Rival human factions / diplomacy.** The threat is zombies (plus the alien-origin mystery); no competing AI colonies or negotiation systems.
- **Full localization.** English only for initial release.

---

## 📝 Phase 1: Engine Foundation, Terrain & Geography
- [x] **1.1 Project Setup & Configuration**
  - [x] Initialize Godot 4.x project repository with modular GDScript folder structure (`/scripts`, `/scenes`, `/assets`, `/ui`).
  - [x] Configure display settings for low-CPU background execution (Unfocused FPS limit, background audio processing).
- [x] **1.2 Dual Camera Controller (`CameraController.gd`)**
  - [x] Implement smooth pan, zoom, and perspective toggle (`TOP_DOWN` vs `ISOMETRIC`).
- [x] **1.3 Continuous Axial Hex Map & Real British Geography (`HexGridMap.gd`)**
  - [x] **5x5 Mile Macro-Hex Grid System:** Axial coordinate system `(q, r)` where each hex acts as a ~25 sq mile regional container. Manchester spans 4 macro-hexes; London covers 12 macro-hexes.
  - [x] **Authentic British Biomes & Topography:**
    - [x] **Elevated Terrain & Natural Barriers:** Pennine Chain (Peak District chokepoints south of Manchester), Chiltern Hills, and Cotswold Escarpment.
    - [x] **Major Waterways & Canals:** River Thames, River Mersey, River Trent, and historic canal networks (Manchester Ship Canal, Grand Union Canal).
    - [x] **Swamps & Waterlogged Basins:** Fenlands, Thames Estuary Marshes, and Chat Moss peat bogs.
  - [x] **Granular Soil Fertility:** Map localized soil patches (`Lush` Cheshire/Midlands farmland, `Poor` moorland, `Desolate` industrial slag heaps) inside individual hexes to determine specific farm placement and crop yields.
  - [x] **District & Frontline Partitioning:** Divide macro-hexes into sub-districts (Urban Center, Industrial Estate, Uncleared Wilderness), enabling active zombie combat in contested halves while safe zones harvest resources and build infrastructure.

---

## 🏭 Phase 2: Historical Building Tree, Economy & Logistics
- [x] **2.1 Authentic 19th-Century Building Tree (`BuildingManager.gd`)**
  - [x] **Housing & Civil:** Terraced Tenements, Workhouses, Church Steeple Watchtowers, Gas Streetlamps, Telegraph Relay Offices, Steam Printing Presses. (Also added Town Hall & Garrison — not named in this checklist, but required as Civilian/Military ZoC sources by 2.3.)
  - [x] **Industry & Extraction:** Clay Brickworks, Charcoal Kilns, Coal Pitheads, Cast Iron Foundries, Saltpetre/Powder Mills, Forward Ammo Dumps.
  - [x] **Agriculture:** Tenant Farms (requires `Lush`/`Poor` soil), Grain Silos, Cattle Yards.
- [x] **2.2 Resource Upkeep Engine (`ResourceManager.gd`)**
  - [x] Manage daily upkeep drains: **Food** (population drain), **Coal** (boiler/heating/streetlamp upkeep), and **Gunpowder** (ranged combat upkeep).
  - [x] Track construction materials: **Wood**, **Bricks**, **Cast Iron**, **Reinforced Concrete**.
- [x] **2.3 Supply Line Logistics & Two-Zone Control System (`LogisticsNetwork.gd`)**
  - [x] Build supply flow nodes connecting outer resource sectors to central population hubs via roads, railways, and canal lines.
  - [x] **Simplified Dual Zone of Control (ZoC):**
    - [x] **1. Military ZoC (Supply, Vision & Suppression):** Projected by Forward Ammo Dumps, Garrisons, Watch Towers, and Combat Units. Gives off a resupply aura covering 66% of a tile. Permits small-scale wooden barricades to keep zombies at bay and protect assets.
    - [x] **2. Civilian ZoC (Civil Infrastructure & Construction):** Projected by Town Halls, Churches, and Telegraph Relays. Can only be placed on secure hex tiles (no zombies) and covers the entire hex tile. Unlocks major wall fortifications and Barracks for unit recruitment.
  - [x] Implement supply line disruption logic: If zombies sever a road, rail, or canal segment connected to an Ammo Dump, its Military ZoC supply aura deactivates.

---

## 🔎 Phase 2.5: Tactical Zoom & Local Detail Layer
> Added mid-development (not in the original spec) to guarantee the intended *They Are Billions*-at-country-scale feel: seamlessly zoom from a large chunk of Great Britain down to individual trees and buildings. Built now, ahead of Phase 3, because Phase 4's freeform wall-snapping already needs precise coordinate placement rather than hex-granularity — this is the foundation that unlocks that, not a detour from it.
- [x] **2.5.1 Two-Tier Map Rendering (`CameraController.gd`, `LocalDetailManager.gd`)**
  - [x] Hard zoom-threshold switch between the abstract Strategic hex view (the "large chunk of the UK" view) and a continuous, coordinate-precise Tactical view of a single hex's ~5x5 mile footprint — a pure camera zoom crossing a line, no loading screen or separate map.
  - [x] Tactical detail only generates for settled/frontier hexes (settlement, has a placed building, or covered by Military/Civilian Zone of Control) — distant unclaimed wilderness stays an abstract tile even at max zoom, keeping the persistent background simulation cheap at full-country scale.
  - [x] A neighborhood of qualifying hexes around the camera hydrates/dehydrates as the player pans while zoomed in, so tactical detail follows a contiguous developed territory rather than a single fixed hex.
- [x] **2.5.2 Procedural Local Detail (`LocalDetailGenerator.gd`)**
  - [x] Deterministic, coordinate-seeded prop scatter (trees/bushes/rocks/reeds) varied by each hex's biome — regenerated on demand instead of authored/saved per hex.
- [x] **2.5.3 Precise Building Placement**
  - [x] BuildingInstance/BuildingManager extended with an exact position within a hex (`place_building_at_world()`), instead of only a hex-coordinate slot, so buildings render at real positions in the Tactical view.
- [ ] **2.5.4 Individual Units** — deferred: no unit system exists until Phase 5.4. The Tactical view's local-position pattern (BuildingInstance.local_position, world-space placement) is designed to extend to units directly once that phase starts.

---

## 🌫️ Phase 2.6: Fog of War
> Plan only — not implemented yet. Documented now because it's a prerequisite for Phase 5.1's "Fog of war contracts outside of Gas Streetlamps and Watchtower searchlights" (that line needs a fog system to contract in the first place), and because Phase 2.5's Tactical view needs a fog gate too — an unexplored hex has nothing known to render, at any zoom.
- [ ] **2.6.1 Three-State Visibility Model (`GameEnums.FogState`, `FogOfWarManager.gd`)**
  - [ ] `UNSEEN` (never scouted, rendered as blank darkness) → `EXPLORED` (terrain/buildings remembered, no current intel on movement) → `VISIBLE` (full real-time information). `UNSEEN → EXPLORED` is one-way per hex forever; `EXPLORED ↔ VISIBLE` toggles freely as vision sources come and go.
  - [ ] `FogOfWarManager` (new system, wired as a HexGridMap-sibling like LogisticsNetwork/BuildingManager) owns fog state per hex and recomputes `VISIBLE` coverage whenever a vision source changes: building placed/removed (`BuildingManager`), Zone of Control recomputed (`LogisticsNetwork`), and later unit movement (Phase 5.4).
  - [ ] **Decided:** losing a hex's last vision source doesn't drop it to `EXPLORED` instantly — it lingers `VISIBLE` for a short grace period first (a few seconds), so losing sight of a threat isn't instant/twitchy. Needs a per-hex timer, not just a recompute-on-change flag.
- [ ] **2.6.2 Vision Sources**
  - [ ] `BuildingDefinition.vision_radius` (new field) — buildings like Gas Streetlamps and the Church Steeple Watchtower project vision over their own hex plus a small radius, independent of whether they also project a Zone of Control.
  - [ ] Military and Civilian ZoC coverage (`LogisticsNetwork`) double as vision sources — this was already the original Phase 2.3 spec's intent ("Military ZoC: Supply, **Vision** & Suppression"), just not wired to anything until this phase exists.
  - [ ] Units (Phase 5.4) feed the same system once they exist — `FogOfWarManager`'s vision-source contract should be generic enough that a unit is just another source, not a special case.
- [ ] **2.6.3 Rendering Hooks**
  - [ ] Strategic view (`HexCellView`): tint the whole tile via `Node2D.modulate` — black (hides biome color entirely) for `UNSEEN`, dimmed grey for `EXPLORED`, full color for `VISIBLE`. No new nodes needed.
  - [ ] Tactical view (`TacticalHexView` / `LocalDetailManager`, Phase 2.5): a hex must be at least `EXPLORED` to hydrate a Tactical view at all — an `UNSEEN` hex zoomed into is still just blank/dark, there's nothing known to draw. Terrain/props/buildings stay visible (dimmed) at `EXPLORED`; the future mobile-entity layer (zombies, units — Phase 5) must check `VISIBLE` before drawing anything there, so an `EXPLORED`-but-not-`VISIBLE` hex shows remembered terrain with no zombies/units on it — exactly "see the terrain, not what's moving through it."
- [ ] **2.6.4 Night Integration (feeds Phase 5.1)**
  - [ ] Vision radius shrinks at night except for lit sources (Gas Streetlamps, Watchtower searchlights), which hold or extend theirs. This is what Phase 5.1's fog contraction actually runs on under the hood — recorded here so that phase doesn't have to invent the fog system itself when it arrives.

---

## 🚩 Phase 2.7: Strategic Map Markers & Threat Indicators
> Building icons and the frontier indicator are implemented now (see commit); wall markers, unit markers, under-attack alerts and spotted-horde markers are documented here as hooks for Phase 4/5.2-5.4 to register with when those systems exist, rather than left to be retrofitted later.
- [x] **2.7.1 Generic Marker Layer (`StrategicOverlayManager.gd`)**
  - [x] A single overlay system (WorldRoot sibling of HexGridMap, Strategic-zoom only — hides itself on `CameraController.tactical_mode_changed`) that other systems register markers with instead of each drawing its own icons.
  - [x] Code-drawn placeholder glyphs per marker type (same convention as every other visual so far), swappable for real icon art later without touching whatever triggers a marker.
- [x] **2.7.2 Building & Frontier Markers**
  - [x] A small icon per placed building, colored by `BuildingCategory` (shared `BuildingVisuals.category_color()` lookup, also used by `TacticalHexView` so the two views agree), driven off `BuildingManager.building_placed`/`building_removed`, positioned at the building's own precise `local_position` from Phase 2.5.
  - [x] A frontier indicator on hexes that mix secured and contested ground (`HexCell.is_frontier()` AND `get_safe_districts()` non-empty — a fully wild hex is just unclaimed territory, not a line worth marking; a fully secured hex has nothing contesting it). Matches "settlement hexes" under today's Phase 1 baseline district data, and will naturally spread to other hexes once Phase 3+ adds real territory capture/clearing.
- [ ] **2.7.3 Wall Markers** — blocked on Phase 4.1. Wall segments register their position/state with `StrategicOverlayManager` once the freeform wall system exists.
- [ ] **2.7.4 Unit Markers** — blocked on Phase 5.4. Units register/unregister the same way buildings do.
- [ ] **2.7.5 Under-Attack Alerts** — blocked on Phase 4.2 (wall breach) and Phase 5.4 (`CombatEngine` engagement events). Either raises a pulsing alert marker at the hex under attack, cleared once the threat resolves.
- [ ] **2.7.6 Spotted Horde Markers** — blocked on Phase 5.2 (`HordeManager`) and 5.3 (reconnaissance). Interacts with Fog of War (Phase 2.6): while a horde's hex stays `VISIBLE` the marker tracks it live; once vision is lost, **decided:** the marker freezes as a dimmed "last known position" ghost rather than vanishing — you remember roughly where it was, not where it's gone.

---

## 💾 Phase 2.8: Persistence & Save/Load
> Plan only — not implemented yet. **Decided:** "persistent background" describes what's already built (`BackgroundExecutionManager` keeps the sim cheap while alt-tabbed/minimized during a play session) — it does NOT mean the colony keeps simulating, or catches up, while the application itself is fully closed. Closing the game pauses everything exactly where it was; reopening resumes there. No elapsed-time math, no "while you were away" report — that idea's explicitly dropped along with the offline-simulation model it would've depended on.
- [ ] **2.8.1 What Actually Needs Saving**
  - [ ] Terrain does **not** need saving — `HexMapGenerator`/`BritishGeographyData` use fixed noise seeds (1890/1891), so the base map is byte-identical every time it's regenerated. The same logic already applies to `LocalDetailGenerator`'s per-hex prop scatter (Phase 2.5) — deterministic, coordinate-seeded, never persisted today, and that was the right call.
  - [ ] What DOES need saving: `BuildingManager`'s placed instances (building type + hex coord + local_position — re-look-up the `BuildingDefinition` from `BuildingCatalog` by type rather than saving the definition itself), `ResourceManager`'s stockpile + storage caps, `LogisticsNetwork`'s supply line segments and severed state (ZoC itself recomputes fresh from buildings on load, doesn't need saving), `TickManager`'s current day/speed, and — once they exist — Fog of War's explored/visible state per hex (Phase 2.6, this one's genuinely earned player knowledge and can't be re-derived), Tech Tree unlock state (Phase 2.9), and Discontent per civilian region (Phase 3.4).
- [ ] **2.8.2 Save Format (`SaveGameData.gd`)**
  - [ ] A single aggregating `Resource` populated by pulling the above out of each manager (they're already `Node`s, which `ResourceSaver` can't serialize directly) — save via `ResourceSaver.save()`, load via `ResourceLoader.load()` and feed the values back into fresh manager instances on startup.
- [ ] **2.8.3 Save/Load UI** — manual save slots at minimum; autosave cadence is a later balancing decision, not an architecture one.

---

## 🔬 Phase 2.9: Technology & Progression Tree
> Plan only — not implemented yet. Resolves an existing gap: Phase 4.1 already assumes wall tiers unlock somehow ("Wooden -> Brick -> Concrete"), and Phase 5.4's Tier 0-3 units need the same kind of gate. A dedicated tree gives both a home, plus a resource-to-spend sink beyond raw construction. **Decided:** dedicated tree over pure milestone-unlocks, for the extra player agency.
- [ ] **2.9.1 Research Generation (`TechManager.gd`)**
  - [ ] A Research Points resource (new `GameEnums.ResourceType` entry) generated by civic/knowledge buildings — Telegraph Relay Office and Steam Printing Press are the natural sources given what's already built, without needing a brand new building type.
- [ ] **2.9.2 Tech Nodes**
  - [ ] Each node costs Research Points (+ often a construction material) and takes time to complete; unlocks a wall tier (Phase 4.1), a unit tier (Phase 5.4), or an advanced building variant.
  - [ ] Simple prerequisite chain (node B needs node A first) rather than a wide branching web — matches the project's grounded, non-sprawling scope.
- [ ] **2.9.3 UI** — a tech list/tree screen; out of scope exactly how it looks until Phase 6's HUD work is underway.

---

## 🍞 Phase 2.10: Population Sustenance & Starvation
> Plan only — not implemented yet. Extends already-built Phase 2.1/2.2: population currently exists only as `BuildingDefinition.population_provided`, a fixed number per building *type* — this phase makes it real, mutable, per-instance state that can actually be lost, which is also what Phase 5.9's casualty conversion needs to have anything civilian to convert in the first place.
- [ ] **2.10.1 Population Becomes Mutable (`BuildingInstance.current_population`)**
  - [ ] New per-instance field on `BuildingInstance`, seeded from `definition.population_provided` when a housing building is placed. Colony-wide population for upkeep purposes (`BuildingManager`'s existing daily tally) sums `current_population` across instances, not the static definition value.
- [ ] **2.10.2 Food Satisfaction Ratio**
  - [ ] Each day (`BuildingManager._on_day_completed`, already built): `ratio = available_food / food_demand`, where `food_demand` is the same population-based Food upkeep already computed today, and `available_food` is stockpile + that day's production.
  - [ ] **Decided thresholds:** `ratio >= 1.0` — fully fed, no penalty (see 2.10.4 for surplus above this). `0.5 <= ratio < 1.0` — no deaths, but a production penalty on all buildings scaling with how far below 1.0 (e.g. ~75% fed is a moderate hit, ~55% fed is severe) — hungry, not dying. `ratio < 0.5` — civilians actually starve to death (2.10.3).
- [ ] **2.10.3 Starvation Deaths**
  - [ ] Below the 50% threshold, population is lost from housing buildings proportional to each instance's share of `current_population` — severity scales with how far below 50% the ratio is (barely under starves a few, near zero would be a catastrophe), not a flat rate the moment it triggers.
  - [ ] **Decided: military units are explicitly exempt from starvation death** — rationing priority goes to the garrison, full stop. Losing your defenders to hunger on top of an active siege would just be miserable, not interesting. (Whether undersupplied units still take a lesser morale penalty instead is Phase 5.7's call, not this one.)
  - [ ] Every starved civilian is a casualty for Phase 5.9's purposes — converts to a zombie at its own housing building's hex, same as a combat death. A famine inside your own walls can produce a horde without a single external zombie ever getting in.
- [ ] **2.10.4 Food Surplus Bonus**
  - [ ] **Decided:** a genuine surplus (comfortably above `ratio = 1.0`, not just barely meeting it) grants a modest, deliberately limited bonus — a small production boost and/or gradual `current_population` regrowth back toward `definition.population_provided` (recovery after a famine, or organic growth). Exact numbers are a balancing pass, not an architecture decision.
- [ ] **Cross-references:** feeds Phase 3.4's Discontent as an additional driver (a hungry-but-not-starving population is unhappy about it, independent of the direct production penalty above) and Phase 5.9 (starvation deaths are casualties like any other).

---

## 🏙️ Phase 3: Urban Underground & Sewer Outbreak Mechanics
- [ ] **3.1 Subterranean Layer System (`SubterraneanMap.gd`)**
  - [ ] Urban hex underground toggle (Victorian Sewers, London Underground tunnels).
- [ ] **3.2 Sewer Zombie Ecosystem & Outbreak System (`SewerInfectionController.gd`)**
  - [ ] Subterranean infestation density tracking and outbreak risk algorithms.
  - [ ] Double sewer eruption risk during Night phase if un-sanitized.
- [ ] **3.3 Sanitation & Political Interventions**
  - [ ] Influence actions: *Sanitation Act*, *Nerve-Gas Purge*, *Militia Sewer Sweep*.
- [ ] **3.4 Population Discontent (`DiscontentManager.gd`)** — plan only; a *colony-wide population* mechanic, distinct from the *per-unit* Morale & Veterancy system documented under Phase 5.7 — don't conflate the two.
  - [ ] **Decided scope:** per contiguous Civilian Zone of Control region, not global and not per-hex. A "Civilian Region" is a maximal connected cluster of hexes currently carrying `has_civilian_coverage` (`LogisticsNetwork`, Phase 2.3) — hex-adjacency flood fill, recomputed whenever ZoC changes. Multi-hex settlements (Manchester's 4 hexes, London's 12) share one Discontent value as long as they stay contiguously covered; a region physically split by lost territory splits into two independently-tracked regions.
  - [ ] Drivers: overcrowding (summed `population_provided` in the region against a capacity threshold) and casualties/incursions within the region's own hexes are region-local; Food/Coal/Gunpowder shortfalls affect every region equally, since the resource stockpile itself is deliberately one global pool (Phase 2.2), not split per region. Worth stating plainly: Discontent is region-scoped, the economy underneath it deliberately isn't. Food specifically now has its own precise ratio/threshold system (Phase 2.10) rather than just the generic `ResourceManager.upkeep_shortfall` signal — a hungry-but-not-starving population (2.10.2's 50-99% band) is a Discontent driver here on top of 2.10's direct production penalty, not instead of it.
  - [ ] Consequences: production penalty on buildings within a high-Discontent region (queried by `BuildingManager` at its existing daily-tally step, Phase 2.1); unrest events are a later addition once there's an event system to hang them on.
  - [ ] Feeds Phase 3.3's decrees (a policy response to rising Discontent, not just sewers) and Phase 7's political mystery thread.

---

## 🧱 Phase 4: Defensive Construction, Infrastructure & Chokepoints
- [ ] **4.1 Chokepoint Defensive Building (`BuildingSystem.gd`)**
  - [ ] Freeform wall construction snapping across geographic bottlenecks (riverbanks, cliff passes). Structurally closer to `LogisticsNetwork`'s `SupplyLineSegment` (a line between two points, potentially snapping along a chokepoint) than a normal point-placed `BuildingInstance` — decide whether it reuses `BuildingInstance` with a start/end pair of `local_position`s or gets its own `WallSegment` data class when this is actually built; no gameplay consequence either way, pure implementation detail.
  - [ ] Wall progression: Wooden Walls -> Brick Walls -> Concrete Walls (tier unlocked via Phase 2.9's Tech Tree).
  - [ ] **Decided: walls are attackable and have a real health pool** scaling with tier — a horde does damage to a wall segment over the course of a siege (Phase 5.10's `ATTACKING` state) rather than it being a binary present/absent gate.
  - [ ] **Decided: hordes get an explicit siege bonus against walls** (representing sheer numbers/attrition wearing down a static structure) — walls are never literally unbreachable, but a well-invested one (tier + defense works below + a garrisoned/lit bonus from Streetlamps/Searchlight Towers) should comfortably outlast anything but a genuinely large horde. The point is walls stay a good investment, not a false sense of security.
  - [ ] **New defense works, stacking with a wall segment rather than replacing it:** Ditches and Oil Pits (new building types in the existing `BuildingCatalog`, Phase 2.1) — each adds toughness/breach-difficulty or inflicts damage on a besieging horde before/during a breach attempt. This is the "the more you invest, the harder it is to break in" lever, separate from the tier ladder above.
  - [ ] Retain legacy inner walls as fallback bulkheads during breach events — a breached outer wall doesn't expose the district directly, it exposes it to the next layer in (see 4.2's expanded siege-cascade note).
  - [ ] Build Gas Streetlamps and Searchlight Towers to illuminate perimeter walls during night defense, granting combat bonuses to garrisoned units.
- [ ] **4.2 Victorian Infrastructure Reclamation**
  - [ ] Rebuild destroyed stone bridges, steam railways, and canal locks to restore interrupted supply routes.
  - [ ] Drain swamps (e.g., Chat Moss, Fenlands) to improve soil quality and expand buildable land.
  - [ ] **Wall fortification and siege survival logic** — expanded: a siege is a cascade through layers, not a single check. Outer wall (4.1) fails first, then any legacy inner wall, then garrisoned units (Phase 5.4/5.6) — only once *all* of those layers in a district have failed do its civilian population and buildings actually become exposed to the horde, triggering Phase 5.8 (district falls) and Phase 5.12 (buildings inside start taking damage). A breach is the start of a fight for the district, not an instant loss of it.

---

## ⚔️ Phase 5: Threat Mechanics, Day/Night & Horde Intel
- [ ] **5.1 40-Minute Day/Night Simulation (`TimeCycleManager.gd`)**
  - [ ] **Day Phase (20 Minutes):**
    - [ ] +20% Construction and resource gather speed.
    - [ ] Zombies are slow/sluggish; minimal aggressive horde movement.
    - [ ] Full baseline visual range across unlocked hexes.
  - [ ] **Night Phase (20 Minutes):**
    - [ ] Zombie move speed +50%, aggression +100%, and double noise-attraction multiplier.
    - [ ] Fog of war contracts outside of Gas Streetlamps and Watchtower searchlights.
    - [ ] Sewer infestation eruption rate increases by 2x.
- [ ] **5.2 Horde Spawn & Industrial Attraction System (`HordeManager.gd`)**
  - [ ] Industrial noise fills Threat Meters, triggering night raids from uncleared wilderness.
  - [ ] Second spawn source, see Phase 5.9: casualty conversion turning the player's own losses into zombies, accumulating into hordes at the site of defeat.
  - [ ] Spawning is only half the system — see Phase 5.10 for what a horde actually does once it exists (it doesn't stay put).
  - [ ] **Decided: the world starts pre-populated with a handful of small roaming hordes** (Phase 5.10's `WANDERING` state from turn one, not something that only appears once noise/casualties trigger it) — deliberately modest in size so a brand-new colony has room to establish basic defenses before facing anything serious. Horde size and spawn frequency ramp up over time rather than staying flat for the whole game (campaign Act pacing: Phase 7.1; a difficulty-preset lever: Phase 7.6).
- [ ] **5.3 Reconnaissance & Early Warning Mechanics**
  - [ ] High ground observation posts & telegraph alerts provide horde countdown timers — concretely, an ETA along an `ATTRACTED` horde's path (Phase 5.10) once it's within observed range, not just an abstract warning.
- [ ] **5.4 Unit Tiers & Combat Engine (`CombatEngine.gd`)**
  - [ ] Tier 0 (Free Ammo) through Tier 3 (Heavy Artillery) combat routines.
  - [ ] Strict Gunpowder depletion penalty: 0 ammo forces ranged units into fragile, unarmored melee mode.
- [ ] **5.5 Hex & Local Pathfinding Foundation (`HexPathfinder.gd`)** — plan only; a shared prerequisite for 5.2 (hordes routing to a target) and 5.4/5.6 (units), documented once here rather than solved twice.
  - [ ] Strategic-scale: A* over the hex graph (`HexCoord.neighbors`), weighted by terrain passability (`HexCell.is_passable()`) and existing roads/rail/canal (`LogisticsNetwork` segments as cheaper edges) — this is how a horde or a unit column crosses several hexes.
  - [ ] Tactical-scale: local movement within a hydrated hex (Phase 2.5) around scattered props/buildings — much shorter-range, doesn't need the same algorithm to double as both.
- [ ] **5.6 Unit Orders, Automation & Patrol Routes (`UnitOrderController.gd`)** — plan only; this is what "automate patrols" (Core Loop, top of this doc) actually refers to, and it wasn't scoped anywhere until now.
  - [ ] Standard RTS order set: move, attack-move, hold position, rally point on newly-trained units.
  - [ ] Patrol routes: a player-defined loop of waypoints (naturally, along roads/wall lines) a unit walks indefinitely, engaging threats it encounters along the way without further input — the actual automation the pitch promises.
  - [ ] Garrison orders: assign a unit to a building/wall segment for a stationary defense bonus instead of patrolling.
- [ ] **5.7 Unit Morale & Veterancy (`UnitMorale.gd`)** — plan only; **decided:** distinct from Phase 3.4's population-wide Discontent — this is per-unit.
  - [ ] Morale derived from four inputs: current health (fraction of max HP), equipment (weapon tier 0-3 and whether it's actually supplied with Gunpowder right now, tying into 5.4's depletion penalty), rank/experience (a kill counter driving a Rookie -> Veteran -> Elite-style progression), and unit tier itself.
  - [ ] Low morale degrades combat effectiveness (accuracy/damage or a chance to rout); veterancy from kills grants small permanent combat bonuses — gives individual units a reason to matter and survive rather than being disposable ammo sponges.
  - [ ] Units are exempt from Phase 2.10's starvation deaths by design, but a severe famine (`ratio < 0.5`) is a reasonable fifth input here — undersupplied-but-alive rather than dying keeps the "don't lose your garrison to hunger mid-siege" guarantee intact while still making a famine cost the military something.
- [ ] **5.8 Territory Capture & Loss (`TerritoryController.gd`)** — plan only. The missing mechanism underneath both "losing a settlement" and "retaking it": nothing currently flips a `District`'s `is_contested` flag during play — Phase 1's `DistrictPartitioner` only sets the *initial* state once, at map generation.
  - [ ] **Loss:** a safe district (`is_contested = false`) flips to contested when a zombie assault overwhelms whatever's defending it (Phase 5.4 combat resolution) — losing whatever Civilian/Military ZoC coverage (Phase 2.3) it was projecting, and, per Phase 5.9, converting anyone stationed or housed there into zombies.
  - [ ] **Recapture:** a contested district flips back to safe once the player clears it of zombies (Phase 5.4 again) — the mechanism that lets a colony reduced to one settlement claw back everything it lost (see Phase 7.6).
- [ ] **5.9 Casualty Conversion & Zombie Repopulation (extends `HordeManager.gd`, Phase 5.2)** — plan only. **Decided:** every civilian and military unit lost becomes a zombie at the location it died — a lost Tenement's whole housed population, a unit killed in the field, all of it. Deliberately not a token/percentage loss; it's the whole reason losing a dense settlement is catastrophic rather than merely inconvenient.
  - [ ] Converted zombies accumulate into that hex's own zombie population — tracked by `HordeManager` as a second, casualty-driven spawn source alongside its existing wilderness-attraction spawning (Phase 5.2) — rather than vanishing into a generic "contested" abstraction.
  - [ ] Once accumulated numbers are large enough, the hex effectively becomes (or reinforces) a horde in its own right: a formerly dense urban district that falls can become one of the single largest threats on the map, purely from its own dead. Feeds Phase 2.7.6's spotted-horde markers the same as any other horde.
  - [ ] Direct consequence for Phase 5.8's recapture: retaking a hex is a real fight scaled to how populous it was when it fell, not a formality — precisely what makes "reduced to one settlement" (Phase 7.6) a genuine crisis without making it unrecoverable.
- [ ] **5.10 Horde Roaming, Attraction & Settlement Sieges (`HordeManager.gd`)** — plan only. **Decided:** a horde is a mobile entity that roams freely across hexes, not a static count pinned to the hex it spawned in — this is the mechanic underneath "cities as beacons in a dead world."
  - [ ] **Horde state machine:** `WANDERING` (default — drifts across passable uncleared wilderness using Phase 5.5's pathfinder, biased toward open territory rather than a deliberate beeline anywhere) → `ATTRACTED` (a horde within range of a noise or light source above threshold — Phase 5.2's industrial noise, and Phase 2.6's lit vision sources at night — paths deliberately toward it) → `ATTACKING` (horde reaches the source's hex and a siege begins, handed off to Phase 5.4 combat) → back to `WANDERING` (repelled, reduced but not destroyed), or absorbed into the settlement's fallen population if the siege succeeds (Phase 5.9), or destroyed outright.
  - [ ] **Contact matters however it happens:** a horde doesn't need to be actively attracted to trigger a siege — pure chance wandering into a player-held or Military-ZoC-covered hex triggers the same `ATTACKING` transition. Attraction just makes contact far more likely/deliberate; it isn't the only path to it.
  - [ ] **Attraction is local, not global:** noise/light project a limited radius (an aura, same shape as ZoC/vision), not colony-wide awareness — a horde on the far side of the map has no way to know a distant city is loud. Keeps a country-sized map from turning every horde into a beeline toward whichever settlement is currently noisiest.
  - [ ] **Escalation:** a horde that wins a siege absorbs that hex's casualty conversion (Phase 5.9) and grows — the longer a horde goes unchallenged and the more it succeeds, the bigger and more dangerous it gets. A horde that loses is reduced, not automatically wiped, and reverts to `WANDERING` to menace somewhere else.
  - [ ] **Performance:** same LOD principle as Phase 2.5 — hordes far from any player-relevant hex (no Tactical detail hydrated nearby, out of vision range) run a cheap abstracted simulation (position + drift only), and only upgrade to full pathfinding/AI once within range of player territory or vision. A country-sized map cannot afford full per-frame AI for every roaming horde everywhere at once.
- [ ] **5.11 Countryside Reclamation (Late-Game Offense)** — plan only. The intended arc: early-to-mid game is purely defensive ("hold the light" against whatever roams in from the dark, per Phase 5.10) — late game is when the player has enough spare military capacity (units not needed for home defense/patrol, Phase 5.6) to go looking for hordes instead of waiting for them, thinning out ambient wilderness zombie density through direct attrition rather than only reacting to sieges.
  - [ ] This is the actual mechanic underneath Phase 7's campaign requiring a "continuous defended logistics link" (7.2) and Post-Campaign UK Liberation (7.4) — clearing a corridor or a whole region isn't a one-off scripted event, it's this same roaming-horde population being hunted down hex by hex.
  - [ ] A cleared hex doesn't flip to "permanently safe forever" — ambient wilderness can still reseed a wandering horde later (Phase 5.2's spawn system doesn't stop just because the player went on offense once); reclamation is upkeep, not a one-time switch, matching the "persistent background" pillar of the whole game.
- [ ] **5.12 Building Destruction & Ruins (extends `BuildingInstance`/`BuildingManager`, Phase 2.1)** — plan only. **Decided (They Are Billions convention):** a destroyed building doesn't disappear — it becomes a Ruins state that stays on the map, a visible scar rather than empty ground.
  - [ ] New `BuildingInstance` health pool (same spirit as walls' own toughness in Phase 4.1, scaling with construction tier/cost) — reduced by an active siege only once the layers in front of it have actually failed (Phase 4.2's cascade: wall -> legacy wall -> garrison -> buildings), not the instant a horde shows up anywhere nearby.
  - [ ] At zero health, the building flips to `is_ruined = true`: stops producing/consuming anything and stops housing population, and renders as a distinct rubble state (code-drawn placeholder, same convention as everything else) instead of being removed from `BuildingManager`'s records.
  - [ ] Whatever `current_population` (Phase 2.10) the building held at the moment of destruction converts to zombies right there — a Phase 5.9 casualty event, same as a starvation death, just triggered by direct assault instead of hunger.
  - [ ] Ruins are inert until the district is recaptured (Phase 5.8), at which point the player can clear a ruin (cheap, fast, empties the plot) or rebuild on the same footprint. Whether a rebuild is discounted vs. fresh construction is a balancing call, not an architecture one.

---

## 🖥️ Phase 6: Background HUD, Alerts & Audio Signals
- [ ] **6.1 Background Play UI & HUD Design (`MainHUD.tscn`)**
  - [ ] Day/Night Phase Clock indicator with countdown timer (e.g., "Nightfall in 04:15").
  - [ ] Threat Meter indicator per sector showing horde attraction levels.
  - [ ] Build/placement menu — the actual UI for `BuildingManager.place_building_at_world()` (built in Phase 2.5, never called by anything since). Without this the game has no way for a human to place a building at all.
  - [ ] Always-visible minimap of the Strategic layer (including Phase 2.7's markers/alerts) while zoomed into Tactical view — the hard-cut zoom (Phase 2.5) otherwise leaves the player with zero awareness of anything happening elsewhere on the map while zoomed into one hex cluster.
- [ ] **6.2 Audio & Desktop Notification Alert System (`AlertManager.gd`)**
  - [ ] Sunset warning chime (e.g., Church bell toll at 2-minute nightfall mark).
  - [ ] Sunrise warning cockrel (e.g., rooster call at 2-minute dayfall mark).
  - [ ] Auto-pause during a wall breach and any other major event.

---

## 🧪 Phase 7: Narrative Campaign, Objectives & Steam Polish
- [ ] **7.1 "The Southern Expedition" Campaign Arc (Manchester to London)**
  - [ ] **Act I: The Cottonopolis & The Pennine Barrier:** Secure Manchester (4 macro-hexes), clear the Chat Moss bogs, and establish defenses across the Peak District passes.
  - [ ] **Act II: The Trent Valley & Fenland Corridors:** Rebuild rail infrastructure through Birmingham, cross the River Trent, and defend supply routes against hordes emerging from the East Anglian Fens.
  - [ ] **Act III: The Thames Basin Citadel:** Breach the Chiltern Hills, secure outer London's 12 macro-hex perimeter, navigate the flooded London Underground, and reclaim Imperial headquarters.
  - [ ] Horde size/frequency (Phase 5.2's starting-small, ramping-up curve) should escalate roughly Act to Act — Manchester's small starting hordes are the tutorial-difficulty end of the same curve, not a separate easy-mode carve-out.
- [ ] **7.2 Major Milestone Objectives System (`CampaignManager.gd`)**
  - [ ] **Primary Objective:** Establish a continuous, defended rail/road logistics link from Manchester to London.
  - [ ] **Secondary Objective:** Investigate regional relic sites (wrecked observatories, strange craters) revealing alien spore origins.
  - [ ] **Final Mystery:** Uncover the fate of Queen Victoria and the Imperial Cabinet inside the sealed Tower of London bunker.
- [ ] **7.3 Playtesting & Steam Integration**
  - [ ] Balance multi-week campaign progression from Manchester down to London.
  - [ ] Implement Steam Cloud Saves, Achievements, and Steam Deck controller layout support.
- [ ] **7.4 Post-Campaign UK Liberation** — plan only. **Decided:** not a separate "Endless mode" menu option — completing the Manchester-to-London campaign (7.1) unlocks the rest of the UK directly, with the campaign itself serving as the onboarding/tutorial arc for everything built in Phases 1-6.
  - [ ] Scotland, Wales and Ireland become new long-term regional objectives on the same persistent map/save, each with its own geography (new `BritishGeographyData`-style seed content) and campaign-style milestones (7.2's pattern), rather than one generic "keep surviving" mode.
  - [ ] Reuses every system built through Phase 6 as-is — hex map, buildings, economy, ZoC, Discontent regions, tech tree — none of it is campaign-specific, which is what makes this cheap to add on top rather than a second game.
- [ ] **7.5 Naval Logistics & Seafaring (Ireland Unlock)** — plan only, and the biggest net-new system in this list. Ireland was part of the UK in 1890 and is only reachable by sea, so reclaiming it needs a genuinely new transport layer: ports (a new building), ships (a new unit-like entity with its own pathfinding over open-water hexes rather than land — see 5.5), and sea supply lines as a `LogisticsNetwork` segment type alongside road/rail/canal. Scope this properly as its own phase when it's actually picked up rather than bolting it onto 7.4 — recorded here so the Ireland objective doesn't quietly assume it away.
- [ ] **7.6 Difficulty, Win/Loss & New Game Setup** — plan only.
  - [ ] **Decided: defeat is an economic/capability elimination check, not a territorial one.** The game only ends when the player simultaneously has (a) zero stockpiled resources across every `ResourceManager` type, (b) zero total daily production from anything still standing, and (c) no remaining building capable of recruiting a unit or expanding onto a new hex. Holding even a single settlement with any one of those intact means the game continues — losing every territory but one is a crisis, not a loss condition. (Check (c) depends on Phase 5.4's recruitment mechanic existing to evaluate against.)
  - [ ] Recovering from near-total loss is meant to be *possible in principle but hard in practice*: Phase 5.8 (Territory Capture & Loss) is what lets a lost district be recaptured at all, and Phase 5.9 (Casualty Conversion) is what makes recapturing it genuinely difficult — a densely populated settlement that falls converts its own people into the zombies now defending it, so the hardest place to retake is exactly the one most worth retaking.
  - [ ] Difficulty presets (horde aggression/frequency, upkeep drain rates) and starting-map/seed choice at New Game — this is the tuning knob on top of Phase 5.2's baseline starting-small/ramping-up curve, not a separate system.
- [ ] **7.7 Future Expansion Hook (Continental Europe)** — plan only, no build work now. Confirms the architecture already supports this without rework: axial hex coordinates (`HexCoord`) are unbounded, `BritishGeographyData.MAP_BOUNDS` is a single adjustable constant rather than anything hard-coded deeper into the generator, and named geography is entirely data (`GeographyFeature` seed lists) — a future Europe expansion is "author a new seed data file and raise the bounds," not a rewrite. Naval logistics (7.5) is the actual prerequisite, since Europe is inherently sea-separated from Great Britain.
