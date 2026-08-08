# Unit art generation pipeline (Phase 6.3.1/6.3.2)

**Status: infrastructure built, images not yet generated.** No tool in this
Claude Code environment can call an AI image generator — the 18 prompts
below and the code in `UnitVisuals.gd`/`TacticalEntityLayer.gd` are the
complete, ready-to-use pipeline; someone with access to an actual
image-generation tool (a future session, or the user directly) needs to
run the prompts and drop the resulting PNGs into this folder. Nothing else
changes when that happens — see "Drop-in workflow" below.

This is deliberately a *different* path from terrain (`assets/terrain/`)
and buildings (`assets/buildings/`), both of which ended up hand-authored
SVG instead of AI-generated (see `todo.md` Phase 6.3.0/6.3.0b) — the user
explicitly chose AI generation for units when asked, so this exists
instead of 18 more hand-drawn SVGs.

## How to use this

Each block under "The 18 prompts" below is **one complete, self-contained
string** — copy it exactly as-is (use the copy button / select the whole
fenced block) and paste it straight into an image-generation tool. Nothing
needs to be added or combined by hand: the style guide, palette
convention, and technical requirements (square, transparent, PNG) are
already baked into every single one.

Generate all 18 in the *same* conversation/session with your image tool,
not 18 separate fresh chats — persistent context is what keeps them
reading as one game's art instead of 18 different styles. If your tool
supports a style-reference/seed mechanism (e.g. Midjourney's `--sref`),
lock it in after the first successful generation and reuse it for the rest.

**If your tool can't produce a transparent background** (not all can, even
when asked): ask for a plain flat solid-color background instead, then run
the result through a free background remover (e.g. remove.bg) before
saving. Everything else about the prompt stays the same.

Save each result as `assets/units/<key>.png` using the exact filename
shown above each prompt below (`_texture_key()` in `UnitVisuals.gd` is the
authoritative mapping if this file and the code ever drift). Partial
coverage is fine — each unit falls back to its old procedural shape
individually until its own file exists, so you can drop in a few now and
the rest later.

## Style DNA (already baked into every prompt below — kept here only as a single source of truth if the shared style ever needs editing)

Editing this section does NOT change the prompts below — since each one is
meant to be copied standalone, the same style/format text is repeated
inside all 18. If the shared style changes, update it here first to get
the wording right, then find-and-replace it across the 18 blocks.

> Style: grounded, late-19th-century Industrial Revolution aesthetic set
> in 1890s Britain — authentic Victorian military/civilian dress and
> equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT
> retro-futuristic steampunk: no goggles-and-gears aesthetic, no
> anachronistic ornamentation, no glowing energy effects. Muted,
> desaturated color palette (browns, greys, faded reds/blues) fitting a
> coal-smoke-choked post-apocalyptic setting.

> Format: Single subject only, centered in frame with a small margin,
> front-facing or slight 3/4 angle, bold simple silhouette that reads
> clearly at small size, no other characters, no background scenery or
> props, no text, no watermark, no signature. Square aspect ratio (1:1),
> fully transparent background, PNG format.

Role-palette convention (matches `TacticalEntityLayer`'s existing
procedural marker colors, so real art won't clash with the fallback it
replaces): **Melee** = rust reds/browns. **Ranged** = blues/greys.
**Special** = muted violets/purples.

Tier progression: Tier 0-3 are individual soldiers in progressively more
standardized/heavier Victorian military dress. **Tier 4-5 are heavy
steam-powered engineering, not humanoid mechs** — a hard constraint from
the top of `todo.md` ("no retro-futuristic steampunk tropes... applies
even to the top-tier 'mechanized' units"), which is why every Tier 4-5
prompt below repeats an explicit anti-mech instruction rather than trusting
the general style guide alone to prevent it.

## The 18 prompts

### Tier 0 — "Free Ammo" starting tier, no tech needed

**`truncheoneer.png`** (Melee)
```
A Victorian parish constable/night-watchman: heavy wool coat, tall hat, gripping a wooden truncheon in a ready stance, worn leather boots, a lantern clipped to his belt. Unglamorous and grounded — the weakest starting soldier in a defense force. Role palette: rust reds and browns. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

**`toxophilite.png`** (Ranged)
```
A civilian archer in practical Victorian outdoor dress (tweed jacket, flat cap), drawing a traditional English longbow. No firearm, no ammunition belt or powder horn — a calm, steady aiming stance. Role palette: blues and greys. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

**`outrider.png`** (Special)
```
A mounted scout on a sturdy horse, wearing a Victorian riding coat and boots, a spyglass or dispatch satchel visible. Posture conveys speed and mobility, not combat readiness. Role palette: muted violets and purples. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

### Tier 1

**`navvy.png`** (Melee)
```
A burly railway/canal labourer turned militiaman: flat cap, rolled shirt sleeves, heavy braces, wielding a pickaxe or sledgehammer as an improvised weapon. Working-class dress — this is armed labour, not a trained soldier yet. Role palette: rust reds and browns. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

**`yeoman_marksman.png`** (Ranged)
```
A rural militia rifleman in practical hunting/shooting attire (flat cap or wide-brim hat, canvas jacket), carrying an early breech-loading rifle and a leather cartridge bandolier, in an aiming stance — the first unit in this roster to actually depend on gunpowder. Role palette: blues and greys. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

**`grenadier.png`** (Special)
```
A militia grenadier in a simple dark tunic, carrying a satchel of hand-thrown black-powder grenades and a slow-match or friction igniter, stance suggesting a lobbing throw. Role palette: muted violets and purples. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

### Tier 2

**`redcoat.png`** (Melee)
```
A British Army infantryman in full dress: red wool tunic, white cross-belts, dark trousers, a shako or pith helmet, fixed bayonet on a rifle held for a melee thrust. A disciplined, iconic Victorian regular-infantry stance. Role palette: rust reds and browns. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

**`rifleman.png`** (Ranged)
```
A Rifle Regiment soldier in a dark green tunic (historically distinct from a redcoat's red), peaked cap, aiming a rifle. More polished and uniform than a rural militia marksman. Role palette: blues and greys. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

**`chasseur.png`** (Special)
```
A light skirmish-infantryman in a short tunic with braided frogging, a curved light sabre at the hip, an alert and agile stance — a colonial-irregular feel without being a different nation's uniform. Role palette: muted violets and purples. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

### Tier 3

**`highlander.png`** (Melee)
```
An elite Scottish Highland regiment soldier: kilt, sporran, feather bonnet, tartan sash, wielding a claymore or a fixed bayonet. A proud, disciplined stance — visibly the best-equipped individual soldier in the roster. Role palette: rust reds and browns, with tartan detail. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

**`sharpshooter.png`** (Ranged)
```
A designated marksman in subdued drab/khaki dress, breaking from the brighter dress of lower-tier units, carrying a scoped or long-barrelled precision rifle, kneeling or crouched in an aiming stance. Role palette: blues and greys. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

**`dragoon.png`** (Special)
```
A mounted dragoon in a cavalry tunic and plumed helmet, sabre drawn, on horseback — the last individual soldier-on-horse before this roster shifts entirely to steam-powered vehicles at the next tier. Role palette: muted violets and purples. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

### Tier 4 — heavy steam engineering begins (grounded, NOT a mech)

**`steam_pram_rammer.png`** (Melee)
```
A squat, heavily armoured steam-powered traction engine with a reinforced ramming prow at the front, riveted iron plating, a coal-smoke stack, moving on wheels or tracks — no legs, no humanoid silhouette, this reads clearly as a vehicle, not a person. Role palette: rust reds and browns, heavy iron tones. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

**`armored_locomotive_gunner.png`** (Ranged)
```
A small armoured rail-gun platform: a stubby armoured locomotive or railcar mounting a single heavy gun barrel, riveted plate, a small smoke stack — reads clearly as a vehicle on rails, not a person. Role palette: blues and greys, heavy iron tones. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

**`steam_tractor_landship.png`** (Special)
```
A boxy, heavily-plated steam tractor/landship on wide iron wheels or a simple track, riveted armour plate, a coal-smoke stack, no turret-mounted main gun — a support/utility vehicle, not primary firepower. No legs, no humanoid silhouette. Role palette: muted violets and purples, heavy iron tones. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

### Tier 5 — the roster's heaviest engineering

**`steam_machine_leg.png`** (Melee) — **this name is the single highest risk of reading as a mech in this whole roster; the prompt below leans on that harder than any other**
```
A heavy steam-powered breaching/crushing vehicle: articulated mechanical crushing arms or a piston-driven ram mounted on a wheeled or tracked iron chassis — the "leg" in its name refers to a piston/ram mechanism, NOT a walking robot leg. This must NOT have a bipedal or humanoid silhouette, must NOT have a "head", and must NOT read as a walking robot or mech at any scale — it is a heavy vehicle on wheels or tracks, full stop. Heavy rust-iron tones, riveted plate, a coal-smoke stack. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

**`railway_siege_howitzer.png`** (Ranged)
```
A massive gun mounted on a dedicated rail carriage/flatcar, a long heavy barrel, a riveted iron armoured mount, a coal-smoke stack — unmistakably siege artillery on rails, not a person or a mech. Role palette: blues and greys, heavy iron tones. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

**`war_machine_armored_car.png`** (Special)
```
A large armoured car/traction-engine hybrid on wide iron wheels, riveted plate on all sides, a radio or signal mast rather than a main gun — the roster's heaviest support vehicle, reading as a mobile command post. No legs, no humanoid silhouette. Role palette: muted violets and purples, heavy iron tones. Style: grounded, late-19th-century Industrial Revolution aesthetic set in 1890s Britain — authentic Victorian military/civilian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. Muted, desaturated color palette (browns, greys, faded reds/blues) fitting a coal-smoke-choked post-apocalyptic setting. Single subject only, centered in frame with a small margin, front-facing or slight 3/4 angle, bold simple silhouette that reads clearly at small size, no other characters, no background scenery or props, no text, no watermark, no signature. Square aspect ratio (1:1), fully transparent background, PNG format.
```

## Drop-in workflow

1. Generate (or otherwise obtain) `<key>.png` for however many of the 18
   `key`s above you have art for — partial coverage is fine, this pipeline
   was built specifically so art can land unit-by-unit (same
   `ResourceLoader.exists()`-gated-null contract as `TerrainVisuals`/
   `BuildingVisuals`, see `scripts/units/UnitVisuals.gd`).
2. Save each as `assets/units/<key>.png` (exact filenames shown above each
   prompt — see `UnitVisuals._texture_key()` for the authoritative mapping
   if this file and the code ever drift).
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
