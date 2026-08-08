# Unit art generation pipeline (Phase 6.3.1/6.3.2)

**Status: infrastructure built, images not yet generated.** No tool in this
Claude Code environment can call an AI image generator — this README, the
18 prompts below, and the code in `UnitVisuals.gd`/`TacticalEntityLayer.gd`
are the complete, ready-to-use pipeline; someone with access to an actual
image-generation tool (a future session, or the user directly) needs to run
the prompts and drop the resulting PNGs into this folder. Nothing else
changes when that happens — see "Drop-in workflow" below.

This is deliberately a *different* path from terrain (`assets/terrain/`)
and buildings (`assets/buildings/`), both of which ended up hand-authored
SVG instead of AI-generated (see `todo.md` Phase 6.3.0/6.3.0b) — the user
explicitly chose AI generation for units when asked, so this doc exists
instead of 18 more hand-drawn SVGs.

## Format

- **PNG, not SVG.** Raster is the natural output of an image-generation
  model, and it sidesteps the exact bug hand-authored SVG hit twice on this
  project (Godot's ThorVG SVG importer silently rasterizes `<pattern>`
  fills as fully transparent — see `assets/terrain/`'s own git history,
  commit `ebd3882`). A plain PNG has no such pitfall.
- **512x512px, transparent background.** Matches the terrain/building art's
  own canvas convention (256/512 square tiles) closely enough to read as
  one consistent art scale across the game, even though these are
  standalone character/vehicle sprites rather than tiles.
- **Single figure or vehicle, front-or-3/4-angled view, filling most of the
  frame with a small margin.** These render small (Tactical zoom, squad
  figures ~12-32 screen px, vehicles somewhat larger) — a cluttered or
  distant composition won't read at that size. Same reasoning terrain's own
  art avoided fussy fine detail concentrated where it wouldn't be seen.

## Shared style guide (prepend to every prompt, or bake into a model's system/style setting)

> Grounded, late-19th-century Industrial Revolution aesthetic — 1890s
> Britain. Authentic Victorian military/civilian dress and equipment:
> wool, leather, brass, cast iron, coal soot. **Explicitly NOT
> retro-futuristic steampunk** — no goggles-and-gears aesthetic, no
> anachronistic ornamentation for its own sake, no glowing energy effects.
> Muted, desaturated palette (browns, greys, faded reds/blues) consistent
> with a coal-smoke-choked post-apocalyptic setting. Character/vehicle
> silhouette must read clearly at small size — bold, simple shapes over
> fine detail. Transparent background, single subject, no ground shadow
> baked in (the game engine draws its own).

## Palette-by-role convention (for style consistency across all 18, not a hard rule)

Matches `TacticalEntityLayer`'s own existing role-marker colors, so real
art doesn't clash with the procedural fallback it's replacing:
- **Melee** — rust reds/browns, close-combat gear (truncheons, bayonets,
  claymores by Tier 3, then heavy ramming/crushing engineering by Tier 4-5).
- **Ranged** — blues/greys, firearms era-appropriate to tier (bow at Tier 0
  only, then muskets → rifles → sharpshooter gear → mounted/rail guns).
- **Special** — muted violets/purples, mobility or utility-flavored gear
  (scouting, grenades, cavalry, then heavy support vehicles).

## Tier progression (escalating sophistication, still grounded)

Tier 0-3 are individual soldiers in progressively more standardized/heavier
Victorian military dress (parish constable → navvy/labourer militia →
regular infantry redcoat → elite Highland regiment). **Tier 4-5 are heavy
steam-powered engineering, not humanoid mechs** — armoured traction
engines, rail-mounted guns, breaching cranes. This is a hard constraint
from the top of `todo.md` ("no retro-futuristic steampunk tropes... applies
even to the top-tier 'mechanized' units") and was explicitly checked again
when this roster was named (`todo.md` Phase 5.4) — a generated image that
reads as a walking robot is wrong regardless of how good it looks.

## The 18 prompts

Each below is a complete, standalone prompt (style guide already folded
in) — paste one at a time into an image-generation tool. `key` is the exact
filename this pipeline expects (`assets/units/<key>.png`).

### Tier 0 — "Free Ammo" starting tier, no tech needed

**`truncheoneer`** (Melee) — A Victorian parish constable/night-watchman in
a heavy wool coat and tall hat, gripping a wooden truncheon in a ready
stance. Worn leather boots, a lantern clipped to his belt. Rust-red/brown
tones. Grounded, unglamorous — this is the player's weakest starting unit.

**`toxophilite`** (Ranged) — A civilian archer in practical Victorian
outdoor dress (tweed, flat cap), drawing a traditional English longbow.
No firearm — this unit deliberately carries no ammunition belt or powder
horn (it never needs Gunpowder). Blue-grey tones, calm/steady posture.

**`outrider`** (Special) — A mounted scout on a sturdy horse, Victorian
riding coat and boots, a spyglass or dispatch satchel visible. Muted
violet/purple accent on the coat trim. Posture conveys speed/mobility,
not combat readiness.

### Tier 1

**`navvy`** (Melee) — A burly railway/canal labourer-turned-militiaman:
flat cap, rolled shirt sleeves, heavy braces, wielding a pickaxe or
sledgehammer as an improvised weapon. Rust-brown tones, working-class dress
— this is armed labour, not a soldier yet.

**`yeoman_marksman`** (Ranged) — A rural militia rifleman in practical
hunting/shooting attire (flat cap or wide-brim hat, canvas jacket),
carrying an early breech-loading rifle and a leather cartridge bandolier —
the first unit in the roster that actually depends on gunpowder. Blue-grey
tones.

**`grenadier`** (Special) — A militia grenadier in a simple dark tunic,
carrying a satchel of hand-thrown black-powder grenades and a slow-match
or friction igniter. Violet/purple accent. Stance suggests a lobbing throw.

### Tier 2

**`redcoat`** (Melee) — A proper British Army infantryman: red wool
tunic, white cross-belts, dark trousers, shako or pith helmet, fixed
bayonet on a standard-issue rifle held for a melee thrust. Iconic,
disciplined Victorian regular-infantry silhouette.

**`rifleman`** (Ranged) — A Rifle Regiment soldier in dark green tunic
(historically distinct from redcoats — "Rifles" wore green, not red),
peaked cap, aiming a rifle. Blue-grey/green tones, more polished
than the Yeoman Marksman.

**`chasseur`** (Special) — A light skirmish-cavalry-flavored infantryman
in a shorter tunic with braided frogging, a curved light sabre at the hip,
alert/agile stance. Violet accent, French-influenced light-infantry look
without being a different nationality's uniform — a colonial-irregular feel.

### Tier 3

**`highlander`** (Melee) — An elite Scottish Highland regiment soldier:
kilt, sporran, feather bonnet, tartan sash, wielding a claymore or fixed
bayonet. Proud, disciplined stance — visibly the best-equipped melee
soldier so far. Rust-red tones with tartan detail.

**`sharpshooter`** (Ranged) — A designated marksman in subdued
drab/khaki-tending dress (breaking from the brighter Tier 1-2 palette —
early camouflage-consciousness), a scoped or long-barrelled precision
rifle, kneeling or crouched aiming stance. Blue-grey tones.

**`dragoon`** (Special) — A mounted dragoon in a cavalry tunic and
plumed helmet, sabre drawn, on horseback. Violet accent, the last
individual-soldier-on-horse before the roster shifts to steam engineering
at Tier 4.

### Tier 4 — heavy steam engineering begins (grounded, NOT a mech)

**`steam_pram_rammer`** (Melee) — A squat, heavily armoured steam-powered
traction engine with a reinforced ramming prow at the front, riveted iron
plating, a coal-smoke stack. No legs, no humanoid silhouette — it moves on
wheels or tracks like a vehicle. Rust-brown/iron tones.

**`armored_locomotive_gunner`** (Ranged) — A small armoured rail-gun
platform: a stubby armoured locomotive/railcar mounting a single heavy
gun barrel, riveted plate, a small smoke stack. Reads clearly as a
vehicle on rails, not a person. Blue-grey/iron tones.

**`steam_tractor_landship`** (Special) — A boxy, heavily-plated steam
tractor/landship on wide iron wheels or a simple track, riveted armour
plate, a coal-smoke stack, no turret-mounted main gun (support/utility
role, not primary firepower). Violet-tinted iron tones.

### Tier 5 — the roster's heaviest engineering

**`steam_machine_leg`** (Melee) — **This name is the single highest risk
of reading as a mech — actively counteract that.** A heavy steam-powered
BREACHING/CRUSHING vehicle with articulated mechanical crushing arms or a
piston-driven ram (the "leg" is a piston/ram mechanism, not a walking
robot leg) mounted on a wheeled or tracked iron chassis. Must NOT have a
bipedal/humanoid silhouette, a "head", or read as a walking robot at any
scale. Heavy rust-iron tones, riveted plate, coal-smoke stack.

**`railway_siege_howitzer`** (Ranged) — A massive gun mounted on a
dedicated rail carriage/flatcar, long heavy barrel, riveted iron
armoured mount, coal-smoke stack. Reads unmistakably as siege artillery
on rails. Blue-grey/iron tones.

**`war_machine_armored_car`** (Special) — A large armoured car/traction
engine hybrid on wide iron wheels, riveted plate on all sides, a
command-post silhouette (radio/signal mast rather than a main gun — this
is the roster's heaviest support vehicle). Violet-tinted iron tones.

## Drop-in workflow

1. Generate (or otherwise obtain) `<key>.png` for however many of the 18
   `key`s above you have art for — partial coverage is fine, this pipeline
   was built specifically so art can land unit-by-unit (same
   `ResourceLoader.exists()`-gated-null contract as `TerrainVisuals`/
   `BuildingVisuals`, see `scripts/units/UnitVisuals.gd`).
2. Save each as `assets/units/<key>.png` (exact key strings above — see
   `UnitVisuals._texture_key()` for the authoritative mapping if this file
   and the code ever drift).
3. Run a Godot import pass so the engine picks it up:
   `Godot_v4.7.1-stable_win64_console.exe --headless --path . --import`
   (proven working in this project's environment — see `assets/buildings/`'s
   own `.import` files for reference `.import` file shape if authoring one
   by hand instead).
4. That's it — no code changes needed. `TacticalEntityLayer` picks up the
   new texture automatically at MEDIUM and HIGH Tactical fidelity the next
   time it redraws that unit type; LOW fidelity deliberately never uses
   per-unit art (see that class's own doc comment — LOW is a uniform
   category blob by design, not a missing-art gap).
