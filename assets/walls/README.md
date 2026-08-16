# Wall art generation pipeline (user request)

**Status: infrastructure built, images not yet generated.** No tool in this
Claude Code environment can call an AI image generator — the 3 prompts
below and the code in `WallVisuals.gd`/`StrategicOverlayManager.gd` are the
complete, ready-to-use pipeline; someone with real image-generation access
needs to run the prompts and drop the resulting PNGs into this folder.

**Wall tiers** (`wall_wooden.png`/`wall_brick.png`/`wall_concrete.png`) —
a wall segment renders as a `Line2D` running the real distance between
two hex centers, so these need to be **seamlessly tileable strip
textures** (repeats along the wall's own length), not a single square
icon. `Line2D` tiles a texture along its length natively
(`texture_mode = LINE_TEXTURE_TILE`) — no code changes needed beyond
what's already wired, but the SOURCE IMAGE itself must actually tile
cleanly left-to-right (its left edge must flow into its right edge with
no visible seam) for that to look right in-game. A breached wall segment
deliberately does NOT use this art at all — it stays the existing flat
alarm-red line, unchanged, so a breach always reads as an obvious color
warning regardless of how nice the intact-wall texture looks.

Ditch/Oil Pit (a per-segment defense-work stacking mechanic) were removed
in the Building Tree rework (design_doc.md §3 has no equivalent) — the
`ditch.png`/`oil_pit.png` prompts that used to live in this file went with
them.

## Style DNA

> Style: hand-painted / illustrated game asset art — clean, bold
> cartoon-baroque style with visible brushwork and flat painterly
> cel-shading, matching this project's building and prop art. Britain,
> 1890s, in the grip of a zombie plague — a hastily-built but sturdy
> defensive structure, weathered and reinforced.

> View: bird's-eye/overhead — seen from above at a steep downward
> strategy-game camera angle, matching this game's own map view.

## The 3 wall-tier tileable strip textures

**No white background/black outline for these three** — a tileable strip
needs to repeat edge-to-edge with nothing else visible, a white margin or
outline border would create an obvious seam every time it repeats. Ask
instead for the wall material filling the entire frame edge-to-edge, and
explicitly request that the left and right edges match for seamless
tiling.

**`wall_wooden.png`**
```
A tileable strip texture of a rough wooden palisade wall — vertical timber stakes lashed together, weathered grey-brown wood, seen from directly above as a straight defensive line. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's building and prop art. Britain, 1890s, in the grip of a zombie plague — a hastily-built but sturdy defensive structure, weathered and reinforced. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, matching this game's own map view. Format: a horizontal strip texture filling the entire frame edge-to-edge (no border, no background, no outline) — the wall material itself fills the whole image. The left edge and right edge of the image must match seamlessly so the texture tiles/repeats with no visible seam when placed end-to-end. Wide aspect ratio (roughly 4:1), PNG format.
```

**`wall_brick.png`**
```
A tileable strip texture of a red-brick defensive wall — coursed brickwork, mortar lines, a slightly weathered and patched surface, seen from directly above as a straight defensive line. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's building and prop art. Britain, 1890s, in the grip of a zombie plague — a hastily-built but sturdy defensive structure, weathered and reinforced. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, matching this game's own map view. Format: a horizontal strip texture filling the entire frame edge-to-edge (no border, no background, no outline) — the wall material itself fills the whole image. The left edge and right edge of the image must match seamlessly so the texture tiles/repeats with no visible seam when placed end-to-end. Wide aspect ratio (roughly 4:1), PNG format.
```

**`wall_concrete.png`**
```
A tileable strip texture of a reinforced concrete defensive wall — smooth poured concrete with visible form-lines and a few rivet/bolt details, the sturdiest-looking of the three wall tiers, seen from directly above as a straight defensive line. Style: hand-painted / illustrated game asset art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's building and prop art. Britain, 1890s, in the grip of a zombie plague — a hastily-built but sturdy defensive structure, weathered and reinforced. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, matching this game's own map view. Format: a horizontal strip texture filling the entire frame edge-to-edge (no border, no background, no outline) — the wall material itself fills the whole image. The left edge and right edge of the image must match seamlessly so the texture tiles/repeats with no visible seam when placed end-to-end. Wide aspect ratio (roughly 4:1), PNG format.
```

## Drop-in workflow

Generate, save as `assets/walls/<key>.png` (exact keys shown above each
prompt — see `WallVisuals._texture_key()` if this file and the code ever
drift; these do NOT need background removal/keying), run the standard
`--headless --import` pass, done. No further code changes needed —
`StrategicOverlayManager` picks up whichever textures exist the next time
it redraws a wall marker.
