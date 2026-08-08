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

**Revised three times now** based on direct user feedback/hands-on editing
of earlier drafts of these prompts:
- **Round 1:** most image generators can't actually produce a transparent
  background despite being asked — background removal is a required step,
  not a fallback; the original prompts never named an art style, just what
  to avoid, risking photorealistic drift; and a shared muted role palette
  across all 18 units risked every unit of the same role collapsing into
  one indistinguishable brown blob.
- **Round 2:** background color settled on flat solid black (over
  chroma-key green — both were considered); art style specified further as
  **clean, simple, cartoon-baroque** (not just "painterly"); added an
  explicit **isometric, slightly top-down overhead view** requirement,
  since that's how a unit is actually seen through this game's real
  camera — the original prompts never specified a camera angle at all; and
  **full body** called out explicitly so nothing gets cropped.
- **Round 3:** background switched from black to **flat solid white with a
  thick bold black outline/border around every subject** — a simpler,
  more robust keying technique (a black outline against a white field is
  unambiguous regardless of the subject's own internal colors, unlike a
  black background risking blending with this roster's own dark tones)
  that also reinforces the cartoon-baroque style rather than fighting it —
  comic-book-style linework is exactly what "cartoon" already implies.

## How to use this

Each block under "The 18 prompts" below is **one complete, self-contained
string** — copy it exactly as-is (use the copy button / select the whole
fenced block) and paste it straight into an image-generation tool. Nothing
needs to be added or combined by hand.

**Important: each prompt only names its OWN unit's role accent color** —
a Melee unit's prompt mentions rust-red only, never blue or purple, and
so on. Don't add the other two roles' colors in when copying one over;
mixing them in a single generation risks the model blending all three
into one muddy result instead of a single clear accent.

Generate all 18 in the *same* conversation/session with your image tool,
not 18 separate fresh chats — persistent context is what keeps them
reading as one game's art instead of 18 different styles. If your tool
supports a style-reference/seed mechanism (e.g. Midjourney's `--sref`),
lock it in after the first successful generation and reuse it for the rest.

**Background removal is a required step, not optional.** Every prompt
below asks for a flat solid white (`#FFFFFF`) background with a thick
bold black outline around the subject — the outline is what makes clean
keying reliable regardless of the subject's own internal colors (a
background-removal tool, or a simple "select the white, delete it" pass
in any image editor, both work fine against a bold black-outlined
subject). Re-export the keyed result as a PNG with alpha transparency
before saving it into this folder.

Save each result as `assets/units/<key>.png` using the exact filename
shown above each prompt below (`_texture_key()` in `UnitVisuals.gd` is the
authoritative mapping if this file and the code ever drift). Partial
coverage is fine — each unit falls back to its old procedural shape
individually until its own file exists, so you can drop in a few now and
the rest later. **Suggested first step given this is a three-times-revised
prompt template: generate just one or two and check the results (style,
angle, palette separation, background keys out cleanly) before running
all 18.**

## Style DNA (already baked into every prompt below — kept here only as a single source of truth if the shared style ever needs editing)

Editing this section does NOT change the prompts below — since each one is
meant to be copied standalone, the same style/format text is repeated
inside all 18. If the shared style changes, update it here first to get
the wording right, then find-and-replace it across the 18 blocks.

> Style: hand-painted / illustrated game character art, clean and simple
> with a touch of ornate cartoon-baroque flourish — bold clear shapes,
> visible brushwork or flat painterly shading. NOT a photograph, NOT
> photorealistic, NOT a 3D render or CG model. Grounded late-19th-century
> Industrial Revolution setting, 1890s Britain — authentic Victorian dress
> and equipment (wool, leather, brass, cast iron, coal soot). Explicitly
> NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no
> anachronistic ornamentation, no glowing energy effects.

> View: isometric, slightly top-down overhead angle — as seen from this
> game's actual top-down/isometric camera, NOT a flat front-on portrait.

> Format: Single subject, full body shown (nothing cropped off), centered,
> small margin. Bold clear silhouette readable at small size. No other
> characters, no background scenery or props, no text, no watermark, no
> signature. Every subject drawn with a thick, bold black outline/border
> around its silhouette (comic-book/cel-shaded linework), on a flat solid
> white (`#FFFFFF`) background — one uniform shade throughout, no
> gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG
> format.

Role-accent convention (matches `TacticalEntityLayer`'s existing
procedural marker colors, so real art won't clash with the fallback it
replaces) — **reference only, a single individual prompt only ever
includes its OWN row below, never more than one**:
- **Melee** — vivid, saturated rust-red accent.
- **Ranged** — vivid, saturated cobalt-blue accent.
- **Special** — vivid, saturated violet-purple accent.

The base uniform/materials (wool, leather, iron) stay grounded and
weathered regardless of role — only the accent (sash, trim, cap band,
weapon, insignia) carries the role color, and it must read as a clearly
visible, saturated pop against the grounded base, not a muted wash over
the whole figure. This is what keeps 18 units from collapsing into one
indistinguishable palette once the base is desaturated.

Every prompt also carries a differentiation instruction — same role,
different tier, must still look like a different unit (varied silhouette/
headgear/equipment sophistication), not the same figure recolored.

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
A Victorian parish constable/night-watchman: heavy wool coat, tall hat, gripping a wooden truncheon in a ready stance, worn leather boots, a lantern clipped to his belt. Unglamorous and grounded — the weakest starting soldier in a defense force. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base uniform/materials stay grounded and weathered (greys, browns, khaki, faded olive), with a vivid, saturated rust-red accent (sash, trim, cap band, weapon, insignia) clearly visible — not a muted wash over the whole figure. This unit must look visually distinct from other units of the same role at a glance — vary silhouette, headgear, and equipment sophistication rather than reusing the same figure with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

**`toxophilite.png`** (Ranged)
```
A civilian archer in practical Victorian outdoor dress (tweed jacket, flat cap), drawing a traditional English longbow. No firearm, no ammunition belt or powder horn — a calm, steady aiming stance. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base uniform/materials stay grounded and weathered (greys, browns, khaki, faded olive), with a vivid, saturated cobalt-blue accent (sash, trim, cap band, weapon, insignia) clearly visible — not a muted wash over the whole figure. This unit must look visually distinct from other units of the same role at a glance — vary silhouette, headgear, and equipment sophistication rather than reusing the same figure with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

**`outrider.png`** (Special)
```
A mounted scout on a sturdy horse, wearing a Victorian riding coat and boots, a spyglass or dispatch satchel visible. Posture conveys speed and mobility, not combat readiness. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base uniform/materials stay grounded and weathered (greys, browns, khaki, faded olive), with a vivid, saturated violet-purple accent (sash, trim, cap band, weapon, insignia) clearly visible — not a muted wash over the whole figure. This unit must look visually distinct from other units of the same role at a glance — vary silhouette, headgear, and equipment sophistication rather than reusing the same figure with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

### Tier 1

**`navvy.png`** (Melee)
```
A burly railway/canal labourer turned militiaman: flat cap, rolled shirt sleeves, heavy braces, wielding a pickaxe or sledgehammer as an improvised weapon. Working-class dress — this is armed labour, not a trained soldier yet. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base uniform/materials stay grounded and weathered (greys, browns, khaki, faded olive), with a vivid, saturated rust-red accent (sash, trim, cap band, weapon, insignia) clearly visible — not a muted wash over the whole figure. This unit must look visually distinct from other units of the same role at a glance — vary silhouette, headgear, and equipment sophistication rather than reusing the same figure with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

**`yeoman_marksman.png`** (Ranged)
```
A rural militia rifleman in practical hunting/shooting attire (flat cap or wide-brim hat, canvas jacket), carrying an early breech-loading rifle and a leather cartridge bandolier, in an aiming stance — the first unit in this roster to actually depend on gunpowder. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base uniform/materials stay grounded and weathered (greys, browns, khaki, faded olive), with a vivid, saturated cobalt-blue accent (sash, trim, cap band, weapon, insignia) clearly visible — not a muted wash over the whole figure. This unit must look visually distinct from other units of the same role at a glance — vary silhouette, headgear, and equipment sophistication rather than reusing the same figure with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

**`grenadier.png`** (Special)
```
A militia grenadier in a simple dark tunic, carrying a satchel of hand-thrown black-powder grenades and a slow-match or friction igniter, stance suggesting a lobbing throw. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base uniform/materials stay grounded and weathered (greys, browns, khaki, faded olive), with a vivid, saturated violet-purple accent (sash, trim, cap band, weapon, insignia) clearly visible — not a muted wash over the whole figure. This unit must look visually distinct from other units of the same role at a glance — vary silhouette, headgear, and equipment sophistication rather than reusing the same figure with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

### Tier 2

**`redcoat.png`** (Melee)
```
A British Army infantryman in full dress: red wool tunic, white cross-belts, dark trousers, a shako or pith helmet, fixed bayonet on a rifle held for a melee thrust. A disciplined, iconic Victorian regular-infantry stance. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: this unit's tunic is itself already red by historical uniform — treat that as the base, and let the vivid, saturated rust-red role accent show as brighter/richer red trim, piping, and insignia standing out clearly against it, not a second competing color; other materials (belts, trousers, helmet) stay grounded and weathered. This unit must look visually distinct from other units of the same role at a glance — vary silhouette, headgear, and equipment sophistication rather than reusing the same figure with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

**`rifleman.png`** (Ranged)
```
A Rifle Regiment soldier in a dark green tunic (historically distinct from a redcoat's red), peaked cap, aiming a rifle. More polished and uniform than a rural militia marksman. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: the dark green tunic is the historically-accurate base — with a vivid, saturated cobalt-blue accent (sash, trim, cap band, weapon, insignia) clearly visible against it, not a muted wash over the whole figure. This unit must look visually distinct from other units of the same role at a glance — vary silhouette, headgear, and equipment sophistication rather than reusing the same figure with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

**`chasseur.png`** (Special)
```
A light skirmish-infantryman in a short tunic with braided frogging, a curved light sabre at the hip, an alert and agile stance — a colonial-irregular feel without being a different nation's uniform. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base uniform/materials stay grounded and weathered (greys, browns, khaki, faded olive), with a vivid, saturated violet-purple accent (sash, trim, cap band, weapon, insignia) clearly visible — not a muted wash over the whole figure. This unit must look visually distinct from other units of the same role at a glance — vary silhouette, headgear, and equipment sophistication rather than reusing the same figure with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

### Tier 3

**`highlander.png`** (Melee)
```
An elite Scottish Highland regiment soldier: kilt, sporran, feather bonnet, tartan sash, wielding a claymore or a fixed bayonet. A proud, disciplined stance — visibly the best-equipped individual soldier in the roster. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base uniform/materials stay grounded and weathered (greys, browns, khaki, faded olive), with a vivid, saturated rust-red accent carried in the tartan/sash pattern, clearly visible — not a muted wash over the whole figure. This unit must look visually distinct from other units of the same role at a glance — vary silhouette, headgear, and equipment sophistication rather than reusing the same figure with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

**`sharpshooter.png`** (Ranged)
```
A designated marksman in subdued drab/khaki dress, breaking from the brighter dress of lower-tier units, carrying a scoped or long-barrelled precision rifle, kneeling or crouched in an aiming stance. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base uniform/materials stay grounded and weathered (greys, browns, khaki, faded olive), with a vivid, saturated cobalt-blue accent (sash, trim, cap band, weapon, insignia) clearly visible — not a muted wash over the whole figure. This unit must look visually distinct from other units of the same role at a glance — vary silhouette, headgear, and equipment sophistication rather than reusing the same figure with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

**`dragoon.png`** (Special)
```
A mounted dragoon in a cavalry tunic and plumed helmet, sabre drawn, on horseback — the last individual soldier-on-horse before this roster shifts entirely to steam-powered vehicles at the next tier. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian dress and equipment (wool, leather, brass, cast iron, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base uniform/materials stay grounded and weathered (greys, browns, khaki, faded olive), with a vivid, saturated violet-purple accent (sash, trim, cap band, weapon, insignia) clearly visible — not a muted wash over the whole figure. This unit must look visually distinct from other units of the same role at a glance — vary silhouette, headgear, and equipment sophistication rather than reusing the same figure with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

### Tier 4 — heavy steam engineering begins (grounded, NOT a mech)

**`steam_pram_rammer.png`** (Melee)
```
A squat, heavily armoured steam-powered traction engine with a reinforced ramming prow at the front, riveted iron plating, a coal-smoke stack, moving on wheels or tracks — no legs, no humanoid silhouette, this reads clearly as a vehicle, not a person. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian engineering (iron, rivets, brass, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base plating/materials stay grounded and weathered iron/rust tones, with a vivid, saturated rust-red accent (a painted panel, warning stripe, or trim band) clearly visible — not a muted wash over the whole vehicle. This vehicle must look visually distinct from other vehicles of the same role at a glance — vary silhouette and equipment sophistication rather than reusing the same shape with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

**`armored_locomotive_gunner.png`** (Ranged)
```
A small armoured rail-gun platform: a stubby armoured locomotive or railcar mounting a single heavy gun barrel, riveted plate, a small smoke stack — reads clearly as a vehicle on rails, not a person. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian engineering (iron, rivets, brass, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base plating/materials stay grounded and weathered iron/rust tones, with a vivid, saturated cobalt-blue accent (a painted panel, warning stripe, or trim band) clearly visible — not a muted wash over the whole vehicle. This vehicle must look visually distinct from other vehicles of the same role at a glance — vary silhouette and equipment sophistication rather than reusing the same shape with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

**`steam_tractor_landship.png`** (Special)
```
A boxy, heavily-plated steam tractor/landship on wide iron wheels or a simple track, riveted armour plate, a coal-smoke stack, no turret-mounted main gun — a support/utility vehicle, not primary firepower. No legs, no humanoid silhouette. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian engineering (iron, rivets, brass, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base plating/materials stay grounded and weathered iron/rust tones, with a vivid, saturated violet-purple accent (a painted panel, warning stripe, or trim band) clearly visible — not a muted wash over the whole vehicle. This vehicle must look visually distinct from other vehicles of the same role at a glance — vary silhouette and equipment sophistication rather than reusing the same shape with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

### Tier 5 — the roster's heaviest engineering

**`steam_machine_leg.png`** (Melee) — **this name is the single highest risk of reading as a mech in this whole roster; the prompt below leans on that harder than any other**
```
A heavy steam-powered breaching/crushing vehicle: articulated mechanical crushing arms or a piston-driven ram mounted on a wheeled or tracked iron chassis — the "leg" in its name refers to a piston/ram mechanism, NOT a walking robot leg. This must NOT have a bipedal or humanoid silhouette, must NOT have a "head", and must NOT read as a walking robot or mech at any scale — it is a heavy vehicle on wheels or tracks, full stop. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian engineering (iron, rivets, brass, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base plating/materials stay grounded and weathered heavy iron/rust tones, with a vivid, saturated rust-red accent (a painted panel, warning stripe, or trim band) clearly visible — not a muted wash over the whole vehicle. This vehicle must look visually distinct from other vehicles of the same role at a glance — vary silhouette and equipment sophistication rather than reusing the same shape with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

**`railway_siege_howitzer.png`** (Ranged)
```
A massive gun mounted on a dedicated rail carriage/flatcar, a long heavy barrel, a riveted iron armoured mount, a coal-smoke stack — unmistakably siege artillery on rails, not a person or a mech. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian engineering (iron, rivets, brass, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base plating/materials stay grounded and weathered heavy iron/rust tones, with a vivid, saturated cobalt-blue accent (a painted panel, warning stripe, or trim band) clearly visible — not a muted wash over the whole vehicle. This vehicle must look visually distinct from other vehicles of the same role at a glance — vary silhouette and equipment sophistication rather than reusing the same shape with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

**`war_machine_armored_car.png`** (Special)
```
A large armoured car/traction-engine hybrid on wide iron wheels, riveted plate on all sides, a radio or signal mast rather than a main gun — the roster's heaviest support vehicle, reading as a mobile command post. No legs, no humanoid silhouette. Style: hand-painted / illustrated game character art, clean and simple with a touch of ornate cartoon-baroque flourish — bold clear shapes, visible brushwork or flat painterly shading. NOT a photograph, NOT photorealistic, NOT a 3D render or CG model. Grounded late-19th-century Industrial Revolution setting, 1890s Britain — authentic Victorian engineering (iron, rivets, brass, coal soot). Explicitly NOT retro-futuristic steampunk: no goggles-and-gears aesthetic, no anachronistic ornamentation, no glowing energy effects. View: isometric, slightly top-down overhead angle — as seen from a top-down/isometric game camera, NOT a flat front-on portrait. Palette: base plating/materials stay grounded and weathered heavy iron/rust tones, with a vivid, saturated violet-purple accent (a painted panel, warning stripe, or trim band) clearly visible — not a muted wash over the whole vehicle. This vehicle must look visually distinct from other vehicles of the same role at a glance — vary silhouette and equipment sophistication rather than reusing the same shape with a different accent color. Format: single subject, full body shown (nothing cropped off), centered, small margin. Bold clear silhouette readable at small size. No other characters, no background scenery or props, no text, no watermark, no signature. Every subject drawn with a thick, bold black outline/border around its silhouette (comic-book/cel-shaded linework), on a flat solid white (#FFFFFF) background — one uniform shade throughout, no gradient, no vignette, no cast shadow. Square aspect ratio (1:1), PNG format.
```

## Drop-in workflow

1. Generate `<key>.png` for however many of the 18 `key`s above you have
   art for — partial coverage is fine, this pipeline was built specifically
   so art can land unit-by-unit (same `ResourceLoader.exists()`-gated-null
   contract as `TerrainVisuals`/`BuildingVisuals`, see
   `scripts/units/UnitVisuals.gd`).
2. Key out the flat white background and export as a PNG with real alpha
   transparency (a background-removal tool, or a plain "select the white,
   delete it" pass in any image editor — the thick black outline is what
   keeps this reliable even with a simple flood-select approach).
3. Save each as `assets/units/<key>.png` (exact filenames shown above each
   prompt — see `UnitVisuals._texture_key()` for the authoritative mapping
   if this file and the code ever drift).
4. Run a Godot import pass so the engine picks it up:
   `Godot_v4.7.1-stable_win64_console.exe --headless --path . --import`
   (proven working in this project's environment — see `assets/buildings/`'s
   own `.import` files for reference `.import` file shape if authoring one
   by hand instead).
5. That's it — no code changes needed. `TacticalEntityLayer` picks up the
   new texture automatically at MEDIUM and HIGH Tactical fidelity the next
   time it redraws that unit type; LOW fidelity deliberately never uses
   per-unit art (see that class's own doc comment — LOW is a uniform
   category blob by design, not a missing-art gap).
