# Prop/scenery art generation pipeline (user request)

**Status: infrastructure built, images not yet generated.** No tool in this
Claude Code environment can call an AI image generator — the 4 prompts
below and the code in `PropVisuals.gd`/`TacticalHexView.gd` are the
complete, ready-to-use pipeline; someone with real image-generation access
needs to run the prompts and drop the resulting PNGs into this folder.

One prompt per `GameEnums.PropType` (Tree/Bush/Rock/Reed) — the scattered
terrain decoration in Tactical view, currently drawn as flat colored
code-shapes (`TacticalHexView._prop_polygon()`/`_prop_color()`). Real art
replaces that per-species, wherever authored — same "art lands
incrementally" contract as everywhere else in this project. **Deliberately
NOT consulted at LOW Tactical fidelity** — LOW keeps its own uniform
procedural blob regardless of art, same call this project already made for
units and zombies.

Same conventions as `assets/units/README.md` otherwise — one
self-contained prompt per block, generate all 4 in the same session for
style consistency, flat white background with a thick black outline for
reliable keying, save as `assets/props/<key>.png`.

## Style DNA (shared style repeated inside all 4 prompts — edit here first if it ever needs to change)

> Style: hand-painted / illustrated game asset art — clean, bold
> cartoon-baroque style with visible brushwork and flat painterly
> cel-shading, matching this project's unit and building art. Rural/wild
> British countryside, late 19th century.

> View: bird's-eye/overhead — seen from above at a steep downward
> strategy-game camera angle, matching every other asset in this game.

> Format: single subject, centered, small margin, bold clear silhouette
> readable at small size, plain flat white (`#FFFFFF`) background, evenly
> lit with no shadow or gradient, a thick bold black outline around the
> whole subject. Square aspect ratio (1:1), PNG format.

## The 4 prompts

**`tree.png`**
```
A single mature British deciduous tree (oak or similar), a full rounded canopy, a visible trunk. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and building art. Rural/wild British countryside, late 19th century. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, matching every other asset in this game. Palette: deep natural greens with warm brown bark. Format: single subject, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`bush.png`**
```
A single rounded wild hedgerow bush/shrub, dense low foliage. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and building art. Rural/wild British countryside, late 19th century. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, matching every other asset in this game. Palette: mid-toned natural greens, slightly lighter/brighter than the tree's own canopy so the two read as clearly different species. Format: single subject, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`rock.png`**
```
A single weathered grey boulder/rock outcrop, irregular natural shape. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and building art. Rural/wild British countryside, late 19th century. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, matching every other asset in this game. Palette: weathered natural greys with a faint moss-green accent in the crevices. Format: single subject, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`reed.png`**
```
A small cluster of tall wetland reeds/rushes, thin upright stalks with seed-head tips. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and building art. Rural/wild British countryside, late 19th century. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, matching every other asset in this game. Palette: muted olive-green stalks with warm tan seed-head tips. Format: single subject, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

## Drop-in workflow

Generate, key out the white background, save as `assets/props/<key>.png`
(exact keys shown above each prompt — see `PropVisuals._texture_key()` if
this file and the code ever drift), run the standard `--headless --import`
pass, done. No further code changes needed — `TacticalHexView` picks up
whichever textures exist the next time it redraws a hex's scattered props
at MEDIUM/HIGH fidelity.
