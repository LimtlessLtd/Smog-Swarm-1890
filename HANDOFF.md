# Handoff — Battle Scale

> **Scope and expiry.** Written 2026-09-07 for whoever picks up the battle-scale epic.
> This is a bridging document, not a sixth permanent doc — everything durable in it is
> already in `decisions.md` (D76-D87) and `backlog.md`. **Delete this file once the
> epic's Now items are ticked.** Do not let it grow; `CLAUDE.md` §0 exists because
> `todo.md` became exactly this and then never stopped.

---

## 1. Where this came from

The user asked how close the project is to "a massive, 19th century Britain version of
*They Are Billions*", naming two areas they believed needed work: **unit and zombie
movement/models**, and **graphics**. An analysis followed, then two design questions
were put to them and both were answered. The answers are D76-D87.

**Headline finding, so you don't re-derive it:** the simulation is far ahead of the
presentation. Movement is already continuous world-space integration with steering
(`MovementStepper`), and 60,000 individually-positioned zombies already step in 2.79 ms
(`ZombieSwarm`, measured). What was wrong was never the sim. It was that **the camera
never gets close enough to see a person** — `max_zoom` 12 shows 1,040 m of ground —
and that **nothing animates**: `render_directional.py` renders one frozen pose per
direction, and `grep -rn "AnimatedSprite|SpriteFrames|AnimationPlayer" scripts scenes`
returns nothing.

---

## 2. Read these, in this order

1. `vision.md` — unchanged. P2 (hordes big enough to end the run) and P5 (scale is
   literal) are the pillars this epic serves.
2. `decisions.md` — **D76-D87**, the top three sections. They are the spec.
3. `backlog.md` — the "Battle scale (D76-D80)" block at the top of Now is the work.
4. `CLAUDE.md` §3 — terrain granularity. D79 depends on reading through
   `SubHexTerrainQuery`, and §3 is the rule that says why.

---

## 3. What was decided

| | Decision | State |
| :--- | :--- | :--- |
| **D76** | `max_zoom` 12 -> ~128, honest metric figures (3.5 m, 46 px at 128) | live |
| **D77** | Figure size per zoom band, not a world constant | amended by D86 |
| **D78** | Entity allocation keys on the camera rect, not the hex | live |
| **D79** | Residents cluster on URBAN/INDUSTRIAL sub-cells | live |
| **D80** | `HORDE_BASE_SPREAD` is ~77x too wide; 20.0 -> ~0.26 | live |
| **D81** | Rendering is not the constraint. Simulation is. | measured |
| **D82** | Threshold -> 16-20 | **superseded by D85** |
| **D83** | `ENTITY_BUDGET` stays 60,000 | confirmed |
| **D84** | Animation is free to render, ~25-40% more to simulate | measured, confounded |
| **D85** | `high_fidelity_threshold` 2.0 -> **48.0** | live |
| **D86** | Metric crossover IS the threshold; D77's third band deleted | live |
| **D87** | The MEDIUM -> HIGH pop at 48 needs handling | open |
| **D88** | The crop is a pixel copy; a MultiMesh drops an AtlasTexture region | built |
| **D89** | Squad scatter is metric too, at 6 m | built |
| **D90** | D80's spread has a floor under ~50 zombies, accepted not fixed | built |

---

## 4. What is actually built

**§6's bundle landed 2026-09-07.** `CameraController.max_zoom` is 128.0,
`high_fidelity_threshold` is 48.0, `ZombieSwarmManager.HORDE_BASE_SPREAD` is 0.2588,
`UnitVisuals`/`ZombieVisuals`/`PropVisuals` return cropped textures, and
`TacticalEntityLayer` sizes HIGH's figures in metres. Full account in
`devlog/2026-09.md`; the three calls it forced are D88-D90.

Also present, and run by hand — neither is picked up by `run_verifications.py`
(it globs `verify_*.gd`), and `check_gdscript.py` covers both:

- `scripts/test/bench_zombie_render.gd` + `scenes/test/bench_zombie_render.tscn`
  — the cost measurement. **Windowed, not headless.**
- `scripts/test/preview_crowd_threshold.gd` + `scenes/test/preview_crowd_threshold.tscn`
  — renders threshold candidates in seconds, no map generation. **Windowed.**

---

## 5. The numbers, so you don't re-measure them

**Scale.** `HexCoord.HEX_SIZE` 512 wu, `WORLD_UNITS_PER_REAL_METER` 0.1025599, so
**1 wu = 9.75 m**. A hex is ~5 km circumradius, 64.7 km². A 3.5 m figure is 0.359 wu.

**Render cost** (`bench_zombie_render.gd`, RTX 2060, OpenGL Compatibility, 1280x720,
vsync off, median of 60 frames):

- 120,000 sprites at **75x screen coverage** — 2.93 ms
- 20,000 sprites painting the screen **89x over** — 1.88 ms
- Fill rate is ~10x under budget everywhere the game can reach. There is no overdraw
  problem. Do not spend time on one.

**Whole-frame cost**, live `ZombieSwarm` crowds stepped and uploaded each frame, counts
derived from London density:

| zoom | figures | px each | sim ms | total ms |
| ---: | ---: | ---: | ---: | ---: |
| 2.0 (today) | 452,102 | 0.7 | 24.16 | **24.67 OVER** |
| 5.0 | 72,336 | 1.8 | 3.57 | 3.83 |
| 12.0 | 12,558 | 4.3 | 0.62 | 0.86 |
| 48.0 (chosen) | ~490 + horde | 17.2 | — | ~0.63 at 12,834 |
| 128.0 | 110 | 45.9 | 0.03 | 0.26 |

**Sprite framing** — measured alpha bounding boxes in 2048² frames:

| asset | content fills | note |
| :--- | :--- | :--- |
| `zombie_0_s.png` | 22.3% w x 40.3% h | never re-rendered fitted |
| `redcoat_s.png` | 30.8% x 49.9% | never re-rendered fitted |
| `cast_iron_foundry.png` | 81.2% x 75.2% | re-rendered through `frame_content()` |

Consequences, since fixed: figures rendered **2.5x too small** and sat **~15% of a
frame above their own simulated position**, so they hovered.
`TextureCropUtil.tight_crop_copy()` (new, D88) is now called from
`UnitVisuals`/`ZombieVisuals`/`PropVisuals`; `tight_crop()`'s AtlasTexture view still
serves `BuildingIconButton` and cannot serve a MultiMesh.

**Densities** used throughout: residents 0.0129/m² (a London hex at ~5e5 over ~60%
urban, per D79); a horde 0.25/m², ~19x tighter.

---

## 6. Do this next

The four pieces above landed as ONE change, because each is wrong without the others:
cropping alone raises a zombie from 4.03 wu to the full 10 wu — ink per figure up
**6.2x** — so it makes the crowd shot *worse*, and D80's spread alone turns hordes
into dots at the old zoom. What remains is not coupled that way; do not bundle it.

In order:

1. **D87's MEDIUM -> HIGH transition.** Visible now rather than hidden — crossing 48
   jumps from 5 figures per horde to all of them in one scroll click. `[design]`.
2. **D78's camera-rect allocation.** This is why `06_battle_scale.png` is thin:
   residents still spread over a 384 wu disc, of which a battle-scale screen is
   0.05%.
3. **D79's urban clustering**, which is what puts anyone in that frame once D78 aims
   the budget at it.
4. **The stride 8 vs 12 A/B** (D84), before animation commits to a buffer layout.
5. Animation.

**Verify by looking**, still. `smoke_screenshot.gd` shoots six framings now;
`06_battle_scale` is the one past the threshold and `05_tactical_crowd` holds its old
framing as the before. Every real visual defect in this project was found in an image.

---

## 7. Traps that cost real time

- **Headless measures nothing here.** Under the dummy rendering server a MultiMesh backs
  no storage — `buffer` reads back empty. Any bench or preview touching the crowd must
  be **windowed**. `ZombieSwarm`'s own doc comment records this.
- **`MultiMesh.custom_aabb` must be set after assigning `buffer`.** Assigning the buffer
  does not recompute the AABB, so every instance measures as the identity transform and
  the whole crowd culls. `TacticalEntityLayer._refresh_swarm_batches()` records finding
  this by screenshot; both new scripts guard against it.
- **Line endings are per-file.** `backlog.md`, `CLAUDE.md`, `vision.md`, `design_doc.md`,
  `todo.md` are **CRLF**; `decisions.md` is **LF**. A naive Python read-modify-write
  normalises the whole file and produces a 1,200-line diff that hides the real change.
  Check `git diff --stat` after any scripted doc edit.
- **Textures are imported uncompressed** (`compress/mode=0`) at 2048², i.e. 16.8 MB each
  in VRAM, in `static var` caches that are never evicted. 18 unit types x 8 facings is
  2.4 GB if a session sees them all. Backlog item; fix it with the crop.
- **Do not fan out 17 subagents at once.** The workflow that started this analysis died
  wholesale on a session API limit and returned nothing. The work was done inline
  instead, faster.

---

## 8. Distrust these

Reasoning that turned out wrong, so you know which conclusions are load-bearing and
which were guesses:

- **"Zoom 32 is the right threshold."** Recommended from sparse-resident legibility,
  then refuted by `engulfed_032.png` — a packed horde at 11.5 px collapses back into
  grain. Density, not count, destroys legibility. D85 has the corrected reasoning.
- **"Animation costs memory and nothing else."** Written into the bench's own header and
  refuted by its own numbers: stride 12 measured 25-40% more sim time (D84). **But the
  comparison is confounded** — `_WideCrowd` is a faithful-but-not-identical mirror of
  `ZombieSwarm.step()`. A clean A/B with the real class at both strides is owed before
  the animation work commits to a buffer layout. It is in the backlog.
- **"They Are Billions holds ~20,000 on screen."** This is `vision.md`'s own recorded
  claim about TAB's endgame swarm, and it is a **map total, not an on-screen count** —
  the research that would have confirmed it died on an API limit. D85's crowd-size
  argument leans on it. If TAB genuinely peaks far higher on one screen, revisit 48.

---

## 9. Open, and the user's to answer

- **D87** — how the MEDIUM -> HIGH transition at zoom 48 is handled. Crossfade, or scale
  MEDIUM's cluster count with zoom. Not designed.
- **Resident density at battle scale.** At 48 an ordinary infested hex shows ~490
  residents across 260 x 146 m — bodies about, not crawling. If cities should feel
  denser the lever is D79's urban concentration, not the threshold. The user was offered
  a re-shoot at tighter clustering values and has not taken it up yet.
- Everything already `[design]`-tagged in `backlog.md`'s Now section is untouched by
  this epic and still waiting.
