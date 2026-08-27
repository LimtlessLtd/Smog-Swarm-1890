# The Smog & The Swarm — Project Index

> **Restructured 2026-08-27.** This file was 203 KB doing six jobs at once — spec
> addendum, roadmap, dev log, defect tracker, decision record, and design rationale —
> so answering "what should I work on" cost ~50 k tokens before opening a single `.gd`
> file. It is now an index plus the reference sections that don't churn.

## Where things live

| File | What it answers | Read at session start? |
| :--- | :--- | :--- |
| `vision.md` | What the game is *for*. Pillars, anti-goals, and the three checks every backlog item must pass. | **Yes** |
| `backlog.md` | What to build next, tagged `[gated]`/`[visual]`/`[design]` and split Now / Next / Deferred. | **Yes** |
| `decisions.md` | Calls that are settled, and why. Read before re-opening any of them. | On demand |
| `design_doc.md` | The numbers spec: terrain, economy, buildings, units, infestation (§2.1), logistics (§2.2), vision/sound/light (§6). | On demand |
| `todo.md` | This index, plus the reference sections below. | Skim |
| `devlog/` | Append-only history of completed work, archived monthly. | **No** |
| `CLAUDE.md` | Coding rules that override default behaviour. | **Yes** |

**Only `[gated]` items in `backlog.md` may be taken by an unattended loop.** `[visual]`
needs a render or a playtest agent; `[design]` needs the user.

---

## Technical Summary

Godot 4.x/GDScript RTS on a continuous axial hex map of real UK+Ireland geography
(Natural Earth coastline, ~25 sq mi/hex, ~4,692 land hexes). Terrain is real data baked
offline by `tools/geo_bake/`: land-cover from OpenStreetMap vector geometry (Geofabrik
`.osm.pbf` extracts of GB + Ireland) shipped as a **continuous triangle mesh** — real
polygon boundaries, not a raster and not hex tiles — while elevation stays raster from
AWS/Mapzen Terrain Tiles. Rendering reads the mesh; the 30 m mechanical queries still
read the older raster, and closing that gap is `backlog.md`'s "epic phase 2". A two-tier
camera (Strategic hex-icon / Tactical true-scale, `HexCoord.HEX_SIZE` = 512 world
units/hex) drives everything from country-scale strategy to individual soldiers.

**Built and playable end to end:** full economy, building tree, tech tree, 18-unit
roster with combat/morale/veterancy, horde AI, walls/ZoC/supply lines, Fog of War,
Day/Night, save/load, and a complete code-drawn HUD.

**Not built:** the entire §2.1 infestation model and §2.2 logistics rework settled on
2026-08-27 — `infestation` appears nowhere in the code and the map holds ~45-75 zombies
across 4,692 hexes. Also §6 (Vision/Sound/Light), the sewer layer (Phase 3), and the
campaign (Phase 5.11, Phase 7).

Godot binary: `E:\Program Files\GoDot\Godot_v4.7.1-stable_win64_console.exe`. For
anything touching a manager's `_ready()`, run `--headless scenes/main/Main.tscn --quit`,
not just `--headless --quit`.

---

## 📖 The Setting

January 1890. Something came down over the Pennines in the night, and within a week the
dead of Manchester were walking. The city sealed itself hard — gaslit checkpoints, a
militia raised from constables and navvies, whatever the Industrial Revolution could
throw up in a fortnight — and held. Beyond the wire, the rest of Britain went dark: no
telegraph, no trains, no light after sundown, just the slow drift of the hungry across a
country that used to be the workshop of the world. You inherit that quarantine: one lit
town in an island of soot and silence, armed with nothing but cast iron, coal smoke, and
Victorian grit — no borrowed future technology, just the Industrial Revolution pushed as
far as it will go. South of you, Queen Victoria and the Imperial Cabinet are sealed in a
bunker under the Tower of London, and nobody above ground knows if they're still alive.
Scattered through the wreckage are stranger traces still — wrecked observatories, craters
that don't match any war, rumours of things that didn't fall from the sky by accident.
Your job isn't rescue. It's to hold the light, push roads and rail south hex by hex, and
find out — expedition by expedition — whether Manchester's quarantine was the last sane
decision the old world made, or the first sign that whatever did this was already here.

---

## 🏛️ Project Architecture & Design Overview

- **Core Loop:** Continuous persistent expansion across Victorian Britain hex sectors.
  Build defenses, automate patrols, manage daily resource upkeeps (Food/Energy/Gunpowder),
  and protect supply lines.
- **Aesthetic Direction:** Grounded late-18th/19th-century Industrial Revolution (brick,
  cast iron, coal smoke, authentic Victorian architecture) — explicitly **no**
  retro-futuristic steampunk tropes, including top-tier "mechanized" units (heavy steam
  engineering, never a humanoid battle-mech).
- **Dual Perspective Engine:** Camera toggle between Top-Down Orthographic and 2.5D
  Isometric.
- **Multi-Layer Macro-Hex System:** Each hex = a ~25 sq mi macro-region. Cities scale
  across multiple macro-tiles — Manchester spans 4 hexes, Greater London spans 12.
- **Time Controls & Day/Night Cycle:** Global `TickManager` supporting `0x`/`1x`/`2x`/
  `3x`/`5x` speeds. 40-minute real-time day/night cycle at 1x.
- **Accessibility:** Every color-coded piece of state (biome, ZoC, fog-of-war, building
  category, alerts) is paired with a distinct shape/icon, never color alone.
- **World State Framing:** Outside player-held ground, 1890 Britain is dark and roamed by
  hordes with no fixed home. Player settlements are the only lit, defended points on the
  map.

---

## 🚫 Explicitly Out of Scope

> Considered and declined, not merely forgotten — worth stating plainly so nobody
> re-litigates these mid-project. Revisit only if the game's commercial scope changes.

- **Multiplayer / co-op.** Single-player only; the whole design (one player's colony)
  assumes it.
- **Steam Workshop / mod support.** Not for initial release.
- **Rival human factions / diplomacy.** The threat is zombies (plus the alien-origin
  mystery); no competing AI colonies or negotiation systems.
- **Full localization.** English only for initial release.
- **Mainland Europe.** Europe is a future paid expansion if the game finds an audience,
  not built for v1.0. See `vision.md` §4 for the v1.0 cut order.

---

## 🧩 Known Architecture Constraint: Hex-Grid Over-Coupling

> One hex is ~25 sq. miles — the fields below are still a single scalar for that entire
> area, which doesn't match real terrain. Biomes/elevation and wall geometry are already
> real sub-hex resolution (closed 2026-08-10 and earlier). Still hex-locked today:

- **Supply lines** (`SupplyLineSegment.hex_a`/`hex_b`) — whole-edge only, the same shape
  walls used to have before their rework. **Now scheduled**: `decisions.md` D24 gives
  them real geometry reusing `WallManager.place_wall_line()`.
- **Zone of Control, Noise, Fog of War** (`LogisticsNetwork`, `NoiseManager`,
  `FogOfWarManager`) — flat per-hex `Dictionary` state, no gradient across the hex's own
  area. Noise emission is scheduled for rewrite (`backlog.md`, Now).
- **Districts** (`District.gd`/`DistrictPartitioner.gd`) — fixed categorical template per
  hex (always exactly Urban Center + Industrial Estate + Uncleared Wilderness for a
  settlement hex), no real position/shape/geography.

**Also disclosed:** the full map span (~214,600 x 136,700 world units) is past the
~100,000-unit range where single-precision float jitter typically starts
(`HexCoord.HEX_SIZE`'s doc comment) — no jitter observed live so far; a floating-origin
camera rebase is the real fix if it ever surfaces.

---

## 📐 Standing Directive: Design Against *They Are Billions*, Don't Invent New Mechanics

> User feedback, 2026-08-09, verbatim in spirit: "This is all built in They Are Billions
> but for some reason I'm having to spec it out again... you aren't basing these mechanics
> on what I am [referencing] and instead inventing your own mechanics."

**Before designing or redesigning wall placement/destruction, zombie movement/AI, or
siege behavior, research how *They Are Billions* actually implements it first, and match
that model** rather than deriving a new one from first principles.

Where this project knowingly departs from TAB, the departure is recorded in
`decisions.md` with its reason — §2.2's logistics layer being the clearest example, since
TAB has no logistics network at all.
