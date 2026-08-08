# Building art generation pipeline (user request)

**Status: infrastructure built, images not yet generated.** No tool in this
Claude Code environment can call an AI image generator — the 18 prompts
below and the `BuildingVisuals.gd` PNG-first fallback are the complete,
ready-to-use pipeline; someone with real image-generation access needs to
run the prompts and drop the resulting PNGs into this folder.

**This is additive, not a replacement.** Every building already has a real
hand-drawn SVG (`todo.md` Phase 6.3.0b) and every one of those keeps
rendering exactly as it does today. `BuildingVisuals._load_texture()` now
checks for a `.png` at this folder's own `<key>.png` FIRST, and only falls
back to the existing `.svg` if no PNG exists — so art can land building by
building, same "art lands incrementally, zero code changes" contract every
other asset category in this project already follows. The reason to
generate these at all: **user feedback that the existing hand-drawn
buildings aren't distinctive enough from each other, in color and in
design** — every prompt below was written specifically to fix that: no two
buildings in the same category share an accent color, and each has a real,
distinct silhouette detail called out by name (see "Distinctiveness"
below).

Same conventions as `assets/units/README.md` (read that file's own "How to
use this"/"Background removal" sections if this is the first pipeline
you're running) — one self-contained prompt per block, generate all 18 in
one session/conversation for style consistency, flat white background with
a thick black outline for reliable keying, save as `assets/buildings/<key>.png`.

## Distinctiveness (why every prompt below reads differently even within one category)

`BuildingCategory` groups buildings by economic function (Housing & Civil,
Industry & Extraction, Agriculture) and the game's own `category_color()`
fallback already tints each category a single flat hue — real art needs to
do better than that or two buildings in the same category will keep
reading as "the same brown building" even with real detail. Every prompt
below assigns:
1. A **base material** appropriate to the building's real function (raw
   clay for a brickworks, pale limestone for a church, sandbags for a
   military dump) — not just its category's generic palette.
2. One **named accent color**, unique among its own category's other
   buildings (listed together below so it's easy to check nothing repeats).
3. One **distinctive silhouette detail** specific to that building alone
   (twin towers, a winding-gear headframe, a lattice mast) — the same
   "shape carries the read, not just color" accessibility principle this
   project's own marker/UI systems already follow throughout.

- **Housing & Civil:** Terraced Tenement (warm brick red), Workhouse
  (sickly institutional green), Church Steeple Watchtower (aged
  bronze/verdigris), Gas Streetlamp (warm gaslight amber), Telegraph Relay
  Office (copper/brass), Steam Printing Press (deep ink burgundy), Town
  Hall (civic navy blue), Garrison (martial rust-red).
- **Industry & Extraction:** Timber Camp (fresh sap green), Clay Brickworks (muddy ochre), Charcoal Kiln
  (smoldering ember orange), Coal Pithead (warning yellow), Cast Iron
  Foundry (molten furnace orange-red), Saltpetre & Powder Mill (hazard
  red), Forward Ammo Dump (khaki-green).
- **Agriculture:** Tenant Farm (warm wheat gold), Grain Silo (pale
  harvest gold), Cattle Yard (earthy pasture green).
- **Defense Works:** Searchlight Tower (bright white-blue beam) — the only
  building in its own category, no clash to avoid.

## Style DNA (shared style repeated inside all 18 prompts — edit here first if it ever needs to change)

> Style: hand-painted / illustrated game asset art — clean, bold
> cartoon-baroque style with visible brushwork and flat painterly
> cel-shading, matching this project's unit and prop art. Britain, 1890s,
> in the grip of a zombie plague — a defended, weathered outpost building,
> not a pristine museum piece: soot, patched repairs, a few boarded or
> reinforced details.

> View: bird's-eye/overhead — seen from above at a steep downward
> strategy-game camera angle, roof and frontage both readable at once.

> Format: single building, isolated, centered, small margin, bold clear
> silhouette readable at small size, plain flat white (`#FFFFFF`)
> background, evenly lit with no shadow or gradient, a thick bold black
> outline around the whole building. Square aspect ratio (1:1), PNG format.

## The 18 prompts

### Housing & Civil

**`terraced_tenement.png`**
```
A row of cramped Victorian terraced housing under one shared roofline — narrow brick frontages, small windows, a few washing lines strung between chimneys. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, roof and frontage both readable at once. Palette: warm red brick as the base material, with a deeper warm brick-red accent in the roof tiles/trim — distinct from every other Housing & Civil building's own accent color. Distinctive silhouette detail: a long unbroken row of matching chimney stacks along the roof ridge. Format: single building, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole building. Square aspect ratio (1:1), PNG format.
```

**`workhouse.png`**
```
A grim, institutional Victorian workhouse — plain heavy stone walls, small barred windows in even rows, an imposing rectangular block. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, roof and frontage both readable at once. Palette: grey stone as the base material, with a sickly institutional-green accent on window frames/doors — distinct from every other Housing & Civil building's own accent color. Distinctive silhouette detail: a tall narrow central bell-cupola on the roof ridge. Format: single building, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole building. Square aspect ratio (1:1), PNG format.
```

**`watchtower.png`**
```
A reinforced lookout watchtower — a wooden watchtower building with rail built onto the upper level, a ladder stretches up from far below as it is tall. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, roof and frontage both readable at once. Palette: pale limestone as the base material, with an aged bronze/verdigris accent on the spire's own metalwork and clock face — distinct from every other Housing & Civil building's own accent color. Distinctive silhouette detail: the tall pointed spire itself, unmistakably taller than every other Housing & Civil building. Format: single building, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole building. Square aspect ratio (1:1), PNG format.
```

**`gas_streetlamp.png`**
```
A single cast-iron Victorian gas streetlamp on its own post — an ornate fluted iron column, a small glass-paned lantern housing at the top, deliberately slight and thin, a much smaller structure than every other building in this roster. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, the whole post and lantern readable at once. Palette: black cast iron as the base material, with a warm gaslight-amber glow accent inside the lantern housing — distinct from every other Housing & Civil building's own accent color. Distinctive silhouette detail: the tall thin iron post itself, unmistakably slighter than any actual building around it. Format: single subject, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`telegraph_relay_office.png`**
```
A small dark-timber telegraph relay office — a modest wooden building with a telegraph pole rising from its roof, wires strung to insulators, a hand-painted sign. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, roof and frontage both readable at once. Palette: dark stained timber as the base material, with a warm copper/brass accent on the wires and insulator fittings — distinct from every other Housing & Civil building's own accent color. Distinctive silhouette detail: the telegraph pole and strung wires rising off the roofline. Format: single building, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole building. Square aspect ratio (1:1), PNG format.
```

**`steam_printing_press.png`**
```
A soot-blackened brick print-works building, a tall thin chimney venting steam, stacks of printed news-sheets visible through a loading door. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, roof and frontage both readable at once. Palette: soot-darkened brick as the base material, with a deep ink-burgundy accent on doors/trim — distinct from every other Housing & Civil building's own accent color. Distinctive silhouette detail: a tall thin steam-venting chimney, narrower than an industrial building's own stack. Format: single building, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole building. Square aspect ratio (1:1), PNG format.
```

**`town_hall.png`**
```
A grand civic Town Hall — pale sandstone facade, a row of tall arched windows, a small central clock tower, columned entrance steps. The most imposing, authoritative-looking building in the roster. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, roof and frontage both readable at once. Palette: pale sandstone as the base material, with a royal navy-blue accent on doors, banners, and trim — distinct from every other Housing & Civil building's own accent color. Distinctive silhouette detail: the central clock tower and columned entrance steps. Format: single building, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole building. Square aspect ratio (1:1), PNG format.
```

**`garrison.png`**
```
A fortified militia garrison building — thick grey stone walls, narrow firing-slit windows, sandbag reinforcement at the base, a flagpole. Reads as a hardened military post, not civic architecture. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, roof and frontage both readable at once. Palette: heavy grey stone as the base material, with a martial rust-red accent on the flag and trim — distinct from every other Housing & Civil building's own accent color. Distinctive silhouette detail: sandbag reinforcement stacked around the base and narrow firing-slit windows. Format: single building, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole building. Square aspect ratio (1:1), PNG format.
```

### Industry & Extraction

**`timber_camp.png`** (added post-launch, economy-balance pass — the Wood producer)
```
A working timber camp at the edge of cleared woodland — a simple crosscut-saw rig over a sawpit, a stack of freshly felled logs, a woodsman's lean-to shelter. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, the sawpit and log stack both readable at once. Palette: raw sawn timber and bark as the base material, with a fresh sap-green accent on the lean-to canvas and tool handles — distinct from every other Industry & Extraction building's own accent color. Distinctive silhouette detail: the stacked felled-log pile beside the open sawpit, unlike any enclosed shed or stack elsewhere in this category. Format: single subject, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`clay_brickworks.png`**
```
A raw industrial brickworks — an open-sided kiln shed, stacks of drying red clay bricks, a small chimney. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, roof and frontage both readable at once. Palette: raw orange-red clay as the base material, with a muddy ochre accent on the kiln structure — distinct from every other Industry & Extraction building's own accent color. Distinctive silhouette detail: stacked pallets of drying brick visible in an open yard beside the shed. Format: single building, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole building. Square aspect ratio (1:1), PNG format.
```

**`charcoal_kiln.png`**
```
A squat earthen charcoal-burning kiln mound with a timber-framed loading hatch, thin smoke wisping from vents in its dome. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, the whole mound and hatch readable at once. Palette: blackened earth and timber as the base material, with a smoldering ember-orange accent glowing at the vents — distinct from every other Industry & Extraction building's own accent color. Distinctive silhouette detail: the low rounded earthen dome shape, unlike any other industrial building's flat-roofed silhouette. Format: single building, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole building. Square aspect ratio (1:1), PNG format.
```

**`coal_pithead.png`**
```
A coal-mine pithead — a tall iron winding-gear headframe with a large wheel at the top, a small engine house beside it, a coal-wagon rail line. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, the headframe and engine house both readable at once. Palette: dark coal-blackened iron as the base material, with a warning safety-yellow accent on the headframe's own ironwork — distinct from every other Industry & Extraction building's own accent color. Distinctive silhouette detail: the tall winding-gear headframe with its large wheel, taller and thinner than any other industrial structure here. Format: single subject, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`cast_iron_foundry.png`**
```
A heavy cast-iron foundry building — a tall furnace stack, a large open casting-floor shed, molten glow visible through a furnace hatch. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, roof and frontage both readable at once. Palette: dark soot-blackened iron and brick as the base material, with a molten furnace orange-red glow accent at the hatch and stack top — distinct from every other Industry & Extraction building's own accent color. Distinctive silhouette detail: the tall thick furnace stack, bulkier than the printing press's own thin chimney. Format: single building, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole building. Square aspect ratio (1:1), PNG format.
```

**`saltpetre_powder_mill.png`**
```
An isolated gunpowder mill building, deliberately plain and low, set apart with a low earthen blast-bank wall around it for safety, hazard markings on the doors. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, roof and blast-bank both readable at once. Palette: pale plain stone as the base material, with a hazard-red accent on warning markings and door trim — distinct from every other Industry & Extraction building's own accent color. Distinctive silhouette detail: the low earthen blast-bank wall ringing the building itself, unique to this structure. Format: single building, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole building. Square aspect ratio (1:1), PNG format.
```

**`forward_ammo_dump.png`**
```
A forward ammunition supply dump — a camouflage-netted timber and sandbag structure, stacked ammunition crates visible under a tarpaulin awning. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, the crates and awning both readable at once. Palette: khaki canvas and timber as the base material, with a military khaki-green accent on the netting and crates — distinct from every other Industry & Extraction building's own accent color. Distinctive silhouette detail: stacked ammunition crates under an open tarpaulin awning, unlike any enclosed building here. Format: single subject, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

### Agriculture

**`tenant_farm.png`**
```
A modest thatched-roof tenant farmhouse with a small attached barn, timber framing, a low garden fence. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, thatched roof and yard both readable at once. Palette: warm timber and thatch as the base material, with a warm wheat-gold accent on shutters and trim — distinct from every other Agriculture building's own accent color. Distinctive silhouette detail: the thick thatched roof texture, unlike either other Agriculture building's own roofing. Format: single building, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole building. Square aspect ratio (1:1), PNG format.
```

**`grain_silo.png`**
```
Twin cylindrical grain storage towers side by side, corrugated iron cladding, a small connecting loading gantry between them. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, both cylindrical towers and the gantry readable at once. Palette: weathered corrugated iron as the base material, with a pale harvest-gold accent banding around each tower — distinct from every other Agriculture building's own accent color. Distinctive silhouette detail: the twin cylindrical tower shape, unmistakably different from every flat-roofed rectangular building in the roster. Format: single subject, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`cattle_yard.png`**
```
An open timber-fenced cattle pen with a small open-sided shelter shed at one end, trodden earth yard. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, the fenced yard and shelter both readable at once. Palette: weathered timber fencing and earth as the base material, with an earthy pasture-green accent on the shelter's own trim — distinct from every other Agriculture building's own accent color. Distinctive silhouette detail: the open fenced yard itself, mostly open ground rather than an enclosed structure, unlike either other Agriculture building. Format: single subject, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

### Defense Works

**`searchlight_tower.png`**
```
A tall iron lattice searchlight tower, an angled searchlight housing mounted at the top casting a bright beam, a narrow maintenance ladder up one side. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and prop art. Britain, 1890s, in the grip of a zombie plague — a defended, weathered outpost building, not a pristine museum piece: soot, patched repairs, a few boarded or reinforced details. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, the lattice mast and light housing both readable at once. Palette: dark iron lattice as the base material, with a bright white-blue accent for the searchlight beam and lamp housing. Distinctive silhouette detail: the tall open iron lattice mast structure, entirely unlike any solid-walled building in the roster. Format: single subject, isolated, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

## Drop-in workflow

Same as `assets/units/README.md`'s own "Drop-in workflow" section — generate,
key out the white background, save as `assets/buildings/<key>.png` (exact
keys shown above each prompt — see `BuildingVisuals._texture_key()` if this
file and the code ever drift), run the same `--headless --import` pass, done.
No code changes needed: `BuildingVisuals.building_texture()` already checks
for a PNG here before falling back to the existing SVG.
