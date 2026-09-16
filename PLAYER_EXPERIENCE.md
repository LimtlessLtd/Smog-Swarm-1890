# Player Experience — The Smog & The Swarm

> Authored 2026-09-16 from the user's design-audit brief, reconciled against every
> settled decision in `decisions.md` (D1-D90) and an audit of the implementation.
> Where the user's words settle something they are quoted verbatim (`CLAUDE.md` §2).
> Where nothing settles it, the question is marked **[design]** and left open —
> a recommendation may be attached, but it is not a decision until the user makes it.
>
> **This document's job.** `design_doc.md` answers *what are the mechanics and
> numbers?* This answers *why should a player enjoy using them?* A mechanic that
> matches `design_doc.md` exactly and fails an acceptance criterion here is not done.
> `GAME_HEALTH.md` records how far the build currently is from this document.

**Hierarchy:** `vision.md` → **`PLAYER_EXPERIENCE.md`** → `GAME_HEALTH.md` →
`design_doc.md` → `decisions.md` → `backlog.md` → implementation → test / playtest /
visual validation.

---

## 1. Core fantasy

The user's statement of the game, verbatim:

> "They Are Billions, but on a gigantic continuous map of 1890s industrial Britain,
> with a persistent long-form campaign where the player steadily develops from a tiny
> settlement into an industrial military power and progressively reclaims Britain from
> an enormous zombie population."

The fantasy is **"I am building an industrial civilisation in a zombie-infested
Britain."** It is not "I build a colony and survive a wave."

The emotional backbone is a transformation the player should *feel*, each stage
visibly different on screen and mechanically different in what the player can do:

```
SMALL SURVIVOR SETTLEMENT → DEVELOPING SETTLEMENT → INDUSTRIAL TOWN → FORTIFIED CITY
→ NETWORK OF CONNECTED SETTLEMENTS → REGIONAL INDUSTRIAL POWER
→ MASSIVE MILITARY/INDUSTRIAL EMPIRE → BRITAIN BEING RECLAIMED
```

The target inner monologue, which every section below is in service of:

> "I need to expand." · "That's going to attract zombies." · "I can handle it." ·
> "Oh shit, that horde is much bigger than I expected." · "Shut the factory down." ·
> "Get the guns over there." · "Hold the wall." · "We survived." · "Now I need that
> coal." · "If I clear that city, I can build the next part of my industrial network." ·
> "Britain is actually becoming mine."

### 1.1 What "persistent" means (settled)

> "The player should NOT repeatedly throw away an entire developed base just because
> they lost a local fight."

> "A settlement can be damaged. A wall can fall. A district can be lost. A resource
> region can be overrun. An expedition can be destroyed. A supply route can be cut. A
> city can potentially be abandoned or reclaimed. These should be setbacks inside a
> larger strategic campaign. However, complete strategic defeat can still end the
> campaign."

> "Do not turn the game into an idle game or remove meaningful failure."

This agrees with what was already settled: `vision.md` P4 (losing is real),
`backlog.md` 7.6 / D73 (defeat is economic/capability elimination, not territorial),
D9 (buildings die to attacks, never to a ratio), D29 (an isolated settlement stagnates,
it does not die), and `vision.md` §1 (`BackgroundExecutionManager` is not an idle
mode). It **settles one open question**: the campaign is open-ended and persistent,
not a fixed-length *They Are Billions* map with a final wave (D92). Threat escalates
through expansion and the settlement's own light and noise, not a calendar (D101).

### 1.2 Sessions inside a campaign

`vision.md` §1's "sit-down RTS played in 1-3 hour sessions" and the persistent campaign
are the same thing at two scales: **a session is a chapter of one campaign save.** Each
session should end with the player's position visibly changed and a reason to open the
save again. Engagement density per session is still the design target, not catch-up
after hours away.

---

## 2. The layered loops

Every major system must serve at least one loop. `GAME_HEALTH.md` §3 maps each
implemented system onto these and flags the ones that serve none.

| Loop | Cadence | Steps | The decision it creates |
| :--- | :--- | :--- | :--- |
| **Micro** | seconds | SELECT → MOVE → ATTACK → RETREAT → REPOSITION → REPAIR → REINFORCE | Which units, where, and when to pull back before a line breaks. |
| **Local** | minutes | EXPLORE → CLEAR → SECURE → BUILD → HARVEST → DEFEND | Which ground to take next, and what to spend holding it. |
| **Regional** | tens of minutes | CLEAR AREA → CLAIM RESOURCES → ESTABLISH INFRASTRUCTURE → CREATE OUTPOST → CONNECT IT → DEFEND IT → EXPAND AGAIN | Where the next settlement goes and how it is tied back. |
| **Industrial** | tens of minutes | EXTRACT → PROCESS → POWER → MANUFACTURE → ARM → EXPAND PRODUCTION | What to build toward, and how much noise and exposure to accept for it. |
| **Strategic** | a session | EXPAND → CREATE MORE THREAT → ATTRACT ZOMBIES → DEFEND → INDUSTRIALISE → FIELD LARGER ARMIES → CLEAR MORE DANGEROUS REGIONS → EXPAND AGAIN | Expand or consolidate. |
| **Campaign** | many sessions | SURVIVE → GROW → INDUSTRIALISE → RECLAIM → CONSOLIDATE → PUSH FORWARD → EVENTUALLY RECLAIM BRITAIN | Which region of Britain to push into next. |

### 2.1 What already closes each loop, and what does not

Stated from the code as of 2026-09-16 (detail and citations in `GAME_HEALTH.md`).

- **Micro.** SELECT/MOVE work (continuous `MovementStepper`, attack-move, hold,
  garrison, patrol). ATTACK is a same-hex mutual-damage exchange every 20 s with no
  range, projectile or on-screen feedback (`CombatEngine`), so RETREAT and REPOSITION
  have nothing tactical to respond to. REPAIR exists for buildings and walls.
  REINFORCE works through the resident-wave interleave (D50). **Open: the loop has no
  second-to-second content.**
- **Local.** CLEAR is killing (D8), SECURE is build rights by band (D40), BUILD/HARVEST
  exist. **Open: EXPLORE yields nothing but fog; HARVEST is the same flat output on any
  legal hex, so there is little reason to want a particular hex.**
- **Regional.** Town Hall founding exists (Tier 3). **Open: a second settlement shares
  the one global stockpile (§2.2 unbuilt), supply lines only change movement speed, and
  a founded hex likely gets no civilian ZoC** (districts are generated only at worldgen —
  unverified, filed in `backlog.md`). CONNECT IT and DEFEND IT therefore have no stake.
- **Industrial.** The resource chain exists end to end. **Open: nothing in it is
  exciting yet — tiers unlock buildings and bigger numbers (`3 + 2*tier` damage), and
  industry's only risk is noise, which does not reach hordes in the opening.**
- **Strategic.** EXPAND → CREATE MORE THREAT is real (D39: Hive Cores within 8 hexes of
  a player building export hordes). ATTRACT ZOMBIES is real for industrial buildings
  only. **Open: nothing the player does in the first hours is loud, so this loop does
  not engage until Tier 1 industry exists.**
- **Campaign.** Defeat exists (D73). **Open: no victory, objective, or milestone
  exists; the campaign arc (Phase 7) is deliberately later (§12).**

---

## 3. Session structure

**Measured pacing fact that governs this whole section.** One in-game day is
`TickManager.DAY_LENGTH_SECONDS` 2400 game-seconds; the default speed is index 1 = 5x,
so **one day = 8 real minutes at default speed**. Construction is 1-4 days
(`BuildingConstructionController`), unit training `tier + 1` days capped at 4
(`UnitManager`), production and research tick once per day, and a horde moves one hex
per 20 game-seconds (`MovementStepper.BASE_MOVE_SPEED`) — 4 real seconds per hex at
default speed. So in the first hour the player gets ~7.5 production ticks, the first
building takes at least 8 minutes to stand, the first brick-tier research
(`building_tier_1`, 50 RP against the Town Hall's 5 RP/day) takes ~80 minutes, and a
horde crosses five hexes in 20 seconds. **The economy runs on a clock ~100x slower
than movement.** *Decided 2026-09-16 (D98):* construction, training and research move
to a session timescale and hordes are slowed separately from units; the day stays.

The intended experience at each scale. None of these are timings to hit exactly; they
are what the player should be able to *say happened*.

| Horizon | The player should have… | Status |
| :--- | :--- | :--- |
| **First 10 minutes** | read the map and understood why the start hex is the only safe ground; placed first buildings and seen them work; commanded a first unit; seen a zombie. | Blocked by pacing — first building/unit complete at ~8 min. |
| **30 minutes** | cleared a first neighbouring hex and claimed something on it; seen the map push back (a horde, a wave from residents); made one expand-or-consolidate call. | Clearing works; claiming yields nothing distinctive; pushback is undirected drift (D74 run: contact day 4 = 32 min). |
| **60 minutes** | reached the first industrial tier and felt the change in what they can build and field; faced a first horde they had to *respond* to (noise off, units moved, wall held). | First tier ~80 min at default speed on the Town Hall alone; the opening colony is silent so going dark buys nothing. |
| **2-3 hours** | founded or planned a second settlement for a specific resource; had a defensive emergency and recovered from it; the colony looks and sounds industrial. | Second settlement is Tier 3 and mechanically hollow; no audio at all. |
| **Campaign** | a network of settlements; a first city taken; a region of Britain lit; the next region chosen deliberately. | Phase 7; not a current build target (§12). |

---

## 4. Early, mid and late game

**Early game — survival settlement.** One lit town in a dark country. Wood, clay,
food, a wall, a handful of constables and archers. The world is hostile one hex out
(D7's 0/25/50/75/100 rings). *Experience:* scarcity and a small safe circle; every
push outward is a risk the player chooses. *Decision:* what to build first, when to
send the first squad out. *Settled:* start hex 0%, ring 1 25% (D7); only killing clears
(D8); the first clear is won by building an economy and an army first, and nearby
resources may deplete to push the player outward (D99). *Measured 2026-09-16:* the
start's ring 1 is Manchester itself (68,075 zombies in
the least-populated routable neighbour), which 12 Tier 0 units cannot clear; and
`WallManager.seed_starting_defenses()` exists but has no production caller, so the start
is unwalled.

**Mid game — industrial town to fortified city.** Bricks, coal, iron, gunpowder.
Firearms replace truncheons. Industry makes noise, noise draws hordes (D10, D66-D69),
and the player learns the central trade: capability costs attention.
*Experience:* growth that is audible, visible and dangerous. *Decision:* where to site
industry (behind woodland attenuates noise for free, D69), when to go dark (D11,
D52-D58), how much wall to afford. *Open:* nothing yet makes a tier feel like a turning
point (§7); [design].

**Late game — network and region.** Several settlements, connected by road, canal and
rail, feeding a war industry that can take a city. *Experience:* the map is visibly
yours in a widening region; logistics is strategy, not bookkeeping. *Settled:* one Town
Hall = one stockpile (D21), throughput-limited pooling (D22-D23), terminals (D25),
severance by infestation (D28), stagnation not death (D29), zombies ignore
infrastructure speed (D6). *Deferred:* automation/governors (`vision.md` §3), until
multi-settlement play works — the user, verbatim: governor systems "should only become
a priority once multiple-settlement gameplay actually works."

---

## 5. Pillars of play

Each section: the experience wanted, what is already settled, what follows from
existing systems without new rules, and what is open.

### 5.1 Expansion
- **Want:** "I need to expand" — the player can name *why* they want a specific hex, and
  knows it will cost them.
- **Settled:** expansion is combat (P1); build rights by band (D40); exports target the
  player's neighbourhood (D39), so expanding toward population raises pressure.
- **Follows already:** territory is literally killing a hex's count down (D8, D48-D51);
  a city hex is a harder clear than moorland because its frontage is larger (D49).
- **Open [design]:** *why want this hex over that one.* Biome gates what can be built
  (coal on moorland/highland, industry on urban/industrial) but yield is flat
  everywhere except farm soil. The user has already chosen "real deposits that gate
  mines" over decorative-only (`backlog.md`, countryside item, 2026-08-19) — that is the
  settled direction; its data source and numbers are not designed.

### 5.2 Clearing territory
- **Want:** a clear is an operation with a beginning, a grind and a reward, and ground
  that stays cleared only while it is held.
- **Settled:** 5% threshold (D2); re-infestation real (D9); garrisons hold ground (D8).
- **Follows already:** residents condense into a frontage (D49) so a city fights back
  harder at the same unit count; a surviving wave wanders off as a horde (D51) — poking
  a hive has consequences.
- **Open:** clearing an empty hex and clearing a city differ only in duration and
  losses (§8).

### 5.3 Industrialisation
- **Want:** each era changes what the player can *do*, not only how big the numbers are.
  Wooden survival settlement → brick-and-coal industrial town → steel and rail
  infrastructure → large-scale Victorian military industry.
- **Settled:** the resource hierarchy and tier tree (`design_doc.md` §2-§4); the
  user's constraint, verbatim: "Do not create unnecessary additional resources."
- **Follows already:** Tier 1 firearms introduce gunpowder dependency (`requires_gunpowder`);
  Tier 3 unlocks new Town Halls; Tier 4-5 vehicles need coal.
- **Open [design]:** tiers currently differ by stat ramp and unlock lists (`IND-2`). A
  capability per era is the ask; the candidates already in the spec, which only need
  wiring rather than invention, are: **firearms have range** (ranged units currently
  resolve like melee), **gunpowder consumed per shot** (`design_doc.md` §4 says so;
  the code only checks the stockpile is above zero), **rail moves armies** (D6 already
  makes this the asymmetric advantage), **artillery reaches past walls**, and the
  **second settlement** at Tier 3. See §7 and `backlog.md`.

### 5.4 Logistics
- **Want:** the player sees a bottleneck and fixes it with infrastructure; never audits
  fifteen counters.
- **Settled:** all of D21-D29; `design_doc.md` §2.2.
- **Status:** unbuilt. Supply lines change movement speed and suppress military ZoC only.

### 5.5 Horde interaction
- **Want:** "Oh shit, that horde is much bigger than I expected" → a real choice about
  what to do about it. A huge horde creates decisions, not a bigger health bar.
- **Settled:** hordes big enough to end the run (P2); counterplay is going quiet (D11)
  and drawing hordes away with units (P2's quote); zombies ignore infrastructure (D6);
  walls buy time (D17).
- **The intended causal chain** (the user's):
  `INDUSTRIAL ACTIVITY → MORE CAPABILITY → MORE NOISE/LIGHT → MORE ZOMBIE ATTENTION →
  MORE THREAT → PLAYER COUNTERPLAY → GREATER STRATEGIC DECISIONS`.
- **Where the chain breaks today** (measured; `backlog.md` Now):
  1. The opening colony is silent — 0 of 73 hordes ever ATTRACTED in 30 days (no
     building the player starts with emits). Going dark therefore buys nothing when the
     player is weakest.
  2. Units and gunfire make no noise, so the "draw it away with military units" play
     P2 names has no mechanism, and fighting has no attention cost.
  3. Hordes move ~735 km/day; "early warning" (§2.1's own justification for D6) has no
     travel time to warn across.
  4. The HUD warning shows only a fog-VISIBLE, ATTRACTED horde, with no bearing.
  None of these need a new mechanic; they need the existing ones tuned and connected.
  *Decided 2026-09-16:* combat makes noise (D100); hordes slow relative to units (D98);
  settlement light and noise reach further as it grows, which is how threat escalates
  (D101).

### 5.6 Defence
- **Want:** preparation choices; defences that buy time; breaches that are emergencies;
  reinforcement that matters; a hold that feels earned.
- **Settled:** walls never grant immunity (D17); gates pass friendlies (D18); walls stay
  freehand with snapping as an aid (D20).
- **Follows already:** walls take siege damage and breach with a critical alert;
  garrisoned units take 0.75x damage, less at night near a Search Light.
- **Open:** no building or wall position deals damage; units cannot man a wall; a
  breached horde returns to WANDERING. There is nothing to *do* during a siege except
  have units standing in the horde's hex.

### 5.7 Siege — a pillar, not an event
The user's arc: `WARNING → PREPARATION → POSITIONING → RESOURCE ALLOCATION → INITIAL
CONTACT → PRESSURE → BREACH → EMERGENCY RESPONSE → POSSIBLE RETREAT → RECOVERY`.

| Phase | What exists | Gap |
| :--- | :--- | :--- |
| Warning | ETA label (visible + ATTRACTED only), 100+ spotted alert, strategic marker | Bearing, size class, travel time long enough to act (§5.5) |
| Preparation | Walls, gates, upgrades, repair, going dark | Nothing to pre-position *on* (no firing positions) |
| Positioning | Move/garrison/patrol orders | Position matters only as "same hex or not" |
| Resource allocation | Wall repair costs, going dark | Gunpowder not consumed, so ammunition is not a siege resource |
| Initial contact / pressure | Wall damage per frame, horde damage doubles at night | No visible pressure (no damage feedback, no sound) |
| Breach | Critical alert, auto-pause, red segment | Horde reverts to WANDERING rather than pouring toward the district |
| Emergency response | Attack-move into the breach hex | Response is one same-hex exchange per 20 s |
| Retreat | Move orders | No morale rout, no reason a line breaks |
| Recovery | Repair (buildings, walls), rebuild | Casualty conversion makes a fallen district a new infestation — that part is right |

"The player should eventually be able to look at a city under attack and have several
meaningful things to do." Today they have two: switch things off, and move units into
the horde's hex.

### 5.8 Offensive operations
- **Want:** attacking a zombie-held city is a planned operation: scout it, stage a
  force, cut the hordes it exports, grind it down, hold it, and get something
  irreplaceable for it.
- **Follows already:** frontage scales with density (D49), so London fields 20 a round
  and needs heavy units (measured: 50 Holt Breakers, 12 days); a surviving wave becomes
  a roaming horde (D51).
- **Open:** the payoff (§8), and anything to do during the grind besides wait.

### 5.9 Exploration
- **Want:** discovering a new resource is exciting; the fog hides something worth
  finding.
- **Open [design]:** nothing is discovered today except terrain and zombies. Settled
  direction exists for deposits (§5.1). Ambient ruins from real settlement data are
  scoped but have no mechanic (`backlog.md` Deferred: "loot? salvage? horde spawn
  bias?" — undecided).

### 5.10 Settlement development
- **Want:** a settlement visibly grows — houses to terraces to industry — and a
  second settlement is a milestone that *costs* something.
- **Settled:** each Town Hall owns a stockpile (D21) — "founding a second settlement is
  the moment the player acquires a logistics problem."
- **Follows already:** `SettlementFoundingController` grows an urban disc with
  population and converts the hex to URBAN.
- **Open:** until §2.2 lands, a second settlement has no cost or benefit beyond build
  permissions.

### 5.11 Economic decisions
- **Want:** scarcity that forces a choice (what to ship today, D23), not waiting.
- **Status:** one global pool with no storage caps; the decisions are build order and
  going dark. See §9 "Waiting for resources / research".

### 5.12 Military decisions
- **Want:** different unit types produce different tactical behaviour; army composition
  is a decision.
- **Status:** roles resolve identically; abilities are knockback plus multipliers.
  *Decided 2026-09-16 (D102):* gunpowder is spent per shot and ranged units get a
  realistic metric range, never across hexes — the combat model is still the largest
  single gap between this document and the build.

### 5.13 Strategic setbacks and recovery
- **Want:** "I almost lost everything, but we survived and rebuilt."
- **Settled/follows:** buildings ruin rather than vanish and can be repaired; ruined
  housing converts to zombies on the hex (casualty conversion); isolated settlements
  stagnate (D29); defeat needs total capability loss (D73) with a risk warning signal
  first.
- **Open:** the player receives the defeat-risk warning as a toast only; there is no
  "abandon this settlement / fall back" action; recovery has no dedicated feedback.

### 5.14 Campaign progression, long-term motivation, endgame
- **Want:** a reason to keep playing after becoming economically comfortable — the map
  itself (bigger, denser, more valuable cities further in), and the climax of taking a
  great city.
- **Settled:** capacity from 1891 census is the difficulty curve (D3), so the
  Manchester → London arc ramps because history says so; Hive Cores beyond 8 hexes do
  not export (D39), so pushing forward is what brings the next threat; the whole island
  is the eventual win (P6); the narrative campaign ships in v1.0 but after the core game
  (P3, `vision.md` §4).
- **Open [design]:** what a successful campaign's climax *is* mechanically — taking
  London is the settled narrative target (7.1 Act III), but no victory condition or
  milestone system exists and none should be built before the golden slice (§11).

---

## 6. The map must matter

Britain is not a procedural canvas; place should change strategy.

| Geography | Creates a decision today? | Mechanism / gap |
| :--- | :--- | :--- |
| Population → zombie density | **Yes** | D3 capacity; D49 frontage; D39 export proximity. The strongest geographic system in the game. |
| Terrain movement | Yes, weakly | Biome speed multipliers; urban/industrial have no rule (`design_doc.md` §1 OPEN DECISION). |
| Rivers and crossings | **Yes** | Waterways impassable except bridges, for units and hordes (D6 note) — natural chokepoints exist. |
| Mountains / passes | **Yes** | Mountain hexes impassable; carved passes (`MountainPassCarver`) are real chokepoints. |
| Woodland / high ground vs noise | Yes | D69 attenuation: siting industry behind woodland is free noise reduction. |
| Industrial resources | Partly | Biome gates extractor placement; no deposits, no yield differences. |
| Agricultural land | Yes | Soil fertility scales farm output (LUSH x2 … NOT_ARABLE x0). |
| Coastline | No | Ocean is a boundary only; naval is cut order #2. |
| Transport corridors | No | No pre-existing roads/rail; 1890s main roads scoped, gameplay role [design]. |
| Defensible positions | No | Elevation gives no combat or vision effect yet (§5 of `design_doc.md` unbuilt). |
| Cities | Partly | §8. |

## 7. Industrialisation must feel like progression

Tier ladder as specified, and what each era should change for the player. The right-hand
column lists capabilities **already in `design_doc.md` or `decisions.md`** — nothing is
invented; the question is only which to wire first.

| Era | Buildings (spec) | Capability the player should feel | In spec, not wired |
| :--- | :--- | :--- | :--- |
| T0 Wood | Town Hall, Lumber Yard, Clay Pit, Farm, Houses, Watchtower, wooden walls | Survive; clear the first ring with melee and bows | — |
| T1 Brick | Coal Mine, Brickworks, Garrison, Research Institute, brick walls | Firearms; industry becomes audible; defences harden | Gunpowder per shot; firing range |
| T2 Iron | Foundry, Concrete Plant, Armory, Search Light | Night fighting; a real army | Searchlight LoS/illumination (§6, Deferred) |
| T3 Steel/Rail | Town Hall (new), Steelworks, Railway, Canal, High Command | **Second settlement; rail moves armies faster than hordes (D6)** | §2.2 stockpiles, throughput, terminals |
| T4 Traction | Steam Excavator, Traction Works, Maintenance Depot | Steam vehicles in the field | Coal fuel reserve (field logistics); vehicle noise |
| T5 Armament | Bessemer, Ordnance Complex, bunkers | Artillery and heavy vehicles take cities | Artillery range past walls |

### 7.1 Historical coherence — flagged for review, not rewritten

The user's bar, verbatim: "1890s Victorian Britain / industrial revolution / steam /
coal / steel / rail / early firearms / artillery / industrial machinery. Alternate
history is allowed. But the game should not gradually become a generic First World
War / dieselpunk / modern military RTS unless explicitly justified by the existing
design decisions." The project's own setting text already agrees: "no borrowed future
technology, just the Industrial Revolution pushed as far as it will go" (`todo.md`).

Items that drifted past it. **Renamed 2026-09-16 (D104)** to shorter period equivalents,
stats unchanged — the list below is kept as the record of why:

- `design_doc.md`'s title era "1890s-1920s" and `GameEnums` Tier 5 comment "Peak
  Industrial Warfare (1910s-1920s)".
- **Holt Breaker** (Holt caterpillar tractors are 1904+, their armoured use WWI) and
  **Armored Bunker Fortification** — tank-and-trench vocabulary.
- **Howitzer Gun Tractor**, **Armoured Command Car** — motorised WWI staff/artillery.
- **Tower Blocks** — a 20th-century housing form; the 1890s equivalent is tenements or
  model dwellings.
- **Concrete Road**, **Central High-Voltage Grid Station**, **Automated Freight
  Marshalling Yard**, **Synthetic Chemical Refinery** — names read 1920s-1950s; the
  underlying functions (macadam, electrical generation, marshalling yards, chemical
  works) are all 1890s-plausible under a different name.
- Tier names are inconsistent inside `design_doc.md` itself: §2 says "Automation Era /
  Super-Complex Era", §2's hierarchy says "Traction Era / Armament Era".

Not flagged: Maxim guns (1884), steam turbines (Parsons 1884), Bessemer (1856),
searchlights, quadricycles (1890s), canals and locks — all squarely in period.

## 8. Cities must be important

What already follows from existing systems for a real city hex (Manchester,
Birmingham, London), without any new reward:

- **Enormous threat** — capacity from census (D3); London ~4.5e5 residents, frontage 20
  (D49); Hive Core exports within 8 hexes of the player (D39).
- **Major clearing operation** — measured at 50 Holt Breakers for 12 days (London).
- **Placement value** — URBAN ground is where housing, Garrison, Research Institute
  and the Tier 3-5 trainers (`requires_settlement`) can go; settlement hexes start
  with safe districts, and therefore civilian ZoC.
- **Major defensive liability** — dense housing that falls converts its population
  into zombies (casualty conversion, 7.6).

What does **not** follow: valuable infrastructure, industrial potential, transport
importance, resources, or a reward for reclamation distinct from build permission.
**[design]** — the user's instruction is "Do not implement arbitrary rewards. First
determine which of these already follow naturally from existing systems." The
candidates that extend existing mechanics rather than invent one: pre-existing rail and
road corridors converging on cities (the 1890s roads item already scoped), salvageable
ruins from real settlement data (already scoped, mechanic undecided), and a city's
Town Hall site anchoring a larger stockpile/urban extent (D21's settlement unit).

## 9. Boring failure modes

The autonomous loop actively looks for these. Each has a detection route; "scenario"
means `tools/playtest/run_scenarios.py`, "telemetry" means `GameplayTelemetry`.

| Failure mode | How to detect | Status 2026-09-16 |
| :--- | :--- | :--- |
| Waiting for resources | telemetry `daily.stockpile` flat while `days_without_player_action` rises | **Present by arithmetic** — daily ticks, 8 real min apart |
| Waiting for research | `industrialisation` IND-4; RP/day vs tier cost | **Present** — T1 ~80 real min on Town Hall RP |
| Nothing dangerous happening | `opening` OPEN-2; gaps between `firsts` | Contact day 4 (32 min) with no player action |
| Expanding without resistance | `expansion` EXP-3/EXP-4 | See `GAME_HEALTH.md` |
| Fighting identical small groups repeatedly | resident frontage 1 on low-density hexes (D49) | **Present** — a moorland clear is N identical 1-zombie rounds |
| Building without meaningful decisions | `building_types_used`; flat yields | **Present** — location changes only farm yield |
| Huge armies sitting idle | telemetry `mean_army_size` vs `days_with_engagements` | Not yet measured over a long run |
| Logistics requiring excessive micromanagement | — | Not reachable: §2.2 unbuilt |
| Zombies dangerous but no counterplay | `horde` vs `horde:dark` HORDE-4 | **Present in opening** — silent colony, nothing to switch off |
| Zombies numerous but strategically irrelevant | HORDE-3; ATTRACTED count | **Present** — 0/73 ATTRACTED in the opening (D74 run) |
| Industry a passive income multiplier | IND-1; noise reach | Partly — noise exists but opening hordes never hear it |
| Defences as permanent immunity | `siege` DEF-2 | Walls breach; see `GAME_HEALTH.md` |
| Late game as repetitive map painting | — | Not reachable yet |
| Large battles unreadable | windowed `--shots` at battle zoom | 60,000-crowd "carpet" (`backlog.md`); MEDIUM draws no residents (D87) |
| UI overwhelming / unlabelled | playtest-critic agent | 15 counters, 6 unidentifiable (2026-08-17 playtest) |

## 10. Acceptance criteria

Evaluated on the player's experience, not code correctness. IDs are referenced by
playtest scenarios (`scripts/test/playtest/scenarios/`) and by `GAME_HEALTH.md`. A
criterion with no scenario is checked by a windowed screenshot or the playtest-critic
agent.

**OPENING** — `OPEN-1` a first unit is commandable within a few real minutes. `OPEN-2`
the world pushes back (a fight or a horde) within the first ten real minutes of ordinary
play. `OPEN-3` every horde that reaches the colony was visible to the player first.
`OPEN-4` the colony is not destroyed in the first ten days without warning. `OPEN-5` the
obvious first builds place, or say clearly why not.

**COMBAT** — `COMBAT-1` units respond to commands within a second. `COMBAT-2` attacks
are visually understandable: who is attacking whom is visible. `COMBAT-3` targets are
readable at battle zoom. `COMBAT-4` hits feel impactful (flash, recoil, sound).
`COMBAT-5` deaths are readable. `COMBAT-6` the player can tell why they are winning or
losing. `COMBAT-7` different unit types produce meaningfully different tactical
behaviour.

**EXPANSION** — `EXP-1` clearing the first neighbouring hex is an operation of minutes,
not an hour. `EXP-2` clearing yields something the player wanted from that hex. `EXP-3`
expansion costs something (losses, exposure). `EXP-4` expansion provokes the map.
`EXP-5` the player can say why they want a particular hex. `EXP-6` expansion does not
become repetitive clicking.

**HORDE** — `HORDE-1` a large horde is detectable before it arrives. `HORDE-2` the
warning is long enough to act on. `HORDE-3` hordes react to what the player does.
`HORDE-4` counterplay changes the outcome. `HORDE-5` counterplay has a cost (production
lost, units exposed). `HORDE-6` a large horde is not merely a larger health bar.

**INDUSTRY** — `IND-1` each tier noticeably changes what the player can do. `IND-2` unit
tiers change tactics, not only stats. `IND-3` there are turning points, not a smooth
ramp. `IND-4` the tech path is paced for the session structure (§3). `IND-5` industry
creates new risks as well as power.

**DEFENCE** — `DEF-1` a horde next to the settlement produces a siege. `DEF-2` defences
buy time, not immunity. `DEF-3` defenders have things to do during a siege. `DEF-4` a
lost fight is a setback, not the end. `DEF-5` breaches create emergencies the player can
answer. `DEF-6` a successful defence feels earned.

**LOGISTICS** — `LOG-1` the player can see where a bottleneck is. `LOG-2` infrastructure
creates strategic value. `LOG-3` infrastructure changes how expansion works. `LOG-4`
logistics is never bookkeeping.

**SETTLEMENTS** — `SET-1` a second settlement grants territory, resources or reach the
first could not. `SET-2` it costs infrastructure, protection and exposure. `SET-3`
managing several is not repetitive micromanagement.

**FEEDBACK** — `FB-1` the main strategic threat (infestation) is visible on the map.
`FB-2` every alert says where. `FB-3` the player can tell what a resource counter is.

## 11. The golden slice

The benchmark for game feel. It answers: **"Would I voluntarily play this for another
hour?"** It is not a milestone that unlocks campaign work — the user, verbatim: "Do not
move to campaign content simply because the golden slice exists."

It contains, on the real map from the real start:

1. The starting settlement, readable in its first screen.
2. Resource gathering that produces visible change within minutes.
3. First military units (Tier 0) under direct command.
4. First expansion: a neighbouring hex chosen for a reason.
5. First clearing operation, with losses and a reward.
6. First meaningful zombie response to that expansion.
7. First industrial upgrade (Tier 1) that changes what the player can do and makes
   the colony audible.
8. First defensive problem: a wall under pressure.
9. At least one horde interaction with real counterplay (going dark, drawing it off, or
   holding the line).
10. A meaningful choice about whether to expand or consolidate.

**Acceptance:** OPEN-1..5, EXP-1..5, HORDE-1..4, IND-1 and IND-4, DEF-1..3 and FB-1 all
"ok" in the scenarios or on screen, and the playtest-critic agent's report not leading
with a finding that breaks the slice. **Estimated length:** the first 60-90 real minutes
at default speed. The pacing [design] question (§3) decides whether that is achievable
at all.

## 12. Player impact

Every significant task answers five questions before it is prioritised:

1. **What does the player get to do that they couldn't before?**
2. **What decision does this create?**
3. **What feedback does it provide?**
4. **What makes it more fun?**
5. **What strategic consequence does it create?**

A task that cannot answer them is not automatically prioritised, however well specified
(the priority model is in `CLAUDE.md` §0.2). Infrastructure, performance and tooling
work answer them through what they unblock, and say so.

## 13. Audio roadmap

Audio is part of the experience. Current state: **silent** — `AlertManager._MUTE_ALL_SOUND`
is true, and the only sounds are five code-generated square-wave tones (`AlertTones`).
Order matters more than content volume; do not prioritise content production over core
gameplay.

| Priority | Layer | What it is for |
| :---: | :--- | :--- |
| 1 | **Warnings** — horde spotted, horde approaching (by bearing), wall under attack, breach, building lost | Counterplay needs the player to know without looking |
| 2 | **Weapon identity** — truncheon, bow, rifle volley, Maxim, artillery | COMBAT-4; §6 makes gunfire the loudest routine event |
| 3 | **Horde approach and siege intensity** — distant moan swelling with proximity and count; wall impacts | P2's "much bigger than I expected" |
| 4 | **UI feedback** — place, reject, select, order acknowledged | Fixes the "no-op clicks read as successes" class of defect |
| 5 | **Industrial machinery** — per building class, audible at tactical zoom, silenced when dark | Makes noise attraction legible: what you hear is what they hear |
| 6 | **Construction** | Activity reads as progress |
| 7 | **Settlement and zombie ambience** — town at day, silence at night, the dead in the fields | The lit/dark world framing |
| 8 | **Railway and steam atmosphere** | T3+ identity |
| 9 | **Music states** — calm / tension (horde visible) / siege / aftermath, with escalation | Dynamic audio escalation, last because it depends on every state above being detectable |

Why the Master bus is muted is not recorded; unmuting is a **[visual-human]**-class
call (a person has to listen) — `backlog.md`.

## 14. Visual quality bar

- **Units** eventually have idle, movement, attack (with recoil for firearms), hit
  reaction and death animations. Today: one static pose per direction; nothing
  animates (`HANDOFF.md` §1).
- **Buildings** show construction, operating (smoke/fire already exist), dark,
  damaged and ruined states. Today: construction and ruin exist; damage does not show.
- **Combat** is readable at battle zoom (D76's 46 px figures): who is firing, what is
  hit, what died. Today: no attack, hit or death presentation at all.
- **Density vs visibility is a design problem.** The full 60,000 crowd renders as a
  carpet (`backlog.md`); D85 chose the threshold by looking, and "density, not count,
  destroys legibility" is the rule. A battle must leave room to read buildings and
  units; the crowd is the threat's scale, not wallpaper.
- **Threat is on the map.** Infestation bands, horde bearing and noise reach must be
  visible at strategic zoom (FB-1).
- **Verify by looking.** Every real visual defect in this project was found in an image
  (`CLAUDE.md` §0.1). Visual work is `[visual-autonomous]` where a render can be
  captured and inspected, `[visual-human]` only where judgement of taste or feel is
  genuinely needed.

## 15. The twenty questions — where the spec stands

The audit's gap list. **Settled** = a user decision answers it. **Follows** = existing
systems already produce the answer. **[design]** = genuinely open; recorded in
`backlog.md`.

| # | Question | Standing |
| ---: | :--- | :--- |
| 1 | What does the player do every minute? | Pacing decided (D98); the minute-scale loop is micro combat, which still has no content (§5.12). |
| 2 | What are they deciding every few minutes? | Follows partly — where to push, what to build, whether to go dark. Pacing-blocked. |
| 3 | What changes over 30 minutes? | Follows once D98 lands — build-up toward the first clear (D99). |
| 4 | …over 60 minutes? | Follows once D98 lands — first tier and first real clear (D99). |
| 5 | …over 2-3 hours? | **[design]** §3; second settlement is the intended marker (D21). |
| 6 | Why expand? | Settled direction: deposits gate mines (2026-08-19), and nearby resources may deplete, forcing expansion (D99, "Perhaps"); unbuilt. |
| 7 | Why is expansion dangerous? | **Follows** — D39 export proximity, D49 frontage, D51 leaks, D9 re-infestation. |
| 8 | Why clear cities? | Settled (D103): pre-existing 1890s roads and rail, a larger settlement site, and timed salvage of ruins; unbuilt. |
| 9 | Why is a city different from an empty hex? | Follows for threat (D3/D49); reward settled by D103. |
| 10 | Why does industrialisation feel exciting? | **[design]** §7 — capabilities in spec, not wired. |
| 11 | Why does a second settlement feel important? | Settled (D21: it is where logistics begins); unbuilt. |
| 12 | Why does connecting settlements feel important? | Settled (D22-D29); unbuilt. |
| 13 | Why does a huge horde create decisions? | Settled (P2, D11, D17, D100, D101); chain broken in practice until those land (§5.5). |
| 14 | Why is defending a city fun? | **[design]** §5.6-5.7 — no active defence mechanics. |
| 15 | Why is attacking a zombie-held city fun? | **[design]** §5.8 — follows as a grind, lacks payoff and activity. |
| 16 | Why is discovering a resource exciting? | Settled (D99, D103): finite deposits from real geology deplete, so finding the next one matters; unbuilt. |
| 17 | Why does moving deeper into Britain change the situation? | **Follows** — census density rises toward the great cities (D3), D39 wakes Hive Cores as the player approaches. |
| 18 | Why care about specific locations? | Partly follows (§6 table); resource and city value **[design]**. |
| 19 | Why keep playing once comfortable? | Settled: growth and expansion draw bigger threats (D101); nearby resources run out (D99, tentative). |
| 20 | What is the climax of a successful campaign? | Settled as narrative target (London, 7.1 Act III; whole island, P6); mechanics deferred (P3). |
