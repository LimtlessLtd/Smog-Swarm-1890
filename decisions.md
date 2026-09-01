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

## 2026-09-01 — What a building's noise actually reaches

`backlog.md` asked for "§6's per-source dB and attenuation model" in place of a flat
2-hex aura it measured at ~43x the reach of §6's loudest listed sound. Taking that
literally turned out to be the wrong move, and the measurement that says so is the
first entry below.

**D66. §6's radius table is TACTICAL and is not implemented at the strategic layer.**
What is implemented is §6's *model* — source level, spreading, absorption, terrain —
with buildings on their own scale.
*Why, measured:* a tactical tile is 10 m (§7) and a macro hex is 8,647 m centre to
centre, so **every row of §6's table fits inside a twentieth of one hex** — melee 20 m,
rifle 150 m, Maxim 250 m, construction 80 m, artillery 400 m. Emission at those radii
never crosses a hex boundary, `HordeManager`'s ATTRACTED state scans whole hexes, and
the counterplay `vision.md` P2 calls the core tension engine of the game would stop
working entirely. §6 has no strategic entry to use instead: its only building row is
"Building Construction, 8 tiles".
*Consequence, accepted:* the reach of a building is a game-scale number and says so.
`NoisePropagation.HEARING_THRESHOLD_DB` is the one knob it hangs off, fitted so the
catalogue's loudest building pulls a horde from 2.03 hexes — where the flat disc it
replaces already reached — so this lands as a change of shape and not of balance.
Filed as a balance knob in `backlog.md`, and gated so it cannot drift silently.

**D67. `noise_output` (a 0-6 rank) becomes `noise_source_db` (dB at 10 m).**
*Why:* the old field's own comment already wanted what a rank could not express —
"a Foundry's hammering is louder than a Brickworks' kiln" — while every building above 0
projected the identical 2-hex disc and differed only in magnitude, uniformly, at every
hex inside it. With a real source level, reach is derived: **0.85 hexes for a Brickworks
against 2.03 for a Bessemer Smelting Complex**. 0.0 stays the "not machinery" sentinel;
it is not a 0 dB source.

**D68. Sources combine as intensities, not as sums.** Four equal buildings on one hex
are +6 dB.
*Why:* the old code summed contributions and its comment claimed that was "closer to how
real industrial noise stacks". It is the opposite — levels are logarithmic and it is
intensities that add — so a ten-building district read as ten times as attractive rather
than 10 dB louder. *Consequence, accepted:* stacking industry is a much smaller penalty
than it was, which the per-source reach spread more than replaces as a decision.

**D69. Terrain attenuation is computed per HEX and cached there, not per
source/listener path — and the elevation half of it reads the COARSE raster.**
*Why, measured, twice:*
- The first implementation ray-marched each source/listener path at 250 m through
  `SubHexTerrainQuery`. At 200 buildings a recompute took **55 s** and never got faster,
  because 7,400 pairs at ~70 samples each overran and thrashed the path cache.
  Sampling each hex's own terrain once instead and walking the hex line between
  endpoints costs one dictionary lookup per hex crossed: **0.23 s cold, 39 ms warm**.
- Within that per-hex sampling, `elevation_metres()` (the fine 30 m read `CLAUDE.md` §3
  names as sanctioned) loads one ~27 KB PNG per hex, which took a cold recompute from
  **0.23 s to 11.5 s** with only that line changed. The coarse raster's high-ground
  FRACTION differs from the fine one by 0.057 on average and 0.33 at worst over 140
  corridor hexes — **0.34 dB mean, 2.0 dB worst** once multiplied into the 6 dB rule.
*Why that is defensible and not merely cheap:* the quantity is a SHARE of a 65 km² hex
used as a share of a kilometres-long path integral, which is what an area fraction
is for. `RealTerrainSampler` makes the same call for the same reason — the fine bake
deliberately covers biome and terrain_feature and not elevation, because "elevation
varies smoothly enough at this scale". Biome, where sub-hex detail is real and cheap,
still reads the fine tile.
*What would reverse it:* a consumer that needs to know WHERE in a hex the high ground
is rather than how much of it there is. §6's line-of-sight work is that consumer, and
it is deferred.
*Also settled here:* §6's "Level 2/3 Highlands reduce propagation by 50%" is applied in
proportion to how much of the path is high ground, not whole the moment a path touches
any. The first version applied it whole, and the measurement caught it — HILL starts at
100 m and most of northern England clears that, so it fired on essentially every path
and became a global -6 dB rather than a property of a barrier.

---

## 2026-08-30 — What a ruin and a building site emit

Settled while closing the two gaps the going-dark work filed (see the section
below). Three systems read `vision_radius` and `lit_at_night` off the same
`BuildingInstance` and disagreed about what an unfinished or destroyed one
means; `design_doc.md` says nothing about either state (`grep -i ruin` on it
returns nothing), so these are gap-fills argued from the repo's own precedent
rather than spec compliance.

**D59. A ruin emits nothing at all — not even vision of its own hex.**
`FogOfWarManager._compute_visible_set()` skips a ruined instance outright
rather than zeroing its radius.
*Why:* four systems already answered this question the same way —
`LogisticsNetwork` ("rubble, not a functioning civic seat — projects
nothing"), `NoiseManager`, `CombatCoordinator`'s Searchlight beam, and
`BuildingManager.find_nearest_building()`'s "STANDING" test. Fog was the only
dissenter, and it was dissenting in the player's favour: a burnt-out Search
Light kept the `lit_at_night` bonus for a lamp that had stopped attracting
anything one skip earlier in `NoiseManager`. The repo's own test for which
side of the line something falls on is
`find_nearest_building()`'s: going dark is "about what a building emits and
produces, not about whether it is there". Vision is emitted.
*Accepted consequence, and it is not small:* the player loses live sight of
the ground at the moment they most want to watch it. Measured on the gate's
fixture at night, a destroyed Watchtower takes its hex count from **37 to 0**.
`HUDReconTracker`'s "horde approaching — ETA" warning is gated on fog VISIBLE,
so it goes silent exactly when the watchtower watching for that horde falls;
tactical figures in those hexes stop drawing, and horde markers freeze into
last-known-position ghosts. What survives is everything gated on
at-least-EXPLORED: terrain memory (permanent — `recompute()` never revokes
it), the minimap's own building dot, and therefore the ability to select the
ruin and order the repair.
*Reversal is small but not one word:* move the `is_ruined` test out of the
loop and into `_building_vision_radius()` as `return 0`, which keeps the
rubble's own hex VISIBLE and drops only the ring. Two lines, one behaviour
change, if it plays too abruptly.
*The consequence that is NOT symmetric with D60, stated so it is not
mistaken for an oversight:* a building being repaired stays `is_ruined` for
the whole 1-4 day job (`BuildingHealthController.process_day()` clears it
only at completion, and nothing sets `is_under_construction`), so a repair
site emits nothing while a construction site sees its own hex — even though
both are work parties standing on the same ground. That is `is_ruined`'s
existing meaning everywhere in the codebase, not a new rule here, and it was
already true of ZoC and noise before this change; only fog is newly affected.
Giving a repair site its own hex would need a "being repaired" state on the
instance, which does not exist, so it is left as-is rather than invented.

**D60. A construction site sees its own hex, casts no lamp, and stays loud.**
`vision_radius` and `lit_at_night` are properties of the FINISHED structure:
scaffolding is not a lookout and an uninstalled gas lamp is not lit. So a site
takes radius 0 (which still marks its own hex — `BuildingDefinition.vision_radius`'s
own doc comment), takes no night term at all, is not a Searchlight for
`CombatCoordinator`'s garrison beam, and does not contribute
`NoiseManager.NIGHT_LIGHT_ATTRACTION`. Its `noise_output` term is deliberately
left running, which is `NoiseManager`'s existing call (§6 rates Building
Construction at 8 tiles).
*Why not "a site sees nothing":* the work party is really there — that is the
same fact that keeps the site loud. It sees the ground it stands on and not
the county.
*Accepted consequence:* a Search Light under construction is now SILENT,
because its `noise_output` is 0 and the lamp was the only term it had. That is
wrong in the same direction §6 already is: the flat per-building model has no
term for construction noise at all and uses the finished building's machinery
as a stand-in. `backlog.md`'s noise emission rewrite is where that gets fixed;
this change does not make it worse for any building that has a `noise_output`.
*Not covered by the gate:* the `CombatCoordinator` clause. The beam is only
reachable through a full combat round, so it is argued from parity with the
other two rather than measured.

**D61. A gate and its trigger are one change, never two.** The same commit
connects `building_ruined`/`building_repaired`/`building_construction_completed`
to `FogOfWarManager`, `building_repaired`/`building_construction_completed` to
`NoiseManager`, and `building_ruined`/`building_repaired` to
`LogisticsNetwork`.
*Why:* a state gate that nothing recomputes against is invisible until some
unrelated event rebuilds the field — the next day-phase flip (up to half an
in-game day, and never while paused) or a unit crossing a hex boundary. Two of
the three gates here were already correct and only stale: `NoiseManager` had
gated ruin since it was written, and `LogisticsNetwork`'s ZoC ruin gate came
with its own explanatory comment. Neither was ever told when a building became
one. Measured before the fix: a destroyed Watchtower still lit **37 hexes 10
seconds later** and still projected ZoC over **7**.
*Accepted consequences, both real:* Military/Civilian ZoC — and therefore
`DiscontentManager`'s region membership, which reads
`get_civilian_covered_hexes()` — now collapses at the instant of ruin instead
of whenever the next recompute happened to land. And a ruin now costs two full
fog rebuilds where both managers are wired (fog's own trigger, then
`network_recomputed`). Neither manager may lean on the other's trigger to keep
its own state true, so the redundancy stays; `recompute()` is documented cheap
at this scale and a ruin is a rare event.

**D62. Zone of Control is still NOT gated on construction, and that is left
open rather than decided here.** A Watchtower or Search Light under
construction keeps projecting its Military aura, and fog reads ZoC coverage
verbatim as vision — so in the real game a building site still reveals a
one-hex ring, and D60's "its own hex and no more" describes fog's own building
loop, not the union.
*Why not just fix it:* the ruin trigger above restores an intent
`LogisticsNetwork` had already written down. Gating ZoC on construction is a
NEW rule about territory, supply and Discontent regions, with no precedent in
that file to lean on, and it would mean a placed Watchtower projects no
military control for its first 1-4 days. That is a design call, not a stale
trigger. Filed in `backlog.md`; stated in the gate's own header so no check
quietly depends on the wrong thing.
*What D60 costs while this stays open, and it is the sharpest argument for
closing it:* the lamp gate removed the only price an unfinished Watchtower or
Search Light paid. A site still projects its Military aura — 7 hexes of
ZoC-derived vision through fog — still holds its `storage_bonus`, and still
refunds 100% of its cost on demolish; what it no longer does is attract
anything at night. A permanently-unfinished tower is now a free, silent
watchpost. Nothing else in the game rewards not finishing a building, and
this is the one place that now does.

---

## 2026-08-30 — Going dark: buildings can be switched off

Settled while building `BuildingPowerController`. `design_doc.md` §2.1's "Going
dark" paragraph and D11 name four things an off building stops — production,
upkeep, noise, light — a restart delay proportional to tier, and nothing else.
These record what the spec left open, and one place the existing code had to
move to make the flag safe.

**D52. Going dark suspends what the BUILDING draws and produces. Its residents
are untouched.** A switched-off building is skipped for `daily_upkeep` and
`daily_output` (including the Energy/Population capacity entries), but its
`current_population` still counts toward the colony Food bill, toward
`DiscontentManager`'s overcrowding, and toward `SettlementFoundingController`'s
urban extent.
*Why:* the people in a mothballed tenement have not gone anywhere. The
implementation trap this exists to name is real and one line wide — the natural
change is to fold the power check into `BuildingSustenanceController`'s
existing ruin/construction skip at the top of its loop, which also deletes the
population accumulation underneath it. That would let a player switch off every
house during a famine and erase the colony's entire Food demand at no cost, and
it would put the Food bill and Discontent's headcount into permanent
disagreement. `verify_building_power.gd` distinguishes the two outcomes by the
exact size of the delta.
*Accepted consequence:* switching off a pure-housing building is close to a
no-op — it stops the building's own upkeep line and withdraws its Population
capacity grant, and does nothing else. That is correct rather than useless: a
house has no noise and no light to stop.

**D53. The restart takes its Energy/Population capacity at COMPLETION, not when
ordered — deliberately unlike repair.** `BuildingPowerController.restart()`
queues the countdown and moves no capacity; `process_day()` re-checks
affordability and applies it at the moment `is_powered_down` clears.
*Why:* it buys one invariant the whole feature leans on — **an instance holds
its capacity allocation exactly when `not is_ruined and not is_powered_down`**.
`BuildingHealthController.demolish()` tops that allocation back up on the way
out and has to know whether the building still holds it; with this ordering it
reads the answer off the instance's own two flags and needs no reference to the
power controller's pending list.
*What the alternative costs, measured against the existing code:*
`BuildingHealthController.repair()` applies capacity when the job is queued
while `is_ruined` stays true until completion, so demolishing a building
mid-repair silently leaks the allocation. That is a real pre-existing defect,
found while deciding this and **not fixed here** — it needs its own test and its
own change, and copying its ordering would have reproduced the same bug in a
second place.
*Accepted consequence:* a restart can be cancelled on the day it was due, if the
grid can no longer carry the draw. It is reported through
`building_restart_rejected` and toasted, because by then the player may have a
different building selected and nothing else would tell them. Silently
completing it is the one outcome that is not allowed: `CapacityAllocator.apply()`
discards `spend()`'s bool, so an unaffordable apply takes the grant without the
draw.

**D54. The Town Hall cannot be switched off** (`BuildingDefinition.always_powered`,
true on Town Hall alone).
*Why:* it grants +100 Population and +20 Energy capacity, and
`ResourceManager`'s POPULATION pool starts at 0.0 — that grant seeds the entire
ledger every other building and unit draws from. It also emits no noise and no
light, so blacking it out buys the player nothing at all toward P2 while
zeroing their capacity. A switch whose only effect is self-harm is a trap, not
a decision.
*Open to reversal, and cheap:* one line in `BuildingCatalog._town_hall()`. The
argument for allowing it is that the mechanic is more interesting if the capital
CAN go dark and the player pays for it. Raised for the user rather than settled
silently — see `backlog.md`.

**D55. Zone of Control, storage capacity and retreat targeting are NOT affected
by going dark.** `LogisticsNetwork`'s Civilian/Military ZoC still projects from
a switched-off Watchtower or Supply Dump, `storage_bonus` stays on
`ResourceManager`'s caps, and `BuildingManager.find_nearest_building()` still
returns a dark Garrison.
*Why:* the spec enumerates four things and these are none of them. A dark
watchtower is still the tallest thing in the parish, a dark Garrison is still
somewhere to fall back to, and switching off a Grain Silo should not spill the
grain. Going dark is about what a building EMITS and PRODUCES, not about whether
it is there — the same distinction `find_nearest_building()`'s own doc comment
now records.
*Deliberately reversible:* if ZoC should go dark too, it is one clause in
`LogisticsNetwork.recompute()` plus two signal connections.

**D56. Switching off is instant and free; the whole cost is the restart, at
`1 + tier` days.** Tier 0 costs 1 day, Tier 5 costs 6. Read off
`BuildingDefinition.tier` rather than through
`BuildingConstructionController.days_for()`'s cost proxy.
*Why instant:* it is the emergency move against a horde that is already walking
toward the noise. A delay on the way down would make it useless for the one job
it exists to do.
*Why tier and not cost:* D11 names tier, and the two are not the same ordering —
a Tier 5 Ordnance Complex and a Tier 1 Brickworks can land on the same clamped
1-4 construction days, and "banking a Victorian furnace and bringing it back up
is a real operation" has to bite hardest at the top of the tree.
*Placeholder balancing numbers, not an architecture decision.* Nothing has been
playtested against a horde yet; the shape (monotonic in tier, never zero) is
what `verify_building_power.gd` locks down, not the constants.

**D57. Ruin subsumes going dark: a destroyed building stops being "switched
off".** `BuildingPowerController.on_ruined()` drops any queued restart and
clears `is_powered_down`, called from `BuildingManager`'s `ruined` relay before
the ruin is announced. `BuildingHealthController.damage()` skips its capacity
refund for an instance that was already dark.
*Why:* found by adversarially reviewing the first cut, and it is the ORDINARY
sequence rather than an edge case — going dark is the emergency move against an
approaching horde, so "switched off, then wrecked by that horde" is the expected
path. Three defects fell out of the overlap, all of them capacity leaks:
ruin refunded an allocation `power_down()` had already released (measured:
**+20 Energy and +25 Population minted from nothing** on a Coal Mine); a restart
queued before the building was destroyed completed days later on the rubble,
drawing the full allocation for a building that no longer stood; and a repair
completed while the flag was still set, leaving an instance that was not ruined,
still flagged off, and holding capacity — at which point the Restart the UI
offered would have applied it a second time.
*The rule that resolves all three in one line each:* rubble is not "switched
off", it is rubble. `is_ruined` already takes precedence everywhere, so letting
the two flags overlap bought nothing and cost three leaks.
*Consequence, taken deliberately:* a building switched off, destroyed, then
repaired comes back RUNNING, not dark. A repair is a full rebuild paid at full
capacity cost; coming out of it still mothballed would be a silent second cost.

**D58. An in-flight restart can be cancelled.** "Switch off" on a building that
is already dark and counting down drops the job and leaves it dark
(`BuildingPowerController.power_down()`'s early branch); the panel button reads
"Cancel restart" in that state.
*Why:* the first cut refused it ("already switched off"), which meant an ordered
restart could not be stopped. A horde turning toward the district on day 2 of a
5-day restart would be met by a foundry lighting up on schedule — the exact
situation the mechanic exists for, failing at the one moment it matters.
*Free to implement, because of D53:* `restart()` takes no capacity, so
cancelling has nothing to release and nothing to reverse. Dropping the queued
job is the whole operation.

**Two pre-existing gaps found while wiring this, recorded rather than fixed.**
Both are out of scope and neither is made worse here. **Both closed 2026-08-30
— see the section above (D59-D62).**
`FogOfWarManager._compute_visible_set()` checks neither `is_ruined` nor
`is_under_construction`, so a ruined building still lights the map and a
construction site sees at full radius — the `is_powered_down` clause added there
is the first instance-state gate in that loop. And `NoiseManager` listens to
`building_ruined` but not to `building_repaired` or
`building_construction_completed`, so a repaired building stays silent until the
next day-phase flip. Filed in `backlog.md`.

---

## 2026-08-29 — Combat against a hex's residents

Settled while building `ResidentDefenseController`. `design_doc.md` §2.1 is
unchanged apart from an "as built" table; these record how the resident half of
a hex's population became fightable, which is the gap D42 knowingly left open
("a hex's RESIDENT population is drawn but cannot currently be fought").

**D48. A hex's residents CONDENSE into a defending `Horde`; combat never learns
a second kind of enemy.** `InfestationManager.condense_defenders()` moves a
count out of `_resident` and into a `Horde` standing on the hex it left.
*Why:* `Horde` is already what `CombatCoordinator` fights, `TerritoryController`
tests for, `HordeManager` paths and `SaveLoadManager` saves. Fighting residents
directly means teaching all four about a second enemy type — and a
`CombatEngine` defender built from 446,729 zombies is 893,458 HP dealing 223,364
damage a round, which annihilates anything in the roster on contact, so the
count would have needed bounding anyway. Conservation then costs no code at all:
the same transfer `export_from()` already performs, so `zombie_count_at()`,
`infestation` and the band do not move when a wave rises. Only killing moves
them, which is D8 intact rather than D8 worked around.
*What falls out for free:* the save round-trips with no new state (a defending
wave IS a horde), the tactical layer draws the wave without changing (D44's
horde pass has priority over the resident pass, which is the right order — the
zombies in the fight are the ones the player is looking at), and a wave that
survives and wanders off is an ordinary roaming horde with no special case.

**D49. The wave is a FRONTAGE — an area of the hex's own density — not a
fraction of its population.** `ResidentDefenseController.frontage_for()` is the
residents inside a 30 m disc (`HexCoord.SUB_HEX_CELL_SIZE_METERS`) of the hex's
own density, against `HexCoord.hex_area_square_metres()`, floored at 1 and
capped at the residents present.
*Why:* how many zombies can reach a squad is bounded by geometry, not by how
many live in 25 square miles. A flat percentage hands London a wave of thousands
and ends the run on contact, and hands a Highland hex a wave of zero. Measured on
the real map (`scripts/test/diagnose_resident_combat.gd`):

| hex | residents | wave |
| :--- | ---: | ---: |
| Greater London | 446,729 | 20 |
| Birmingham | 321,008 | 14 |
| Manchester | 68,075 | 3 |
| two hexes from the player's home | 31,702 | 1 |

which makes §2.1's "capacity is the difficulty curve, and that is the point"
true at the tactical layer as well as the strategic one, off one constant that
was already in the project.
*Why the floor of 1:* below ~11,450 residents the disc holds less than half a
zombie, and a hex that can never field a defender can never be cleared either,
because clearing IS killing. The floor is what makes an emptying hex finishable.

**D50. The wave is topped back up between one unit's round and the next, so a
stack of units kills in proportion to its size.** `run_wave_tick()` calls
`reinforce()` inside its per-unit loop, and `CombatCoordinator.engage_unit()` is
per unit rather than per hex for exactly that reason.
*Why:* the first version topped a hex up once and then resolved every unit's
round against what was left. On low-density ground the frontage is 1, the first
unit wipes it, and `_engage()`'s own `horde.size <= 0` early-out means the other
nine units engage nothing — **ten units clear a hex exactly as slowly as one**,
and no amount of balancing the combat numbers lifts that ceiling, because it is
a property of the wave rule and not of the damage. Interleaving fixes it without
touching `CombatEngine`: every unit meets a full frontage, so incoming damage
per unit is independent of stack size, while the gap each unit cuts is refilled
before the next one swings. Measured at **10.0x for ten units** afterwards, and
`verify_resident_defense.gd` fails below 5x so the ceiling cannot come back.

**D51. A hex holding player units and hordes now fights CONTINUOUSLY, one round
per `WAVE_INTERVAL_SECONDS`.** This replaces `CombatCoordinator`'s original
"one-shot, not continuous: an engagement fires off a MOVEMENT signal".
*Why:* the tide has to keep coming. Once a defending wave is at frontage
strength nothing moves, so a movement-triggered resolver stalls the grind
exactly when the fight is hardest, and a unit parked on a Hive Core stands in
446,729 zombies doing nothing. 20.0 s matches `HordeManager.LOGIC_TICK_SECONDS`
and `UnitOrderController.LOGIC_TICK_SECONDS` — the last of those matters, because
`GARRISON_REGEN_FRACTION_PER_TICK` heals 5% of max HP on that same interval, so
one round of incoming damage against one tick of regen is a comparison the
player can actually reason about. That comparison is what decides whether ground
can be held, measured on the real map:

| hex | wave | Truncheoneer garrison | Holt Breaker garrison |
| :--- | ---: | :--- | :--- |
| two hexes from home | 1 | holds; 50 clear it in 5 days | holds; 50 clear it in 5 days |
| Manchester | 3 | wiped in 76 rounds | holds; 50 clear it in 5 days |
| Birmingham | 14 | wiped in 4 rounds | holds; 50 clear it in 8 days |
| Greater London | 20 | wiped in 3 rounds, having killed 1 | holds; 50 clear it in 12 days |

*Three consequences accepted knowingly:*
1. **A Contested hex now leaks, but only in response to the player.** §2.1's "a
   hex below 75.0 spreads nothing" becomes "spreads nothing PASSIVELY": a
   defending wave that survives and wanders off is a roaming horde. It is at
   most one frontage at a time, no zombie is destroyed without being killed, and
   poking a hive to draw it out is P2's own "draw the horde away with some
   military units". Re-absorbing strays was considered and rejected: it needs a
   horde-shrinking API, per-hex debt bookkeeping and save state, to prevent a
   leak of 20 zombies at a time out of 446,729.
2. **"Under attack" alerts had to be de-duplicated.** `EventManager` raised a
   COMBAT/WARNING per engagement, which is a tone and a toast every round for as
   long as the player holds the line. Now once per unit per day, on the same
   "raise on the transition INTO the bad state" shape its food-band and
   resource-shortfall trackers already used. A CRITICAL death is never
   suppressed.
3. **Veterancy inflates, and the cause is a definition rather than this
   change.** `UnitMorale.get_rank()` counts hordes destroyed, not zombies killed
   (its own doc comment settles that), and a frontage-1 wave is a horde that
   dies every round — so a unit on low-density ground is ELITE (10 kills) after
   200 simulated seconds. Bounded at +25% damage rather than runaway. Filed in
   `backlog.md` rather than fixed here, because redefining what a kill is
   belongs with the balance pass and not inside this seam.

**Residents do not attack player BUILDINGS.** Only a player unit standing on the
hex makes a wave rise. A horde reaching an undefended building already sieges it
(`CombatCoordinator._siege_buildings()`), and a wave that wanders off can do the
same by the ordinary path; what is deliberately absent is a hex's own population
spontaneously attacking a Watchtower placed on Fringe ground, which would make
§2.1's own Fringe build rights self-defeating.

---

## 2026-08-29 — Tactical zombie layer

Settled while building `ZombieSwarm` / `ZombieSwarmManager` / `LiveHexTracker`.
`design_doc.md` §2.1 is unchanged; these record where the implementation had to
answer something D12-D15 left open, and what was measured before it did.

**D42. The tactical layer is a VIEW of counts the strategic layer owns, not a
transfer of ownership.** D14 says a horde "dissolves into entities on entering a
live hex and re-condenses on exit, conserving its count". Read literally that
means the `Horde` stops existing while its zombies are individuals. It does not:
the `Horde` stays the authority, and each frame a crowd's size is driven toward
`Horde.size` plus `InfestationManager.resident_count_at()`.
*Why:* `Horde` is what `CombatCoordinator` fights, `TerritoryController` tests
for, `HordeManager` paths and `SaveLoadManager` saves. Moving ownership into a
packed array means teaching all four about a second kind of enemy, for no
gameplay difference — the player sees individuals either way, kills them through
the same combat, and watches the same count fall. Conservation then costs no
code at all: nothing is ever transferred in, so nothing can be lost or
double-counted.
*Accepted cost:* a hex's RESIDENT population is drawn but cannot currently be
fought. Combat engages `Horde`s, and residents are not one. Filed as its own
backlog item rather than bolted on here.

**D43. The live set is empty outside Tactical zoom.** §2.1's rule is "camera hex
+ six neighbours + player units/buildings" with no zoom clause; `LiveHexTracker`
adds one.
*Why:* §2.1 bounds instantiation by observation — "the player cannot detect the
difference, because they cannot observe 60,000 zombies' worth of ground at
once" — and at Strategic zoom the player observes no individuals at all, because
`TacticalEntityLayer` hides itself entirely below
`CameraController.tactical_zoom_threshold`. Instantiating a crowd nothing can
draw is pure cost; measured at 0 individuals on the real map from Strategic zoom.
*Accepted cost:* zooming out and back in re-scatters a crowd's internal
arrangement. Its POSITION does not move — that belongs to the `Horde` or the
hex — and no player can remember where 60,000 dots were.

**D44. The budget is spent hordes first, then residents, both nearest the
observer.** `HORDE_BUDGET_FRACTION` reserves half of `ENTITY_BUDGET` for hordes
before a hex's own population gets any.
*Why:* measured on the real map (`diagnose_tactical_zombies.gd`). Standing on
the busiest Greater London hex, **2,123,376 zombies want instantiating and 60,000
can be** — a purely nearest-first walk hands the entire budget to the hex under
the camera and a horde attacking the player from the next hex renders as nothing.
The one thing the player is certainly looking at has to be served first. §2.1's
own London claim falls out of the second pass: ~60,000 real zombies with ~2.06
million behind them.

**D45. How finely a step is sliced is decided from the whole live population,
not from one crowd's size.** Every `ZombieSwarm` in a frame shares one division.
*Why:* measured, and the per-swarm version was wrong by 4x
(`bench_zombie_swarm.gd`, 60,000 zombies): as one crowd it sliced and cost
**2.75 ms**; split across 30 crowds of 2,000 each nothing reached the slice
threshold, so everything moved every frame and it cost **11.11 ms** — two thirds
of the frame. Deciding globally puts the split case back at **2.79 ms**. The
frame does not care how the budget is divided between crowds; it cares how many
zombies moved.

**D46. A crowd chases its anchor faster than it mills, and re-forms rather than
chases when the anchor teleports.** `CHASE_SPEED` is 2x `BASE_MOVE_SPEED`;
past `SNAP_SPREAD_MULTIPLE` a zombie is re-placed around the anchor instead.
*Why:* milling speed is a quarter of `BASE_MOVE_SPEED` and a horde travels at up
to 1.5x it (`HordeManager.NIGHT_MOVE_SPEED_MULTIPLIER`), so a crowd steered home
at milling speed can never catch its own horde — every advancing horde would have
strewn its individuals behind it across the map. Caught by
`verify_tactical_zombies.gd` while it was still failing. The snap covers the
three cases that are teleports rather than movement: a game speed high enough
that one `MAX_STEP_SECONDS`-clamped step covers less ground than the horde
crossed, a load, and a reallocation.

**D47. Positions are saved; identity is not.** D15's packed float32 positions are
pooled per hex and consumed in group order on load, not keyed by horde id.
*Why:* a horde that merged, split or was killed between save and load would
strand its slice. The point of saving positions is that a crowd does not visibly
teleport, not that any individual zombie is the same one. Measured at **468.8 KB**
for a full 60,000-zombie live set, against §2.1's "under 500 KB" estimate. A save
whose counts have since moved still lands: each crowd takes as many saved
positions as it can use and scatters the rest.

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
