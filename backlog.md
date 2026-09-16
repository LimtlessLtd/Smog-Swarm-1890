# Backlog

Everything not yet built. **Read the index; grep the detail.** Full detail for
inherited items is preserved below the index under "Detail (inherited from todo.md)".

**This is the implementation queue.** `PLAYER_EXPERIENCE.md` is the experience
authority, `design_doc.md` the mechanics/numbers authority, `decisions.md` the record of
settled calls, `GAME_HEALTH.md` the current state. Restructured 2026-09-16 (D94-D95):
work is chosen by player impact, not by the next unchecked line.

**Tags** — what it takes to know an item is done (`CLAUDE.md` §0.2):
- `[gated]` — a script or test can verify it. Unattended loop: yes.
- `[visual-autonomous]` — only a render can verify it, and the agent can capture and
  inspect one. Unattended loop: **yes; not to be avoided for being visual.**
- `[visual-human]` — needs a person's judgement of taste or feel.
- `[design]` — needs a user decision before any code.

Items tagged `[visual-autonomous]` before 2026-09-16 were retagged `[visual-autonomous]` unless
their entry says otherwise.

**Sections** — from `vision.md` §5's three checks. An item fails check 3 (solves a
problem that only exists after the core loop works) → Deferred, however well specified.
Within Now, **the priority index below decides order**, using `CLAUDE.md` §0.2's list.

**New items carry four parts:** **WHY** (which priority and which
`PLAYER_EXPERIENCE.md` criterion), **PLAYER EXPERIENCE** (the five player-impact
answers, briefly), **IMPLEMENTATION**, **VERIFICATION** (gate + scenario or render).
Older items predate this and are kept verbatim; bring one into the format when it is
taken.

---

## Now — priority index (2026-09-16, D94)

The golden slice (`PLAYER_EXPERIENCE.md` §11) is the target. Ranked by `CLAUDE.md`
§0.2; within a rank, actionable-unattended first. Items marked **new** are detailed in
"Golden-slice items" directly below; the rest point at entries further down.

| Rank | Item | Tag | Criteria |
| :--- | :--- | :--- | :--- |
| 1 Broken | **new** — The economy clock is ~100x slower than the movement clock | `[design]` | OPEN-1, OPEN-2, IND-4, HORDE-2 |
| 1 Broken | ↳ *The undefended colony is destroyed on day 13* (below) | `[design]` | OPEN-4 |
| 1 Broken | ↳ *A horde crosses Britain in a day and a half* (below) | `[design]` | HORDE-2 |
| 1 Broken | **new** — Does a founded Town Hall get civilian ZoC? | `[gated]` | SET-1 |
| 1 Broken | **new** — An unroutable move order re-runs a ~234 ms failed search every 2 game-seconds | `[gated]` | COMBAT-1, FB-2 |
| 1 Broken | **new** — A new game starts unwalled: `seed_starting_defenses()` has no production caller | `[gated]` | OPEN-4, DEF-1 |
| 1 Broken | **new** — The first expansion from the real start is into Manchester's own 68,075 zombies | `[design]` | EXP-1, OPEN-2 |
| 2 Boring | *The ATTRACTED mechanic never fires in the opening* (below) | `[design]` | HORDE-3, HORDE-4 |
| 2 Boring | **new** — Units and gunfire make no noise | `[design]` | HORDE-3, HORDE-5, IND-5 |
| 2 Boring | **new** — How threat escalates inside an open campaign | `[design]` | OPEN-2, §9 |
| 3 Feedback | **new** — Infestation is never drawn on the map | `[visual-autonomous]` | FB-1, EXP-5 |
| 3 Feedback | **new** — Combat has no on-screen presentation | `[visual-autonomous]` | COMBAT-2..6 |
| 3 Feedback | **new** — The horde warning misses wandering hordes and gives no bearing | `[gated]` | HORDE-1, HORDE-2, FB-2 |
| 3 Feedback | *Placement status line is never cleared* (Next) | `[gated]` | OPEN-5 |
| 3 Feedback | *6 of 15 resource counters have no icon, name or tooltip* (Next) | `[visual-autonomous]` | FB-3 |
| 3 Feedback | **new** — At battle zoom one building fills the screen | `[visual-autonomous]` | COMBAT-3 |
| 3 Feedback | **new** — The game is silent | `[visual-human]` | COMBAT-4, §13 |
| 4 Decisions | **new** — Ranged units have no range; gunpowder is never spent | `[design]` | COMBAT-7, IND-2 |
| 4 Decisions | **new** — Why want this hex: deposits and city value | `[design]` | EXP-2, EXP-5, §8 |
| 4 Decisions | *Should the Town Hall / ZoC / building sites go dark* (below) | `[design]` | HORDE-5 |
| 5 Pacing | *Infestation balance pass* (below) | `[design]` | — |
| 6 Horde | *Walls block bleed proportionally — blocked* (below) | `[design]` | DEF-2 |
| 6 Horde | *`HordeManager` stuck-detection/bypass* (Next) | `[gated]` | — |
| 6 Horde | **new** — Hordes on the map grow 4 → 306 in 60 days with no player input | `[gated]` | HORDE-6, performance |
| 7-8 Expansion/logistics | *Per-settlement stockpiles*, *logistics geometry*, *terminals*, *§2.1 ZoC consequences* (Next/below) | `[gated]` | SET-1, SET-2, LOG-1..4 |
| 9 Capability | **new** — Historical coherence review | `[design]` | §7.1 |
| 10 Polish | *MEDIUM -> HIGH pop*, *camera-rect allocation*, *urban clustering*, *stride A/B* (Battle scale, below) | mixed | COMBAT-3, readability |
| 11 Performance | *Relief tiles will not load in an exported build*, *`portal_offset_for_step()`* (Next) | `[gated]` | — |

**Why battle scale sits at rank 10 and not at the top of Now any more:** it is
presentation groundwork. The camera-rect allocation (D78) and the stride A/B (D84) are
what *pay for* combat presentation, so take them when the combat-presentation item
needs them, not ahead of it.

### Golden-slice items (new 2026-09-16)

- [ ] `[design]` **The economy clock is ~100x slower than the movement clock.**
  **WHY:** rank 1 — the session structure in `PLAYER_EXPERIENCE.md` §3 cannot happen.
  `TickManager.DAY_LENGTH_SECONDS` 2400 at default speed 5x = **8 real minutes per
  day**. Construction 1-4 days, training `tier+1` days, production and research once a
  day; the first `building_tier_1` needs 50 RP against the Town Hall's 5 RP/day = **~80
  real minutes**. Meanwhile a horde moves a hex per 20 game-seconds = 4 real seconds.
  So in the first hour: ~7.5 production ticks, the first building stands after 8
  minutes, and a horde from 4 hexes out arrives in 16 seconds. This one number sits
  under three existing items (day-13 colony loss, 735 km/day hordes, resource-tick
  pacing) and they should be answered together.
  **PLAYER EXPERIENCE:** the player gets to act within the first minute and sees the
  colony change every few minutes (OPEN-1); a horde's approach is something to respond
  to rather than a surprise (HORDE-2); a tier arrives inside a session (IND-4).
  **IMPLEMENTATION — options, not decided:** (a) keep the day, express construction,
  training and research in hours (`BuildingConstructionController._MIN_DAYS`, the
  training formula, `TechDefinition.research_days`) and tick production more than once
  a day — the catch-up-safety constraint in the resource-tick item applies;
  (b) shorten the day; (c) split `MovementStepper.BASE_MOVE_SPEED` so hordes travel at
  walking pace while units keep theirs; (d) change the default speed.
  *Recommendation:* (a) plus (c) — (a) moves the economy onto the scale of a session
  without changing the day/night rhythm that noise, light and horde speed already hang
  off, and (c) is what §2.1 already assumes when it says zombies have "a predictable
  cross-country travel time". (b) and (d) rescale everything at once, including the
  things that are already right.
  **VERIFICATION:** `run_scenarios.py opening expansion industrialisation` before and
  after; OPEN-1, OPEN-2, EXP-1 and IND-4 move into range; `diagnose_horde_contact.gd`
  for km/day.

- [ ] `[gated]` **Does a Town Hall founded after worldgen get civilian ZoC?**
  **WHY:** rank 1 if true — the second settlement is D21's whole logistics premise.
  Inferred from the code, not measured: `LogisticsNetwork` requires a safe district for
  civilian ZoC; safe districts are created only by `DistrictPartitioner` at map
  generation for hexes that were settlements then; `SettlementFoundingController` sets
  `is_settlement` but creates no district. So a founded settlement may project no
  civilian ZoC, and `DiscontentManager` regions (built from it) would exclude it.
  **PLAYER EXPERIENCE:** founding a settlement grants territory (SET-1).
  **IMPLEMENTATION:** write the verification first (found a Town Hall on a cleared
  non-settlement hex, complete construction, assert civilian ZoC covers it). If it
  fails, the district creation belongs with the founding event, through a public method
  on whichever class owns districts — not by `SettlementFoundingController` writing
  another class's fields (`CLAUDE.md` §1).
  **VERIFICATION:** new `verify_settlement_founding_zoc.gd`, mutation-tested.

- [ ] `[gated]` **An unroutable move order re-runs a ~234 ms failed path search every 2
  game-seconds.** **WHY:** rank 1 — found 2026-09-16 by the playtest runner's
  per-manager timing, and diagnosed by instrumenting `UnitOrderController` (reverted, not
  committed). Opening scenario: two Truncheoneers attack-moved from the walled starting
  settlement (79, 118) to its neighbour (78, 119). `HexPathfinder.find_path()` (gates
  passable) returns no route; `_replan_with_backoff()` retries every
  `REPLAN_RETRY_SECONDS` = 2.0 game-seconds, and each failed search measured **~234 ms**
  (46.7 s per 200 calls) — **214 s of wall time per simulated day for two units**, while
  hordes, residents and fog together cost ~2 s. At default 5x that is one 234 ms stall
  per unit every 0.4 real seconds for as long as the order stands; at 1000x it is every
  frame. The units never moved. *An earlier note here blamed per-prop obstacle
  dictionaries; removing `TerrainDetailView` changed nothing, so that was wrong.*
  **Two questions in one:** (1) why (78, 119) — passable at hex level, adjacent — has no
  unit route out of the start hex (starting walls/gate placement, a boundary rule, or a
  water crossing; the runner now notes every such hex); (2) why a failed search is so
  expensive — an unreachable goal expands the whole reachable region of the map.
  **PLAYER EXPERIENCE:** a move order either works or says immediately why not, and the
  game never stutters because of one (COMBAT-1, FB-2; `move_order_unreachable` already
  exists and fires once).
  **IMPLEMENTATION:** measure first with `diagnose_route_failure.gd` adapted to a fresh
  map. Candidates: bound failed searches (a node budget, or a cheap connectivity check
  before A*), back off exponentially rather than every 2 game-seconds, and fix the
  starting-hex route if the walls are the cause. `verify_gates.gd` and
  `verify_unit_border_crossing.gd` must still pass; enumerate every caller of
  `find_path()` (`CLAUDE.md` §3 trap).
  **VERIFICATION:** a verification that an unroutable order costs bounded time per game
  second; `run_scenarios.py opening` with the target forced to (78, 119).

- [ ] `[gated]` **A new game starts unwalled.** **WHY:** rank 1 — measured 2026-09-16:
  `WallManager.seed_starting_defenses()` has no production caller (only
  `verify_gates.gd` calls it), while `WallManager`'s doc comment says it "Runs from
  _ready()" and `BuildingManager` places its starting Farm on the assumption that the
  start hex is fenced. The siege scenario had to call it itself (96 pieces). Either the
  call was dropped by accident or the walls were removed on purpose and the comments
  are stale — check `git log -S seed_starting_defenses` before choosing.
  **PLAYER EXPERIENCE:** the opening has the defensive footing its own code assumes
  (OPEN-4, DEF-1). **IMPLEMENTATION:** restore the call where the comment says, or delete
  the stale comments if removal was deliberate. **VERIFICATION:** a verification that a
  fresh `Main.tscn` has wall segments around the start; `run_scenarios.py opening`.

- [ ] `[design]` **The first expansion from the real start is into Manchester's own
  zombies.** **WHY:** rank 1 — measured 2026-09-16: the start (79, 118) is a Manchester
  hex (D35), so its ring 1 at D7's 25% is Manchester too; the least-populated routable
  neighbour holds **68,075 zombies** (capacity 272,298, frontage 3 per D49). Twelve Tier
  0 units attack-moved in and all died the same day; the D51 table already says a
  Truncheoneer garrison "wiped in 76 rounds" there. So the golden slice's "first
  clearing operation" (§11 step 5) is not winnable at Tier 0 from the real start.
  **PLAYER EXPERIENCE:** the first push out is hard but winnable, and the map's density
  gradient is something to choose against (EXP-1, EXP-5). **IMPLEMENTATION — options:**
  (a) D7's rings are a fraction of each hex's capacity, so a city start is harsh by
  construction — seed ring 1 by an absolute count or a lower fraction for dense hexes;
  (b) start on the edge of Manchester rather than inside it; (c) accept it and give Tier
  0 a lower-density direction to expand (moorland toward the Pennines) and make that
  readable (the infestation overlay item). *Recommendation:* (c) first — it is the
  cheapest, keeps "history decides the difficulty curve" (D3), and the scenario can
  measure whether any routable neighbour is winnable. **VERIFICATION:**
  `run_scenarios.py expansion` EXP-1 in range.

- [ ] `[gated]` **Hordes on the map grow 4 → 306 in 60 days with no player input.**
  **WHY:** rank 6 — measured 2026-09-16 (`industrialisation` scenario, no units): the
  count climbs roughly linearly after D74's fix (33 at day 15 matches D74; it does not
  plateau), and simulation wall time per day rises 1.7 s → 31 s with it. Contributors on
  the day ticks: ambient spawns (35%/day), one export per day (D39), splits, and
  defending waves that wander off (D51). **PLAYER EXPERIENCE:** threat that accumulates
  into masses rather than a growing confetti of hordes (HORDE-6); frame time that does
  not decay over a long campaign. **IMPLEMENTATION:** measure first which source
  dominates (`diagnose_horde_contact.gd --days 60` split by spawn source); merging and
  export sizing are balance knobs, so a structural cap would be `[design]`.
  **VERIFICATION:** 60-day count and per-day wall time.

- [ ] `[design]` **Units and gunfire make no noise.** **WHY:** rank 2 — the P2 chain
  (`PLAYER_EXPERIENCE.md` §5.5) has no link between fighting and attention, and "draw
  the horde away with some military units" (the user, `vision.md` P2) has no mechanism.
  `NoiseManager.recompute()` iterates buildings only. §6 makes gunfire the loudest
  routine event; D66 records that its tactical table must not be applied at the
  strategic layer literally. **PLAYER EXPERIENCE:** firing has a cost (HORDE-5);
  a decoy force is a real play; bows vs rifles becomes a choice (COMBAT-7).
  **IMPLEMENTATION — needs deciding:** the strategic reach of combat noise (a transient
  per-engagement dB source through `NoisePropagation`, decaying over a logic tick or
  two, is the shape that reuses D66-D69), and whether melee/bows are silent. Same gap as
  the §6 item's step (d) under Deferred, pulled forward because the opening depends on
  it. **VERIFICATION:** `horde` scenario HORDE-3 with units fighting near the colony;
  `verify_noise_emission.gd` extended.

- [ ] `[design]` **How threat escalates inside an open campaign.** **WHY:** rank 2 —
  D92 settles that the campaign is not a fixed-length TAB map, which closes the inherited
  "nothing escalates" item's fixed-schedule proposal but not its question.
  `HordeManager._on_ambient_spawn_day` ignores the day, and escalation today is purely
  spatial (D39: exports wake as the player approaches). **PLAYER EXPERIENCE:** the
  player is never safe to strip the walls (§9 "nothing dangerous happening") without the
  run becoming a timer. **IMPLEMENTATION — options:** (a) spatial only — escalation is
  the map (census density and D39) and the player's own noise; (b) time pressure too —
  ambient spawn size/rate grows with days survived; (c) activity-driven — escalation
  follows the colony's total noise/industry, so growth itself is the clock.
  *Recommendation:* (c) layered on (a): it is the user's causal chain ("INDUSTRIAL
  ACTIVITY → … → MORE THREAT") taken literally and needs no calendar. **VERIFICATION:**
  a 60-day `opening` run (`--days=60`) with a scripted growing economy; time between
  threats in telemetry `events`.

- [ ] `[visual-autonomous]` **Infestation is never drawn on the map.** **WHY:** rank 3 —
  the game's primary strategic threat (P1) has no overlay: no UI, overlay or view file
  reads `InfestationManager.band_at`/`infestation_at`. The player cannot see which hex is
  Cleared, Fringe, Contested or Hive Core, and so cannot answer "why do I want this hex"
  or "where will the next horde come from". **PLAYER EXPERIENCE:** the map shows the
  frontier of reclaimed Britain (the campaign fantasy made visible), which hexes are
  buildable, and where exports come from (FB-1, EXP-5). **IMPLEMENTATION:** a renderer
  under `StrategicOverlayManager`, shape-plus-colour per band (`todo.md`'s accessibility
  rule: never colour alone), drawn only on EXPLORED hexes, updated from
  `InfestationManager.band_changed` (push, not polling — `CLAUDE.md` §1), toggleable like
  the other overlays; an iterator over the non-Cleared set if a per-frame walk is
  needed (D70). **VERIFICATION:** a verification that the renderer's hex set follows
  `band_changed`; windowed `smoke_screenshot.tscn` 01/02 framings **inspected**; before
  and after PNGs in the PR.

- [ ] `[visual-autonomous]` **Combat has no on-screen presentation.** **WHY:** rank 3 —
  COMBAT-2..6 all fail today: no attack animation, projectile, muzzle flash, hit flash,
  damage number, death effect or on-map health bar; nothing but `EventManager` listens
  to `CombatCoordinator.engagement_resolved`, and nothing at all to
  `WallManager.wall_segment_damaged`. A fight is static figures thinning out.
  **PLAYER EXPERIENCE:** the player can see who is fighting whom, that hits land, what
  died, and whether the line is holding — the minimum for "Hold the wall" to mean
  anything. **IMPLEMENTATION:** first increment inside the existing model, no combat
  rule changes: at HIGH fidelity, a per-engagement flash/tracer from unit figures toward
  the crowd, a hit flash on the crowd, figures removed with a brief fall/fade rather
  than vanishing, and a wall-impact effect on `wall_segment_damaged`. Driven by the
  signals, in a view class, not in `CombatCoordinator` (`CLAUDE.md` §1). The D78/D84
  battle-scale items pay for per-entity work if the first increment needs it.
  **VERIFICATION:** `run_scenarios.py siege --shots` at the battle-scale framing,
  **PNGs inspected**; frame cost with `bench_zombie_render.gd` if anything per-entity
  lands.

- [ ] `[gated]` **The horde warning misses wandering hordes and gives no bearing.**
  **WHY:** rank 3 — `HUDReconTracker` shows only a fog-VISIBLE horde in ATTRACTED
  state; most hordes that reach the colony WANDER there (0 of 73 ATTRACTED, D74 run),
  so the colony is hit with no warning. TAB's reference is an ETA and a compass bearing
  (inherited escalation item). **PLAYER EXPERIENCE:** "Oh shit, that horde is much
  bigger than I expected" needs to be *seen*: size, direction, time (HORDE-1, HORDE-2,
  FB-2). **IMPLEMENTATION:** extend the tracker to any visible horde whose path or
  heading closes on a player building, with bearing and size class; ETA from
  `HordeManager.get_eta_seconds()`. **VERIFICATION:** a verification over a fixture
  horde wandering toward a building; `horde` scenario HORDE-1.

- [ ] `[visual-autonomous]` **At battle zoom one building fills the screen.** **WHY:** rank 3 —
  observed 2026-09-16 in `playtest_shots/siege/day03_zoom60_0.png` (`run_scenarios.py
  --shots siege`, image inspected): centred on the starting settlement at zoom 60, a
  building's outline art covers the whole 1920x1080 frame. D86 made figures metric at
  HIGH fidelity; buildings were not part of that change. The battle-scale band is where
  "Hold the wall" is supposed to be watched, and today a settlement is unreadable there.
  **PLAYER EXPERIENCE:** at battle zoom the player sees buildings, walls, units and the
  crowd at consistent scale (COMBAT-3). **IMPLEMENTATION:** find which view draws the
  building at that zoom (`TacticalHexView`/`BuildingVisuals`) and give it D86's metric
  rule; check the smoke shot `06_battle_scale` too (framed one hex off the settlement,
  so it may not show this). **VERIFICATION:** `--shots siege` zoom-60 PNG inspected
  before/after; `smoke_screenshot.tscn` all framings.

- [ ] `[visual-human]` **The game is silent.** **WHY:** rank 3 — `AlertManager._MUTE_ALL_SOUND`
  is `true`, muting the Master bus at startup, and the only sounds are five square-wave
  tones. Why it was muted is not recorded. **PLAYER EXPERIENCE:** warnings that do not
  need eyes; weapon identity; the audio roadmap in `PLAYER_EXPERIENCE.md` §13.
  **IMPLEMENTATION:** ask the user why it is muted before unmuting; then roadmap layer 1
  (warnings). **VERIFICATION:** a person listens.

- [ ] `[design]` **Ranged units have no range, and gunpowder is never spent.** **WHY:**
  rank 4 — `CombatEngine` resolves MELEE, RANGED and SPECIAL identically as a same-hex
  exchange; `UnitDefinition` has no range. `design_doc.md` §4 specifies "1
  Gunpowder/shot", but `CombatCoordinator` only checks the stockpile is above zero.
  **PLAYER EXPERIENCE:** army composition is a decision; ammunition is a siege resource
  (§5.7); Tier 1 firearms feel like a new era (IND-2). **IMPLEMENTATION — needs
  deciding:** per-shot consumption is already specified and could be `[gated]` on its
  own, but at today's 20 s rounds it is a balance change to every ranged unit, so it
  wants the user's nod. Range belongs to §6's tactical layer (Deferred) — the question
  is whether a minimal range (engage an adjacent hex, or within N m at HIGH fidelity)
  comes first. **VERIFICATION:** `siege` DEF-3; `diagnose_resident_combat.gd` re-run.

- [ ] `[design]` **Why want this hex: resource deposits and city value.** **WHY:**
  rank 4 — output is flat on every legal hex (only farm soil varies), and a city differs
  from an empty hex only in threat and placement permissions (`PLAYER_EXPERIENCE.md`
  §8). The user has already chosen "real deposits that gate mines" (countryside item,
  2026-08-19). **PLAYER EXPERIENCE:** "Now I need that coal." / "If I clear that city,
  I can build the next part of my industrial network." (EXP-2, EXP-5).
  **IMPLEMENTATION — needs deciding:** the deposit data source (BGS/GSI, `design_doc.md`
  §5 PLANNED) and whether deposits are finite; for cities, which of the existing scoped
  items carries the reward (1890s roads/rail converging on cities, salvageable ruins
  from real settlement data, a larger urban extent) — no arbitrary bonus.
  **VERIFICATION:** `expansion` EXP-2 against a deposit hex.

- [ ] `[design]` **Historical coherence review.** **WHY:** rank 9 — D97; the Tier 4-5
  catalogue and the design doc's "1890s-1920s" title drift toward First World War
  vocabulary. **PLAYER EXPERIENCE:** the late game still feels like Victorian industry
  pushed to its limit. **IMPLEMENTATION:** user decides keep / rename / rework per
  flagged item (`PLAYER_EXPERIENCE.md` §7.1); renames are data-only. **VERIFICATION:**
  gate only.

## Now — the core loop (P1, P2)

Everything here traces to `design_doc.md` §2.1/§2.2 and `decisions.md` D1-D29. Rough
dependency order.

### Battle scale (D76-D80) — settled 2026-09-07, the user's call

The tactical view gets close enough to see a person, and what is drawn is culled to
the view rather than to the hex. Rough dependency order; each item is independently
shippable and independently visible.

- [x] `[gated]` **Crop unit/zombie/prop sprites to their own content.** Done 2026-09-07.
  `UnitVisuals`/`ZombieVisuals`/`PropVisuals` return
  `TextureCropUtil.tight_crop_copy()`, so every consumer is fixed at once rather than
  each renderer separately. Measured fills: `zombie_0_s.png` **22.3% x 40.3%**,
  `redcoat_s.png` **30.8% x 49.9%**, `rock.png` 57.1% x 48.8%, `tree.png` 85.0% x
  80.4%. A **copy**, not `tight_crop()`'s AtlasTexture view: a MultiMesh takes a
  texture RID and `AtlasTexture.get_rid()` is its atlas's, so the region is dropped —
  probed, see D88.
- [ ] `[gated]` **Texture import is uncompressed.** *(PR #108 open, 2026-09-16.)* `compress/mode=0` on every 2048^2
  PNG means RGBA8 in VRAM: **16.8 MB per texture**, in `static var` caches that are
  never evicted (`UnitVisuals._texture_cache`, `ZombieVisuals._texture_cache`). 264 MB
  on disk across `assets/units|zombies|buildings|props`. **Smaller than it was since
  the crop landed** — a cropped `redcoat` facing is 631x1022 = 2.5 MB, so 18 unit types
  x 8 facings is ~350 MB rather than 2.4 GB (extrapolated from one measured asset).
  Still worth VRAM compression, and the real on-screen size is now known: a figure is
  17-46 px, so a 2048^2 source is ~40x the resolution anything samples. **Set
  `mipmaps/generate` with it** — it is `false` on every asset, which was harmless while
  figures were a sub-pixel smear and is not now: a 457x825 cropped zombie minified to
  17 px without mipmaps shimmers across a moving crowd, which is the worst case the
  battle-scale band exists to show.
- [x] `[gated]` **Recalibrate horde spread — it was ~77x too wide.** (D80) Done
  2026-09-07. `ZombieSwarmManager.HORDE_BASE_SPREAD` 20.0 -> 0.2588, so
  `_horde_spread(3758)` returns 7.09 wu = 69 m instead of 548 wu = 5.35 km. Measured
  before changing it, because the mill step was tuned against the old value: nothing
  snaps at any size, and only hordes under ~50 sit looser than their own spread — see
  D90 for the table.
- [x] `[visual-autonomous]` **Raise `max_zoom` 12 -> 128 and add the metric figure band.**
  (D76, D86) Done 2026-09-07. The closest zoom showed **1,040 m** of ground and now
  shows 97.5 m, where a 3.5 m figure reads at 46 px. Figure size is metric exactly
  where HIGH fidelity is active and the world-space icon radii apply everywhere below,
  so LOW/MEDIUM behave as they did. `smoke_screenshot.gd` gained `06_battle_scale` at
  zoom 60. Squad scatter had to come with it (D89) — 20 wu is 195 m, which reads as a
  formation only while a figure is itself ~117 m.
- [ ] `[gated]` **Allocate the entity budget to the camera rect, not the hex.** (D78)
  At zoom 128 the screen is **0.012%** of `RESIDENT_SPREAD`'s disc, so 60,000
  simulated zombies put **7 on screen**. Frees ~2.7 ms/frame at battle zoom
  (`bench_zombie_swarm.gd`: 2.79 ms at 60,000, so ~0.09 ms at 2,000) — which is what
  pays for animation and per-entity combat. The 60,000 budget still serves the
  whole-hex framings; it is redistributed by zoom, not reduced.
- [ ] `[gated]` **Cluster resident zombies on URBAN/INDUSTRIAL sub-cells.** (D79)
  Forced by battle scale and the uncomfortable half of it: spread evenly, a hex at the
  1,000 floor is one zombie per 64,700 m^2 — **0.08 on a battle screen**, one every
  twelve screens, at the exact zoom the player is meant to fight at. Confined to ~2%
  urban area the same hex shows **4 in the town and none in the fields**; London at
  ~5e5 and ~60% urban shows **69**. Reads through `SubHexTerrainQuery.biome_at()` per
  30 m sub-cell as `CLAUDE.md` §3 requires — do not flatten to one value per hex.
- [x] `[gated]` **Bench the crowd render cost.** Done 2026-09-07,
  `scripts/test/bench_zombie_render.gd` (windowed). Settled D81-D84: fill rate is a
  non-issue (120,000 sprites at 75x coverage = **2.93 ms**), the simulation is the
  whole constraint, and the threshold is a legibility choice rather than a budget one.
- [x] `[visual-autonomous]` **Move `high_fidelity_threshold` 2.0 -> 48.0.** Landed 2026-09-07 with
  the `max_zoom` item. Decided 2026-09-07 by
  looking (`scripts/test/preview_crowd_threshold.gd`), settled in D85-D87. **32 was the
  wrong answer and the images said so**: a packed horde at 11.5 px collapses back into
  grain, and `engulfed_032.png` holds the most zombies of any candidate (28,877) while
  being the worst picture. At 48 the view is 260 x 146 m, figures are 17.2 px, an
  engulfing horde is 12,834 individuals at ~0.63 ms. Code change is one exported
  default on `CameraController`; it lands with the `max_zoom` item above.
- [ ] `[visual-autonomous]` **Handle the MEDIUM -> HIGH pop at the threshold.** (D87)
  *Tag note 2026-09-16:* `HANDOFF.md` called this `[design]`. It is a look decision of
  the same kind as D85, which the user delegated ("you make the decision"), so it is
  autonomous — render both options and put the images in the PR. MEDIUM draws
  `MEDIUM_ZOMBIE_CLUSTER_SIZE` = 5 figures per horde and HIGH draws all 12,834, so zoom
  48 is a jump between them in one scroll click. The old 2.0 threshold hid this because
  neither side was legible. Crossfade, or scale MEDIUM's cluster count with zoom.
  **Photographed 2026-09-07, and it is worse than D87 states.** MEDIUM draws
  `MEDIUM_ZOMBIE_CLUSTER_SIZE` figures *per horde* and nothing at all for a hex's
  RESIDENTS, which have no `Horde` to hang a cluster on. `05_tactical_crowd.png` at
  zoom 2.6 stands on a hex holding 60,000 instantiated residents and shows **none of
  them** — clean brick terrain. So the gap is not 5 figures vs 12,834, it is zero vs
  everything, and it now spans 0.1875 to 48 instead of 0.1875 to 2.0: **85% of the
  tactical range by log measure, up from 57%.** Pre-existing, widened by D85.
- [x] `[gated]` **Fold D77's pixel-clamped band into the threshold.** (D86) Done
  2026-09-07 with the `max_zoom` item — `TacticalEntityLayer.METRIC_FIGURE_RADIUS`/
  `METRIC_VEHICLE_RADIUS` apply at HIGH only, `FIGURE_RADIUS`/`VEHICLE_RADIUS`/
  `ZOMBIE_RADIUS` still size LOW/MEDIUM. No separate crossover at 67 was ever built.
- [ ] `[design]` **Unit click tolerance is world-space and battle scale breaks it.**
  `UnitCommandController._UNIT_CLICK_TOLERANCE` is 40.0 wu = 390 m, chosen to cover a
  squad's `FIGURE_SPREAD` scatter. At `max_zoom` 128 the whole screen is 10 wu across,
  so every click anywhere selects the nearest unit within four screens of it; at
  Strategic zoom the same constant is sub-pixel. It wants to be screen-space, or
  band-dependent the way figure size now is (D86). Surfaced by the battle-scale work,
  not caused by it — the constant has always been world-space.
- [ ] `[gated]` **Clean A/B on `ZombieSwarm` stride 8 vs 12 before animation lands.**
  (D84) The stride-12 path measured 25-40% more sim time, but the bench's `_WideCrowd`
  is a faithful-but-not-identical mirror of `ZombieSwarm.step()`, so some of that delta
  may be the loop rather than the stride. Re-measure with the real class at both
  strides and nothing else changed — the animation work has to commit to a buffer
  layout and this is the number that decides it.
- [x] `[design]` **Does per-entity combat buy more than crowd size?** Answered
  2026-09-07 by D81-D84: it was a false trade. Rendering costs roughly a tenth of what
  was feared, so the budget freed by D78 does not have to be spent choosing between
  crowd size and combat detail. Per-entity combat is still unbuilt — combat is one
  abstract mutual-damage exchange (`CombatEngine.resolve_engagement()`) with no
  projectile, no range, no death — but it is now a scope question, not a budget one.
  Scope it to entities within engagement range of a player entity (dozens to low
  hundreds), never the whole crowd.


- [ ] `[design]` **Re-fit `geo_projection.CALIBRATION_POINTS`, or accept it.** Retagged
  from `[gated]` 2026-08-28: there is no single bad row to fix. Both sides of the Warwick
  row are faithful, its 3,539-unit leave-one-out residual is the worst of a spread that
  also holds Pennines north at 3,111 and The Fens at 2,541, and a 12-parameter quadratic
  barely improves the fit (RMS 1,265 → 1,188) — the anchors are hand-drawn, not the model
  wrong. Any re-fit moves the map up to 780 world units (1.5 hexes) against `_LAND_RLE`'s
  coastline and needs every baked product re-run, so it regenerates the map and is the
  user's call. Full measurements in `decisions.md` D36. The one gameplay-visible
  consequence — the projection putting Manchester's population two hex rows off its own
  footprint — is already mitigated by D35.
- [x] `[gated]` **Bake `total_zombie_pop` per hex.** Done 2026-08-28. Wikidata census
  (CC0) → OSM `place` tags (ODbL) → per-kind median → floor 1,000, all scaled to the
  1891 census; `assets/terrain_data/zombie_population.zpop`, read by
  `ZombiePopulationData`. Wikidata coverage was verified at bake time and is far thinner
  than D3 assumed — see D33-D35. (D3)
- [x] `[gated]` **Infestation core.** Done 2026-08-28. `InfestationManager` owns one
  saved count per hex; `infestation`, `is_cleared` and the band are derived. Breeding,
  rate-capped export with the 75% floor, worldgen rings 0/25/50/75/100, and §2.1's Build
  Rights column on buildings and walls. (D1, D2, D4, D7, D8, plus D37-D41 for what the
  spec left open.)
- [ ] `[gated]` **§2.1's ZoC consequences of the band.** Split out of the item above
  rather than half-built: Hive Core "Total Severance", the Contested stockpile split and
  the Fringe -25% logistics efficiency all need a logistics throughput number that does
  not exist yet, and the split needs per-settlement stockpiles. Do it with the §2.2 work
  below, not before. (D40)
- [ ] `[design]` **Should the Town Hall be switchable off?** Raised by the going-dark
  work 2026-08-30 and decided provisionally as NO (`BuildingDefinition.always_powered`,
  D54): it grants +100 Population and +20 Energy into a pool that starts at 0.0, and it
  emits no noise and no light, so blacking it out costs the player their whole capacity
  ledger and buys nothing toward P2. The argument the other way is that the mechanic is
  more interesting if the capital CAN go dark and the player pays for it. One line in
  `BuildingCatalog._town_hall()` either way. It interacts with the ZoC question below,
  so answer both together.
- [ ] `[design]` **Should a building site project Zone of Control?** Raised
  2026-08-30 by the item below it and deliberately not settled there (D62).
  `LogisticsNetwork.recompute()` gates ZoC on `is_ruined` but not on
  `is_under_construction`, so a Watchtower projects Military control — and, since
  `FogOfWarManager` reads ZoC coverage verbatim as vision, reveals a one-hex ring —
  from the frame it is placed, days before it exists. Saying no is one clause in each
  of the two ZoC loops; the cost is that a placed Watchtower or Supply Dump projects
  nothing for its first 1-4 days, which is a territory/supply/Discontent-region change,
  not a vision one. **The argument for saying no got sharper the same day:** with the
  lamp gate landed (D60), an unfinished tower no longer attracts anything at night but
  still projects that aura, so a permanently-unfinished Watchtower is a free, silent
  watchpost — the one place in the game that rewards not finishing a building.
  Answer it with the two ZoC questions below.
- [ ] `[design]` **Should Zone of Control go dark too?** §2.1 enumerates four things an
  off building stops and ZoC is not one of them, so as built a switched-off Watchtower
  or Supply Dump still projects (D55). If it should, it is one clause in
  `LogisticsNetwork.recompute()` plus two signal connections. The cost of saying yes:
  going dark would start losing the player territory and vision coverage, not just
  production — a much heavier trade than the spec describes.
- [x] `[gated]` **`FogOfWarManager` grants full vision to ruins and construction
  sites.** Done 2026-08-30. A ruin emits nothing at all, a construction site sees its
  own hex and casts no lamp, and the three signals that make those land at the moment
  they happen are connected in the same change. Before/after on the gate's own fixture
  at night: a destroyed Watchtower **37 hexes → 0**, a site **37 → 1**. Gated by
  `scripts/test/verify_building_state_emissions.gd`. (D59-D62)
- [x] `[gated]` **A repaired building stays silent until the next day-phase flip.**
  Done 2026-08-30, with the fog item above — same defect, and the same fixture
  measures both. `NoiseManager` now connects `building_repaired` and
  `building_construction_completed`, and its `lit_at_night` term is gated on
  construction (an uninstalled lamp is not lit) while `noise_output` stays
  deliberately loud. Measured: a repaired Watchtower's own hex went **0.0 → 1.0
  attraction at the moment of repair**, where before it stayed 0.0 until the next
  phase flip. (D60, D61)
- [ ] `[design]` **Contested-band decay of non-defensive structures.** §2.1 says
  "Existing non-defensive structures decay while the hex is Contested"; the rate, and
  whether that decay is repairable, are undesigned.
- [ ] `[design]` **Infestation balance pass.** The model runs; its rates are first
  guesses with measurements behind them, not tuned numbers —
  `SPAWN_RATE_PER_DAY` 2%/day, `MAX_EXPORT_FRACTION_PER_DAY` 2.5%/day,
  `EXPORT_MAX_DISTANCE_FROM_PLAYER` 8, `MAX_EXPORTS_PER_DAY` 1. Measured over 60 days
  with no player action: 61,459 zombies exported across 7 new hordes, largest single
  export 3,758. Re-measure with `scripts/test/diagnose_infestation_pressure.gd` after
  any change. (D38)
  Two more knobs joined them 2026-08-29 on the combat side —
  `ResidentDefenseController.ENGAGEMENT_RADIUS_METRES` 30 m and
  `WAVE_INTERVAL_SECONDS` 20 — and the thing to look at first is that the roster's
  heaviest unit kills 6 zombies a round against cities holding 1e5-1e6. Measured
  (`scripts/test/diagnose_resident_combat.gd`): 50 Holt Breakers on secured ground
  clear Greater London in 12 days, Birmingham in 8, Manchester in 5; a Tier 0
  Truncheoneer garrison is wiped in 3 rounds at London and holds only where the
  wave is 1. That curve is defensible, but `Horde.HP_PER_ZOMBIE` 2.0 /
  `DAMAGE_PER_ZOMBIE` 0.5 and `UnitCatalog`'s `3.0 + tier * 2.0` damage were set
  when a horde was 10-25 strong, four orders of magnitude ago.
  Going dark added two more 2026-08-30, both placeholders:
  `BuildingPowerController.RESTART_DAYS_BASE` 1 and `RESTART_DAYS_PER_TIER` 1, so a
  Tier 0 building restarts in 1 day and a Tier 5 in 6. Nothing has been played against
  an actual horde yet — the question is whether 6 days is enough to make banking a
  furnace a real decision, or so much that nobody ever switches one off. (D56)
  The noise rewrite added one that matters more than the rest, 2026-09-01:
  `NoisePropagation.HEARING_THRESHOLD_DB` 5.0. It is the single number deciding how far
  every building in the game reaches, and it was fitted to reproduce the flat 2-hex disc
  it replaced rather than derived from anything. Two consequences to weigh together:
  terrain now takes real ground back (measured around the starting corridor, the mean
  path costs 8.0 dB, so the loudest building pulls 1.67 hexes there against 2.03 on
  clear ground — 82%), and a quiet building is now genuinely local (a Brickworks lights
  its own hex and nothing else over that terrain). Re-measure with
  `scripts/test/diagnose_noise_emission.gd`. (D66)
- [x] `[gated]` **Tactical zombie layer + live-hex LOD.** Done 2026-08-29.
  `LiveHexTracker` owns §2.1's live-hex rule, `ZombieSwarm` holds one crowd in
  packed arrays, `ZombieSwarmManager` splits the 60,000 budget hordes-first then
  residents, both nearest-observer-first, and `TacticalEntityLayer` draws each
  crowd from the simulation's own buffer. Positions saved (468.8 KB full set).
  Measured with `bench_zombie_swarm.gd` and `diagnose_tactical_zombies.gd`.
  (D12-D15, plus D42-D47 for what the spec left open.)
- [x] `[gated]` **Combat against a hex's resident population.** Done 2026-08-29.
  Residents condense into a defending `Horde` rather than becoming a second kind
  of enemy (D48); the wave is a frontage — the residents inside a 30 m disc of
  the hex's own density — so Greater London fields 20 a round and a moorland hex
  fields 1 (D49); it is topped back up between one unit's round and the next, so
  a stack kills in proportion to its size (D50); and a hex holding units and
  hordes now fights continuously (D51). `ResidentDefenseController`, measured
  with `diagnose_resident_combat.gd`. (D48-D51)
- [ ] `[design]` **Crowd density at the full budget.** 60,000 individuals on one
  hex renders as an unbroken carpet with no ground showing
  (`smoke_screenshot.gd`'s `05_tactical_crowd.png`) — faithful to "1.8 million
  behind them", but it leaves no visual room for the buildings and units the
  player is supposed to be reading at the same zoom. The knobs are
  `ZombieSwarmManager.ENTITY_BUDGET` and `RESIDENT_SPREAD`; which way to turn
  them is a look question, not a correctness one.
- [x] `[gated]` **Evict `SubHexTerrainQuery._cache`.** Done 2026-09-01. All three
  properties the item named — unbounded, String-keyed, never evicted — replaced
  together, because the measurement said the key was not the expensive part: 400,000
  distinct sub-cells (under four hexes' worth) cost **324.7 MB at 851 bytes per
  entry**. Now **11.0 MB at 84 bytes per live entry**, capped at 2 x 131,072
  addresses (21.0 MB), with a warm lookup at **2.06 us -> 0.91 us**. A packed
  60-bit address key, interned sample Dictionaries (985 distinct terrain values
  across all 2,661,336 sub-cells of 24 corridor hexes), and a two-generation
  rollover rather than the FIFO cap this item suggested. Measured with
  `scripts/test/bench_subhex_cache.gd`, gated by
  `scripts/test/verify_subhex_cache.gd`. (D63-D65)
  **The justification for moving this to Now was wrong and is left recorded:** the
  live-hex system was expected to fan out sub-hex queries hard, and as built it
  makes none at all — crowds mill in open world space and never ask what terrain is
  under them. That is still a gap (zombies walk through walls and rivers at the
  tactical layer) and still not cache pressure.
- [x] `[gated]` **Buildings can be switched off.** Done 2026-08-30.
  `BuildingPowerController` owns the flag and the restart countdown, mirroring
  `BuildingConstructionController`'s shape so it saves through the same seam;
  production, upkeep, noise, light, Searchlight accuracy, training and the Tactical
  smoke/fire/lamp all stop, the Energy/Population allocation is released and retaken,
  and the restart costs `1 + tier` days. Gated by
  `scripts/test/verify_building_power.gd`. (D11, plus D52-D56 for what the spec left
  open.)
- [x] `[gated]` **Noise emission rewrite.** Done 2026-09-01. `NoisePropagation` owns
  §6's model — a source level in dB at 10 m, geometric spreading, air absorption, and
  §6's woodland/high-ground/mountain rules — and `NoiseManager` keeps the field and the
  signals. `BuildingDefinition.noise_output` (a 0-6 rank) became `noise_source_db` (a
  real level, 80-108 across 17 buildings). Measured: reach now spans **0.85 hexes for a
  Brickworks to 2.03 for a Bessemer complex** where every building used to project the
  identical 2-hex disc; the loudest is calibrated to land where that disc did, so it is
  a change of shape and not of balance. Sources now combine as intensities (four equal
  buildings are +6 dB, not 4x). `scripts/test/verify_noise_emission.gd`,
  `scripts/test/diagnose_noise_emission.gd`. (D10, plus D66-D69)
  **What this item asked for and did NOT get, stated because the wording invites it:**
  §6's radius table is not implemented at this layer and must not be. Every entry in it
  fits inside a twentieth of one hex (artillery, its loudest, is 400 m against a
  8,647 m hex), so implementing it literally deletes the ATTRACTED mechanic. That table
  belongs to a tactical consumer that does not exist yet — see the §6 item under
  Deferred, and `NoisePropagation`'s own header.
- [x] `[gated]` **The campaign can be lost.** Done 2026-09-07. `vision.md` P4
  ("Losing is real") had no implementation — the only loss concept in the game was
  `TerritoryController.is_lost(coord)`, one hex flipping contested. `DefeatConditionMonitor`
  implements 7.6's already-settled condition verbatim: all three of nothing affordable,
  nothing produced and no standing trainer, simultaneously. Emits signals;
  `EventManager` raises the event and `AlertManager`'s existing auto-pause stops the
  clock, so no new pause logic exists anywhere. Gated by
  `scripts/test/verify_defeat_condition.gd` (7 checks, 3 mutations confirmed caught).
  (D73)
- [x] `[gated]` **Hordes stop multiplying into confetti.** Done 2026-09-07, found by
  measurement while investigating something else. `MERGE_CHANCE_PER_TICK`/
  `SPLIT_CHANCE_PER_TICK` were per-day probabilities rolled once per 20-second logic
  tick against a 2400-second day — a factor of 120, so a "5% chance" was **99.8% per
  day**. Measured on the real map with no player action: **3 starting hordes became
  1,092 by day 15**, while the zombies inside them only went 33 to 25,658 — mean horde
  size parked at 23.5, just above `SPLIT_MIN_SIZE`. After: **33 hordes at the same day
  on the same seed**, holding 25,894. Gated by
  `scripts/test/verify_horde_fragmentation.gd`; measured by
  `scripts/test/diagnose_horde_contact.gd` (both new). (D74, D75)
- [ ] `[design]` **The undefended colony is destroyed on day 13, and nothing warns
  first.** Measured 2026-09-07 (`scripts/test/diagnose_horde_contact.gd`), real map, no
  player action: hordes reach a player building on **day 4**, and every player building
  is ruined by **day 13**. After the fragmentation fix above the same run leaves
  buildings standing past day 15, so this is no longer a runaway — but it is still a
  colony with no walls, no units and no warning being taken apart inside a fortnight.
  **This is the "how hard is the opening" question and it needs the user, not a
  default.** *They Are Billions* gives the player roughly ten quiet days before the
  first swarm; the knobs here are `HordeManager.STARTING_HORDE_COUNT`/`_SIZE_*`,
  `MIN_SPAWN_DISTANCE_FROM_SETTLEMENT` (4), `AMBIENT_SPAWN_CHANCE_PER_DAY` (0.35), and
  `InfestationManager.EXPORT_MAX_DISTANCE_FROM_PLAYER` (8) — the last being why
  exported hordes land near the player at all. Note this is the same question the
  escalation item under Deferred asks from the other end, and they should be answered
  together.
- [ ] `[design]` **The ATTRACTED mechanic never fires in the opening, because the
  starting colony is silent.** Measured 2026-09-07
  (`scripts/test/diagnose_horde_contact.gd`), real map, 30 days, no player action:
  **0 of 73 hordes ever entered ATTRACTED.** Not a bug in `NoiseManager` or
  `NoisePropagation` — both work, and `verify_noise_emission.gd` proves it. The cause is
  the catalogue: **17 of 42 buildings carry a `noise_source_db` at all, every one of
  them industrial**, and the three the player starts with (Town Hall, Lumber Yard,
  Smallholding Farm) carry none. So there is nothing to be attracted to until the first
  mine or sawmill goes up, and every horde that reached the colony in that run reached
  it by undirected WANDERING drift.
  **The consequence is the part worth deciding.** Going dark is the player's primary
  counterplay (§2.1) and P2's central trade, and for the whole opening — the phase where
  they are weakest — it buys exactly nothing, because they are already silent and the
  hordes are coming anyway. Options, none of them obviously right: give civil buildings
  a low but nonzero level so a colony is quietly audible in proportion to its size; let
  something other than buildings emit (the unit-and-combat-noise item under Deferred is
  the same gap from the other side, and §6 makes gunfire the loudest routine event in
  the game); or accept it and say the opening is deliberately a drift-pressure phase.
  Re-measure with the diagnostic either way.
- [ ] `[design]` **A horde crosses Britain in a day and a half.** Measured 2026-09-07
  (`scripts/test/diagnose_horde_contact.gd`): **85.1 hexes/horde/day = 735 km/day**,
  which is 8.5 m/s sustained, day and night, across 30 days. `MovementStepper`'s own
  comment already flags why: `BASE_MOVE_SPEED` is "a placeholder balancing number"
  derived to preserve the pre-continuous-movement pace of one hex per 20 seconds, and a
  hex is **8,647 m** of real Britain. §2.1 says the point of denying zombies
  infrastructure is that it "gives hordes a predictable cross-country travel time" and
  "makes early warning meaningful"; at this speed there is no travel time to predict and
  no warning to give. It also makes `MIN_SPAWN_DISTANCE_FROM_SETTLEMENT` (4 hexes)
  worth about seven minutes. **A balance decision, not a defect** — the same constant
  sets unit speed, so slowing hordes without slowing units means splitting it in two,
  and that changes how the whole game feels to play. Belongs with the opening-difficulty
  item above.
- [x] `[gated]` **Streamed chunk builds land whole inside one frame.** Done 2026-09-16.
  Load, scatter, soil and mesh-array construction run on `WorkerThreadPool` through
  `ChunkBuildQueue`; only node, `ArrayMesh` and `MultiMesh` creation stays on the main
  thread, one chunk finalized per frame. `bench_chunk_build.gd`, 12 real chunks, both
  views: main-thread cost per chunk **124.4 ms -> 1.64 ms mean, 490 ms -> 5.09 ms
  worst** (headless, so the finalize upload is understated). Gated by
  `verify_chunk_stream.gd`: queue contract, worker-vs-main output identity, and live
  streaming around a camera that moves mid-build.
- [x] `[gated]` **`TerrainDetailView._build_chunk()` allocates a throwaway Array per
  prop.** Done 2026-09-16 with the item above: grouping into `PackedInt32Array` with a
  `has()` check, and the same eager-default fix in `_build_hex_index()`.
- [ ] `[design]` **Walls block bleed proportionally — blocked: there is no passive
  bleed to block.** Retagged from `[gated]` 2026-09-07. The wall half is still exactly
  as specified (sub-hex coverage extending `SubHexPortalGraph.has_any_crossing()`,
  cached per hex-pair, invalidated on `WallManager`'s place/remove/breach/repair
  signals; hordes still siege — D16-D19). What is missing is the quantity it
  attenuates. **`InfestationManager` implements no hex-to-hex spread at all.**
  `run_daily_tick()` does two things: it breeds in place, and it calls `export_from()`,
  which spawns a roaming `Horde` **on the source hex itself**
  (`_horde_manager.spawn_horde_at(coord, available)`) and lets it walk. Walls
  deliberately do not stop hordes (D17), so there is nothing left for a wall to reduce
  by 40%.
  §2.1 is readable both ways and that is the decision needed. "Only Hive Core bleeds,
  and bleeding is just walking" says spread IS the horde, in which case D16 is already
  satisfied by D17 saying walls never stop one, and this item should close as
  superseded. "Wall coverage along a shared hex boundary reduces passive bleed across
  it in proportion" says there is a separate per-day count transfer from a Hive Core
  hex into its neighbours — a mechanic nobody has built, which would change how fast
  infestation creeps across the whole map and is therefore a balance decision, not a
  wiring one. **The user has to pick which; do not infer it from the wording.**
- [ ] `[visual-autonomous]` **Hex-border snapping as a wall placement aid.** Freehand model
  unchanged; snap when a drawn line runs near a border, modifier key to refuse.
  Sealing a border is ~50 pieces over ~4,992 m and is pixel-hunting without it. (D20)
- [x] `[gated]` **Gate pass-through.** Closed 2026-09-16 — it had shipped 2026-08-19
  (`665b8fd3`, `WallManager.get_blocking_segment()`'s `ignore_gates`, threaded through
  `HexPathfinder.find_path()` and `UnitOrderController._blocked_by_wall()`) and this entry
  and its detail line were never updated. What was missing was proof at the layer that had
  already failed once: `verify_gates.gd` only asked the pathfinder. It now also walks a
  real unit out through `UnitOrderController` (must leave across a gated edge and arrive)
  and aims `HordeManager`'s own crossing line at a gate (must hit the gate, damage it, and
  pass only once it is breached). Mutation-tested: route treats gates as solid, crossing
  re-check treats gates as solid (the live-lock — the pathfinder check alone passes it),
  and gates never block — each fails the gate. (D18)

## Next — earns its place, but not the core loop

- [ ] `[design]` **Classify hex elevation off the fine bake.**
  `RealTerrainSampler.majority_biome()` takes the MAX elevation of a 5x5 grid. Its
  own comment records that this is only safe because the coarse raster holds 4x4
  identical blocks, so the max means "some substantial upland part of this hex is
  above the line" rather than a point maximum — and that it stops being true the
  moment the elevation source gets finer. It now is finer. At 30 m one summit would
  classify a whole 25-square-mile hex as Level 4 MOUNTAIN, feeding
  `MountainPassCarver` and every passability decision downstream. Move to an explicit
  percentile and point `_sample_fine()` at the elevation tiles. **This regenerates the
  map** — needs a before/after mountain-hex count and the user's call on the change,
  which is why the bake deliberately did not do it. (`SubHexTerrainQuery.elevation_metres()`
  is the fine read path in the meantime.)
- [ ] `[design]` **Veterancy counts hordes destroyed, not zombies killed.**
  `UnitMorale.get_rank()`'s own doc comment settles that "destroys a Horde" is
  the definition of a kill, which was fine when combat was movement-triggered and
  a horde was 10-25 strong. Since 2026-08-29 a frontage-1 defending wave is a
  horde that dies every round, so a unit grinding low-density ground is ELITE
  (`ELITE_KILLS` 10) after 200 simulated seconds. Bounded — ELITE is +25% damage
  and there is no rank above it — so this is a meaning problem rather than a
  balance runaway. Needs a decision on what a kill is before any code. (D51)
- [ ] `[gated]` **Repair can be ordered again while it is already running, and
  charges again each time.** Found 2026-08-30 while reviewing the emissions change.
  `is_ruined` stays true for the whole 1-4 day repair job, `get_repair_error()` never
  asks whether one is already queued, and `UnitPanelView._add_repair_button()` shows
  the button for any ruin — so pressing Repair twice spends the material cost twice
  AND calls `CapacityAllocator.apply()` twice, minting a second Energy/Population draw
  for one building. Same family as the mid-repair leak below, opposite direction, and
  probably the same fix: a public "is this instance already being repaired" question
  on `BuildingManager`, which `get_repair_error()`, `demolish()` and the panel can all
  ask.
- [ ] `[gated]` **A repaired building keeps its rubble silhouette at Tactical zoom.**
  Found 2026-08-30. `LocalDetailManager` connects `building_placed`/`_removed`/
  `_ruined`/`_construction_completed`/`_powered_down`/`_powered_up` but not
  `building_repaired`, and only those handlers dehydrate a hex before rebuilding —
  `TacticalHexView` draws a ruin as a code-drawn rubble polygon, so a rebuilt building
  stays visibly wrecked until something else forces the hex to rehydrate. The same
  missing-trigger defect the 2026-08-30 emissions work fixed in fog, noise and ZoC;
  this one is a render, so it wants a before/after screenshot rather than a count.
- [ ] `[gated]` **Demolishing a building mid-repair leaks its Energy/Population
  allocation.** Found 2026-08-30 while deciding D53.
  `BuildingHealthController.repair()` applies capacity when the repair job is QUEUED,
  but `is_ruined` stays true until the job completes — and `demolish()` skips its
  capacity top-up for any ruin, on the assumption the allocation was already refunded.
  For a mid-repair instance it was not: it was re-applied one line earlier. The
  going-dark path deliberately settles capacity on the flag instead
  (`BuildingPowerController.restart()`) so it does not inherit this; the repair path
  still has it.
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
- [ ] `[visual-autonomous]` **Placed-segment renderer for Infrastructure.** No persistent visual
  exists once a segment is placed. Now part of the §2.2 rework. Detail below.
- [ ] `[gated]` **Epic phase 2 — mechanics read the vector layer.** Detail below.
- [ ] `[visual-autonomous]` **Epic phase 4 — vertex-displaced elevation relief.** Unblocked by the
  fine elevation bake. Detail below.
- [ ] `[gated]` **`HordeManager` stuck-detection/bypass.** Shares `MovementStepper`
  clearance math with `UnitOrderController` but has no bypass at all. Detail below.
- [ ] `[gated]` **`portal_offset_for_step()` is still the expensive path.** Detail below.
- [ ] `[gated]` **Extract the screenshot camera-framing discipline.** Five scripts now
  carry the same "disable edge pan, disable _process/_input/_unhandled_input,
  make_current(), set_zoom_level() rather than assigning `zoom`, wait real frames, then
  re-assert position and zoom and check for drift" block:
  `capture_project_review_shots.gd`, `smoke_screenshot.gd`, `preview_relief_ingame.gd`,
  `verify_save_screenshot.gd` and (2026-08-30) `preview_going_dark.gd`.
  `smoke_screenshot.gd`'s own doc comment said "if a fifth appears, extract it rather
  than copying it again" — a fifth has appeared. Every copy carries the same two
  hard-won details (a stray desktop mouse wheel rezooming mid-run; relief streaming 2
  tiles/frame so a shot taken too early photographs half-loaded terrain), and a fix to
  one of them today reaches one script in five.
- [ ] `[visual-autonomous]` **6 of 15 resource counters have no icon, name or tooltip.** Detail below.
- [ ] `[gated]` **Placement status line is never cleared**, so no-op clicks read as
  successes. Detail below.
- [ ] `[visual-autonomous]` **Tech Tree panel drew as an empty black rectangle** (unconfirmed).
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
  Three readers share the defect now — `ReliefTileView`, `RealTerrainSampler`
  (`Image.load_from_file()`) and `FineElevationTiles` — so fix them together.
  The raw-binary readers (`TerrainMeshChunkData`'s `*.tmesh`, `ZombiePopulationData`'s
  `*.zpop`) have the mirror-image problem and belong in the same export check: they are
  not resources, so they ship only if the export preset's non-resource include filter
  covers those extensions. Both state it in their own doc comments; neither is verified,
  because `export_presets.cfg` is gitignored and no export has been run.

## Deferred — fails `vision.md` §5 check 3

Not forgotten. Not worked on until the core loop works. Do not justify work by these.

- [ ] `[design]` **§6 line-of-sight and light propagation, full version.** The crude
  `lit_at_night` attraction increment is in Now; full LoS/illumination waits. Needs the
  fine elevation bake. Detail below. **Two things the 2026-09-01 noise work leaves
  here:** §6's tactical sound-radius table (melee 20 m through artillery 400 m) has no
  consumer and belongs to whatever reads sound at the tactical layer, not to
  `NoisePropagation`; and light is still a flat night-only +1.0 added in the attraction
  domain, because there is nothing to derive a distance curve from until this lands.
- [ ] `[design]` **Blood/smell attraction.** Raised by the user, explicitly undesigned.
- [ ] `[design]` **Late-game settlement-count management + automation/governors.** The
  acknowledged consequence of "killing is the only suppression" (D8).
- [ ] `[design]` **Physical goods transport** with travelling carts and trains. §2.2's
  throughput numbers are the upgrade path.
- [ ] `[visual-autonomous]` Coastline/minimap still trace `_LAND_RLE`'s hex-quantized boundary.
- [ ] `[visual-autonomous]` Epic 3b — blending across biome boundaries.
- [ ] `[visual-autonomous]` Epic 5 — escarpment cliff faces + coastline detail.
- [ ] `[gated]` Epic 6 — `SubHexTerrainOverride` runtime patch path.
- [ ] `[gated]` Epic 7 — LOD / caching / perf pass.
- [ ] `[gated]` Real 1890s main roads baked from geographic data.
- [ ] `[visual-autonomous]` Ambient ruins from real settlement data.
- [ ] `[visual-autonomous]` Countryside features outstanding from the 2026-08-19 request.
- [ ] `[design]` Resource-tick pacing/balancing.
- [ ] `[design]` Famine-severity input to Morale.
- [ ] `[design]` Game time runs unattended while the playtester thinks (harness artifact).
  *2026-09-16:* the deterministic half of this is answered by
  `tools/playtest/run_scenarios.py`, which hand-drives time at a fixed step; the
  AgentHarness (real UI) still has no `step_days`.
- [ ] `[gated]` **Playtest scenarios: longer and richer runs.** **WHY:** the scenario set
  shipped 2026-09-16 scripts only Tier 0 play and short horizons, so it cannot yet see
  the 2-3 hour session (`PLAYER_EXPERIENCE.md` §3). **PLAYER EXPERIENCE:** none directly;
  it is how every rank 1-8 item proves itself. **IMPLEMENTATION:** a scripted economy
  that grows through Tier 1-2, a wall-building helper (`WallManager.place_wall_line()`),
  a second-settlement scenario once §2.2 lands, and a headless-safe "long opening"
  (60 days) for the escalation item. **VERIFICATION:** each new scenario runs to JSON
  on `origin/master`.
- [ ] **Phase 3 — Sewers/Underground** (3.1, 3.2, 3.3). Cut order #1.
- [ ] **Phase 7 — Narrative Campaign** (7.1-7.7). Ships in v1.0, started only once the
  core game works. 7.5 Naval/Ireland is cut order #2.

## Closed by design, not by code

- **"Nothing escalates over time; the colony was unthreatened for 149 consecutive
  days"** (playtest, 2026-08-17). This was the structural gap that drove the entire
  §2.1 design. It is answered by the infestation model, not by a separate escalation
  feature. Detail retained below for the original observation.
  *2026-09-16:* its fixed-length-campaign question is closed by D92 (the campaign is
  persistent and open-ended). Escalation over time is re-opened as its own `[design]`
  item in the Now priority index, and the TAB warning conventions it researched (ETA,
  bearing) feed the horde-warning item.

---

## Detail (inherited from todo.md)

Verbatim, for the items above that reference it.

- [ ] **Placed-segment renderer for Infrastructure (Road/Railway/Canal/Bridge) — no persistent visual exists once a segment is placed.** `LogisticsNetwork.place_segment()` stores the segment and emits none of `network_recomputed`/`placement_rejected`/`segment_upgraded`/`upgrade_rejected` as a "just placed, draw me" signal a renderer could hydrate off — unlike `WallManager.wall_segment_placed`, which `StrategicOverlayManager`/`LocalDetailManager` already both listen to. Needs: a `segment_placed` signal on `LogisticsNetwork`, a `SupplyLineMarkerRenderer` (mirrors `WallMarkerRenderer`, using `SupplyLineVisuals.line_texture()` + `WallVisuals.apply_line_geometry()`'s UV_SCALE tiling trick verbatim — same `Line2D`-along-a-hex-edge shape a supply-line segment already is), and `LocalDetailManager` hydration on the new signal so a Tactical-zoom view repaints when a segment is placed nearby, same as `_on_wall_segment_placed()` already does for walls.


- [ ] **`SeaView`/`CoastlineOutlineView`/minimap still trace `_LAND_RLE`'s hex-quantized boundary, not the real coastline 1b baked.** Split out of 1b (2026-08-20). `SeaView`'s big under-everything fill stays correct regardless (it only needs to be big enough, not shaped right), but `CoastlineOutlineView`'s drawn line and the minimap's coastline both now visibly disagree with `TerrainMeshView`'s real mesh edge — the outline is coarser than the terrain it is supposed to be outlining. Needs the outline geometry to come from `coastline.land_polygon_world()` (or a cached derivative of it) instead of `HexCoord.coastline_segments()`.


- [ ] **`geo_projection.CALIBRATION_POINTS` has at least one bad row.** *(Superseded
  2026-08-28: it does not — the row is faithfully transcribed on both sides and the
  residual is hand-placement noise across 18 of the 21 anchors. `decisions.md` D36 has
  the measurements. Original observation kept below.)* Found while validating 1b (2026-08-20): "Midlands Farmland (Warwick)" fits at 6.50 hex radii of residual, far outside every other row (0.44–2.34 for the 3 web-verified city anchors, mostly 1-3 for the rest per the file's own doc comment). Likely a transcription error in that row's lon/lat or q/r, not a property of the affine itself. Not fixed alongside 1b because re-fitting the affine means re-verifying every bake product that already depends on it (fine relief, fine tiles, raster landcover, vector landcover, and now the coastline) — a focused re-check of that one row's source, then one shared re-verification pass, not a coastline change.


- [ ] **2: mechanics read the vector layer.** `SubHexTerrainQuery`'s cache-miss body (`SubHexTerrainQuery.gd:53`) swaps from `RealTerrainSampler.sample_at_hex()` to point-in-polygon against the vector set. **The seam is exactly one call site** — the class already memoizes per 30m sub-cell address and caches misses (`{}`) too, so point-in-polygon runs once per cached cell and every hot-path caller (`HexPathfinder`, `HordeFlowField`, `SubHexPortalGraph`, `BuildingManager` placement) still hits a dictionary lookup. **Not "once per cell ever touched" any more (2026-09-01):** the cache now evicts at `MAX_ADDRESSES_PER_GENERATION`, so a working set larger than one generation re-runs the polygon test each time it cycles. That makes the per-hex polygon bucket index below a requirement rather than a mitigation. Same signature, same return shape, so all four existing readers are untouched. The real risk is not steady state but **cold-cache spikes** — a fresh `HordeFlowField` build or a long path over never-visited ground triggers many first-touch misses at once; mitigation is a per-hex polygon bucket index so a test only considers polygons overlapping that hex rather than all of GB+Ireland. Gate the merge on a measured before/after, not on the argument above. Two invariants must survive: overrides are applied to a DUPLICATE never in place, and the urban disc must keep not overwriting OCEAN/WATERWAY (load-bearing) or `terrain_feature` (`ReclamationManager` owns draining as a costed action).


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


- [x] **Gate pass-through behavior:** *(Stale when written into this file — shipped 2026-08-19; see the Now entry.)* gates currently block identically to a plain wall until breached — no special ally-pass-through mechanic yet.


- [ ] **Countryside features still outstanding from the same request (2026-08-19).** The user asked for four things beyond thick forests and picked them explicitly: **drystone walls & hedgerows** along real field boundaries (the boundary-edge data `TerrainBoundaryBlend.find_crossings()` already computes is the natural input), **ruins & abandoned cottages** that can be selected and demolished when inside a ZoC (overlaps the existing "ambient ruins from real settlement data" item above), **crags/scree/boulder fields** concentrated on steep ground (the 30 m relief tiles bake shade, and `|shade - 128|` is a direct slope proxy — no new bake needed), and **real resource deposits that gate mine placement** (user chose "real deposits that gate mines" over decorative-only, so this touches `BuildingCatalog` placement rules, save data and map balance — it is a gameplay change, not a visual one). None are started.


- [ ] **Famine-severity input to Morale:** a fifth input (units undersupplied but not dying) would need `UnitMorale` to take a live `BuildingManager` reference it's currently deliberately free of — reasonable extension, not wired.


- [ ] **`SubHexPortalGraph.portal_offset_for_step()` is still the expensive path.** `has_any_crossing()` (added for the boundary rule) early-outs at the first passable sample and measured 0.02 ms/edge, but `portal_offset_for_step()` — called per hex-to-hex leg by `UnitOrderController` and `HordeManager` — still goes through `find_portals()`, which sweeps the whole edge at 30 m (~167 positions, measured 2.18 ms cold per edge and ~178 stranded `SubHexTerrainQuery` cache entries). Cached per hex pair so it is paid once per edge per session, but it is the remaining unbounded-cache contributor. Pre-existing, not introduced by the boundary rule.


- [x] **`SubHexTerrainQuery._cache` is unbounded and never evicted.** *(Closed 2026-09-01 — the original observation is kept below because its proposed fix was measured and rejected.)* One entry per queried 30 m sub-cell under a String key, static for the process lifetime. Fine at today's query volume; `cache_size()` exists to measure it. A FIFO/LRU cap like `HordeFlowField.MAX_CACHED_FIELDS` is the obvious fix if a long session ever shows it growing. **What shipped instead:** a two-generation rollover, because a FIFO order list at six-figure cardinality is itself a six-figure Array (D64); and interned sample Dictionaries, because the String key turned out to be a minority of the 851 bytes an entry cost (D63).


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

