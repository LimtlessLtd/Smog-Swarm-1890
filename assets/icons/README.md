# Resource/HUD icon generation pipeline (user request) — AI-PROMPT APPROACH ABANDONED

**The AI-prompt approach below is abandoned, not just paused.** The user
explicitly chose Blender instead when asked to brainstorm an asset
pipeline — **"lets use blender only, no API AI Image gen needed"** — see
`tools/blender_pipeline/README.md`. `coal.png` is generated that way
(`tools/blender_pipeline/models/icons/coal.py` — the pipeline's first
proof-of-concept asset); the other 7 missing icons (population, clay,
limestone, iron_ore, sulfur, steel — 8 already existed pre-rework) haven't
had a Blender pass yet. Any future icon art should use that pipeline, not
the prompts below. Kept only as a historical record.

**Original status note, before the Blender pipeline existed:**
infrastructure built, images not yet generated. No tool in this
Claude Code environment can call an AI image generator — the 8 prompts
below and the code in `ResourceVisuals.gd`/`ResourceBarView.gd` are the
complete, ready-to-use pipeline; someone with real image-generation access
needs to run the prompts and drop the resulting PNGs into this folder.

Every `GameEnums.ResourceType` the top resource bar already shows as plain
text (`Food: 100/∞`, etc.) gets a small icon next to its label where one
exists — text-only stays the fallback for any resource with no icon yet,
same "art lands incrementally" contract as everywhere else in this
project. Partial coverage is fine — generate one or two and check them in
the actual HUD before doing all 8.

**A note on the "overhead/bird's-eye view" convention this whole art
pipeline otherwise follows:** these are small flat UI icons, not objects
rendered in the game world by a camera — a literal steep-downward angle
doesn't read well at icon size for something like a loaf of bread or a
bag of gunpowder (it mostly just looks like a blob from directly above).
Each prompt below instead asks for a **slightly-elevated 3/4 icon angle**,
which is the closest icon-scale equivalent to this game's own overhead
camera style without sacrificing legibility — flagged here explicitly
since it's a deliberate, reasoned departure from the literal instruction,
not an oversight.

Same conventions as `assets/units/README.md` otherwise — one
self-contained prompt per block, generate all 8 in the same session for
style consistency, flat white background with a thick black outline for
reliable keying, save as `assets/icons/<key>.png`.

## Style DNA (shared style repeated inside all 8 prompts — edit here first if it ever needs to change)

> Style: hand-painted / illustrated game icon art — clean, bold
> cartoon-baroque style with visible brushwork and flat painterly
> cel-shading, matching this project's unit/building/prop art. A single
> object or small object group representing the resource, Victorian
> 1890s Britain in materials and design.

> View: a slightly-elevated 3/4 icon angle — the closest icon-scale
> equivalent to this game's own overhead camera style, legible at very
> small size.

> Format: single icon subject, centered, small margin, bold clear
> silhouette readable at very small size (this renders as small as
> 20x20 pixels in the HUD), plain flat white (`#FFFFFF`) background,
> evenly lit with no shadow or gradient, a thick bold black outline
> around the whole subject. Square aspect ratio (1:1), PNG format.

## The 8 prompts

**`food.png`**
```
A styled icon to represent food. small stack of Victorian food staples — a loaf of bread and a wedge of cheese together. Style: hand-painted / illustrated game icon art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit/building/prop art. A single object or small object group representing the resource, Victorian 1890s Britain in materials and design. View: a slightly-elevated 3/4 icon angle — the closest icon-scale equivalent to this game's own overhead camera style, legible at very small size. Palette: warm golden bread-crust and pale cheese tones. Format: single icon subject, centered, small margin, bold clear silhouette readable at very small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`energy.png`**
```
A styled icon to represent energy. A small lump of coal beside a lit gas-lamp flame, representing coal/gas/oil power together. Style: hand-painted / illustrated game icon art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit/building/prop art. A single object or small object group representing the resource, Victorian 1890s Britain in materials and design. View: a slightly-elevated 3/4 icon angle — the closest icon-scale equivalent to this game's own overhead camera style, legible at very small size. Palette: black coal with a warm glowing amber flame accent. Format: single icon subject, centered, small margin, bold clear silhouette readable at very small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`gunpowder.png`**
```
A styled icon to represent gunpowder. A small cloth powder pouch, cinched at the top, with a few loose black powder grains beside it. Style: hand-painted / illustrated game icon art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit/building/prop art. A single object or small object group representing the resource, Victorian 1890s Britain in materials and design. View: a slightly-elevated 3/4 icon angle — the closest icon-scale equivalent to this game's own overhead camera style, legible at very small size. Palette: dark canvas pouch, black powder grains, a small warning-red drawstring accent. Format: single icon subject, centered, small margin, bold clear silhouette readable at very small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`research.png`**
```
A styled icon to represent research. An open leather-bound notebook and a brass magnifying glass resting on it, representing research and progress. Style: hand-painted / illustrated game icon art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit/building/prop art. A single object or small object group representing the resource, Victorian 1890s Britain in materials and design. View: a slightly-elevated 3/4 icon angle — the closest icon-scale equivalent to this game's own overhead camera style, legible at very small size. Palette: worn brown leather, pale paper, a polished brass accent on the magnifying glass. Format: single icon subject, centered, small margin, bold clear silhouette readable at very small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`wood.png`**
```
A styled icon to represent wood. A small bundle of rough-cut timber logs, tied together. Style: hand-painted / illustrated game icon art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit/building/prop art. A single object or small object group representing the resource, Victorian 1890s Britain in materials and design. View: a slightly-elevated 3/4 icon angle — the closest icon-scale equivalent to this game's own overhead camera style, legible at very small size. Palette: warm honey-brown timber tones. Format: single icon subject, centered, small margin, bold clear silhouette readable at very small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`bricks.png`**
```
A styled icon to represent bricks. A small stack of red clay bricks. Style: hand-painted / illustrated game icon art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit/building/prop art. A single object or small object group representing the resource, Victorian 1890s Britain in materials and design. View: a slightly-elevated 3/4 icon angle — the closest icon-scale equivalent to this game's own overhead camera style, legible at very small size. Palette: warm terracotta brick-red tones. Format: single icon subject, centered, small margin, bold clear silhouette readable at very small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`cast_iron.png`**
```
A styled icon to represent cast iron. A small stack of cast iron ingots, dark and faintly riveted-looking. Style: hand-painted / illustrated game icon art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit/building/prop art. A single object or small object group representing the resource, Victorian 1890s Britain in materials and design. View: a slightly-elevated 3/4 icon angle — the closest icon-scale equivalent to this game's own overhead camera style, legible at very small size. Palette: dark iron grey with a faint warm rust-orange accent along the edges. Format: single icon subject, centered, small margin, bold clear silhouette readable at very small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`concrete.png`**
```
A styled icon to represent concrete. A small pale grey concrete block/slab, faintly textured. Style: hand-painted / illustrated game icon art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit/building/prop art. A single object or small object group representing the resource, Victorian 1890s Britain in materials and design. View: a slightly-elevated 3/4 icon angle — the closest icon-scale equivalent to this game's own overhead camera style, legible at very small size. Palette: pale neutral grey concrete tones. Format: single icon subject, centered, small margin, bold clear silhouette readable at very small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

## Drop-in workflow

Generate, key out the white background, save as `assets/icons/<key>.png`
(exact keys shown above each prompt — see `ResourceVisuals._icon_key()` if
this file and the code ever drift), run the standard `--headless --import`
pass, done. No further code changes needed — `ResourceBarView` picks up
whichever icons exist the next time the game boots.
