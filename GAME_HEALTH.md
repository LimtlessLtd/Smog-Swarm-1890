# Game Health

> Internal development states, **not review scores, ratings or rankings** (D96). Each
> area has one state and the facts that put it there. A state changes only when its
> evidence changes; whoever changes one updates the evidence in the same edit.
>
> **BROKEN** — the area cannot deliver its `PLAYER_EXPERIENCE.md` intent at all.
> **FUNCTIONAL** — the mechanics run end to end, but the experience criteria mostly fail.
> **ENGAGING** — a player would choose to use it; most criteria hold.
> **STRONG** — it carries sessions on its own; criteria hold under playtest.
> **POLISHED** — presentation, audio and edge cases finished.
>
> Evidence tags: **[code]** read from source (file named), **[measured]** from a
> diagnostic or scenario (named), **[playtest]** from a person or the playtest-critic
> agent. Scenario numbers come from `tools/playtest/run_scenarios.py` on the date given
> and go stale with any balance change — re-run before quoting them.

**Last full review: 2026-09-16** (design audit; branch `worktree-design-audit-2026-09-16`).

## 1. Summary

| Area | State | One-line reason |
| :--- | :--- | :--- |
| Core loop | **BROKEN** | The economy runs ~100x slower than movement; loops cannot close inside a session |
| Combat | **FUNCTIONAL** | Clears hexes and kills hordes; no range, roles identical, nothing visible |
| Expansion | **FUNCTIONAL** | Clear-by-killing and build rights work; no reason to want one hex over another |
| Economy | **FUNCTIONAL** | Full chain produces; flat yields, no caps, decisions are build order only |
| Logistics | **BROKEN** | §2.2 unbuilt; supply lines change movement speed only |
| Settlements | **BROKEN** | A second Town Hall shares everything and likely gets no civilian ZoC |
| Horde threat | **FUNCTIONAL** | Hordes are real and lethal; the counterplay chain does not engage in the opening |
| Defence | **FUNCTIONAL** | Walls siege and breach; nothing to do during a siege |
| Strategic progression | **BROKEN** | Tiers unlock lists and a stat ramp; ~80 min to the first tier; no goals |
| Visual feedback | **BROKEN** | No combat presentation; infestation never drawn |
| Audio | **BROKEN** | Master bus muted; five square-wave tones |
| UI/UX | **FUNCTIONAL** | Complete HUD; unlabelled counters, no threat overlay, no objectives |
| Performance | **STRONG** | 60,000 zombies in 2.79 ms; 153 fps tactical; streamed chunks 5 ms worst |

The golden slice (`PLAYER_EXPERIENCE.md` §11) is **not reachable** while Core loop is
BROKEN: its first seven steps need the economy to move on a session's timescale.

## 2. Evidence by area

### Core loop — BROKEN
- [code] `TickManager.DAY_LENGTH_SECONDS` 2400, default speed index 1 = 5x → **8 real
  minutes per in-game day**. Production, construction (1-4 days,
  `BuildingConstructionController`), training (`tier + 1` days, `UnitManager`) and
  research (whole days, `TechManager`) all run on that clock.
- [code] `MovementStepper.BASE_MOVE_SPEED` = one hex per 20 game-seconds → 4 real
  seconds per hex at default speed.
- [measured] `diagnose_horde_contact.gd` (2026-09-07, no player action): hordes reach a
  building on **day 4** (≈32 real min), all buildings ruined by **day 13**; **85.1
  hexes/horde/day = 735 km/day**; **0 of 73** hordes ever ATTRACTED.
- [code] First tier: `building_tier_1` 50 RP, Town Hall 5 RP/day, Research Institute is
  itself Tier 1 → **10 days ≈ 80 real minutes**.
- [code] No objective, milestone or victory condition exists; defeat does (D73).
- **What would move it to FUNCTIONAL:** the pacing [design] item answered and OPEN-1,
  OPEN-2, IND-4 in range in the scenarios.

### Combat — FUNCTIONAL
- [code] `CombatEngine.resolve_engagement()`: one mutual-damage exchange per
  engagement; MELEE, RANGED and SPECIAL resolve identically; `UnitDefinition` has no
  range stat; stats are `max_hp = 20 + 15*tier`, `attack_damage = 3 + 2*tier`
  (`UnitCatalog`).
- [code] Gunpowder is never consumed per shot — `CombatCoordinator._engage()` checks
  `> 0.0` only, against `design_doc.md` §4's "1 Gunpowder/shot".
- [measured] `diagnose_resident_combat.gd`: 50 Holt Breakers clear London in 12 days;
  a Truncheoneer garrison is wiped at London in 3 rounds (D51). Combat *works* as a
  clearing mechanism.
- [code] Morale scales damage 0.6-1.0x, no rout; veterancy counts hordes destroyed
  (inflates on frontage-1 hexes, D51).
- Presentation failures are recorded under Visual feedback.

### Expansion — FUNCTIONAL
- [code] Clearing is killing (D8); build rights by band (`BuildingManager.get_infestation_placement_error()`).
- [code] Yield is flat on every legal hex except farm soil
  (`BuildingInstance`, `soil_fertility_scales_output` on four farms). No deposits.
- [code] D39: exports only within 8 hexes of a player building — expansion toward
  population does raise threat.
- [measured] `expansion` scenario — see §4.

### Economy — FUNCTIONAL
- [code] One global `ResourceManager._stockpile`; storage caps are INF and no catalogue
  entry sets `storage_bonus`.
- [code] Food shortage scales production by the satisfaction ratio; Discontent ≥ 0.7
  cuts production 15%; nothing else.
- [measured] `opening` scenario: 150 starting Wood buys Wooden Houses + Clay Pit + two
  Truncheoneers and **not** the two Toxophilites the same opening asked for.

### Logistics — BROKEN
- [code] `LogisticsNetwork` segments replace the terrain speed multiplier on their edge
  and suppress military ZoC when all severed; `is_supply_connected()` has no production
  caller. Nothing pools or moves resources. §2.2 (D21-D29) is unbuilt.

### Settlements — BROKEN
- [code] A Tier 3 Town Hall can be founded on a Cleared hex;
  `SettlementFoundingController` sets `is_settlement` and grows an urban disc.
- [code, inferred] Civilian ZoC needs a safe district; districts are created only at
  worldgen (`DistrictPartitioner` via `HexMapGenerator`). A founded settlement likely
  projects no civilian ZoC. Unverified — `backlog.md` rank-1 `[gated]` item.
- [code] No second stockpile, no link, no cost beyond construction.

### Horde threat — FUNCTIONAL
- [measured] Hordes are lethal to an undefended colony by day 13 (above).
- [measured] 3 → 33 hordes by day 15 after the fragmentation fix (D74).
- [code] Noise sources are buildings only (`NoiseManager.recompute()`); 17 of 42
  buildings emit, none of the starting three.
- [code] `HUDReconTracker` warns only for a fog-VISIBLE ATTRACTED horde, no bearing;
  strategic marker only for hordes ≥ 100 at Strategic zoom.
- [code] No escalation with time (`HordeManager._on_ambient_spawn_day` ignores the day).
- [measured] `horde` / `horde:dark` scenarios — see §4.

### Defence — FUNCTIONAL
- [code] Walls take per-frame siege damage and breach with a CRITICAL alert, auto-pause,
  pulsing ring and red segment; repair `tier + 1` days.
- [code] No building or wall deals damage; units cannot man walls; after a breach the
  horde reverts to WANDERING (`HordeManager`); garrison order 0.75x damage taken.
- [code] Stale comment: `HordeManager` still describes "Ditch/Oil Pit counter-damage";
  both were cut.
- [measured] `siege` scenario — see §4.

### Strategic progression — BROKEN
- [code] Tech unlock types are WALL_TIER, UNIT_TIER, BUILDING_TIER, SEAFARING plus 36
  per-unit stat upgrades; nothing else changes at a tier (`TechCatalog`).
- [code] Seafaring can never be researched — `set_wales_and_scotland_retaken()` has no
  caller — and no Port building exists.
- [code] New campaign asks only for a name; no difficulty, objectives or tutorial.
- [measured] `industrialisation` scenario — see §4.

### Visual feedback — BROKEN
- [code] No `AnimatedSprite2D`, `SpriteFrames`, `AnimationPlayer` or GPU particles in
  game code; CPU particles only for building smoke/fire.
- [code] Nothing visual listens to `engagement_resolved` or `wall_segment_damaged`; no
  hit flash, projectile, damage number, death effect or on-map health bar.
- [code] No overlay reads `InfestationManager` — the primary threat is never drawn.
- [measured] `05_tactical_crowd.png`: 60,000 residents instantiated, none drawn at
  MEDIUM (D87); the full crowd renders as a carpet at HIGH.
- [measured] Battle-scale figures 46 px at zoom 128 (D76) — the groundwork is sound.

### Audio — BROKEN
- [code] `AlertManager._MUTE_ALL_SOUND = true` mutes the Master bus at startup.
- [code] Five code-generated square-wave tones (`AlertTones`); no audio assets exist.

### UI/UX — FUNCTIONAL
- [code] Resource bar, time controls, day phase, tech tree, save/load, build menu,
  minimap, unit panel, toasts, strategic overlays (buildings, units, hordes ≥ 100,
  frontier, walls, ZoC, noise, attack alerts).
- [playtest 2026-08-17] 6 of 15 counters unidentifiable; no tooltips; status line never
  cleared; Tech Tree rendered black for part of a session.

### Performance — STRONG
- [measured] `bench_zombie_swarm.gd`: 60,000 zombies stepped in 2.79 ms.
- [measured] Tactical view 20.8 → 153.6 fps after D70-D71.
- [measured] Chunk streaming main-thread cost 124 ms → 1.64 ms mean, 5.09 ms worst.
- [measured, PR #108 open] sprite VRAM 1,446 MB → 362 MB.
- [code] Not POLISHED: relief tiles will not load in an exported build (`backlog.md`).

## 3. Systems against the loops

Every implemented system and the loops it serves (`PLAYER_EXPERIENCE.md` §2). A system
serving none is flagged.

| System | Micro | Local | Regional | Industrial | Strategic | Campaign |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| Real-geography terrain, sub-hex layer | | ● | ● | | ● | ● |
| Population-derived capacity (D3) | | ● | | | ● | ● |
| Infestation bands, breed/export | | ● | ● | | ● | ● |
| Resident combat (D48-D51) | ● | ● | | | | |
| Tactical zombie layer / battle scale | ● | | | | ● | |
| Horde AI, attraction | ● | | | | ● | |
| Noise propagation (dB) | | | | ● | ● | |
| Going dark | | | | ● | ● | |
| Walls, gates, siege | ● | ● | | | ● | |
| Units, orders, morale, veterancy | ● | ● | | | | |
| Economy chain, capacity pools | | ● | | ● | | |
| Tech tree | | | | ● | | ● |
| Settlement founding | | | ● | | | ● |
| Supply lines (movement only) | | | ● | | | |
| Fog of war, day/night | ● | ● | | | ● | |
| Reclamation (drain marsh, un-sever) | | ● | ● | | | |
| Discontent | | | | ● | | |
| Defeat monitor | | | | | | ● |
| Save/load | | | | | | ● |
| `TerritoryController` (district contested/lost) | | ● | | | | |
| `BackgroundExecutionManager` | — | — | — | — | — | — |
| Seafaring tech | — | — | — | — | — | — |

**Flagged:**
- **`BackgroundExecutionManager`** serves no loop by design — it keeps the world running
  on alt-tab (`vision.md` §1). It is also the source of two harness traps (D72, D75).
  Keep; no action.
- **Seafaring** is unreachable (no caller for its gate, no Port). It belongs to cut-order
  item Naval/Ireland (`vision.md` §4). Leave dormant; do not build on it.
- **`TerritoryController`** and infestation are two per-hex notions of "trouble" (D41).
  Serves Local only; worth re-reading when settlements are worked on, since its safe
  districts feed civilian ZoC.
- **Discontent** serves Industrial weakly (a 15% production cut at 0.7) with no player
  decision attached. Review when the economy is paced.

## 4. Scenario evidence

Pending the 2026-09-16 run.
