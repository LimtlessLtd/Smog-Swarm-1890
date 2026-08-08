# Zombie/horde art generation pipeline (user request)

**Status: infrastructure built, images not yet generated.** No tool in this
Claude Code environment can call an AI image generator — the 3 prompts
below and the code in `ZombieVisuals.gd`/`TacticalEntityLayer.gd` are the
complete, ready-to-use pipeline; someone with real image-generation access
needs to run the prompts and drop the resulting PNGs into this folder.

**Why 3 images, not 18 like units:** a `Horde` has no "type" the way a
`UnitInstance` does — every zombie in every horde is mechanically
identical (`Horde.gd`'s own combat math treats a horde as one uniform
blob). Three variants exist purely for visual variety at HIGH fidelity's
individual-figure rendering — a wall of visually-identical clones reads
worse than a small mix — chosen deterministically per figure
(`ZombieVisuals.zombie_texture()`, seeded off horde id + figure index) so
the same figure always looks the same across redraws, not randomly
flickering. Partial coverage is fine here too: generate just `zombie_0.png`
first and the other two fall back to the procedural circle individually
until they exist.

Same conventions as `assets/units/README.md` — one self-contained prompt
per block, generate all 3 in the same session for style consistency, flat
white background with a thick black outline for reliable keying, save as
`assets/zombies/zombie_0.png` / `zombie_1.png` / `zombie_2.png`.

**Deliberately NOT consulted at LOW Tactical fidelity** — LOW stays a
uniform colored diamond blob regardless of art, same "LOW never
differentiates by type" decision this project already made for units
(`TacticalEntityLayer`'s own doc comment) and is now making again here for
consistency, not a new call.

## Style DNA (shared style repeated inside all 3 prompts — edit here first if it ever needs to change)

> Style: hand-painted / illustrated game character art — clean, bold
> cartoon-baroque style with visible brushwork and flat painterly
> cel-shading, matching this project's unit and building art. Britain,
> 1890s — a shambling victim of the plague this game is named for, not a
> cartoonish monster: recognizably a person once, in torn/soiled
> Victorian-era clothing, grey-green decayed skin tone.

> View: bird's-eye/overhead — seen from above at a steep downward
> strategy-game camera angle, matching every other figure in this game.

> Pose: shambling/standing, arms loose, not mid-lunge or mid-attack —
> these render in large clustered groups, and a whole horde caught
> mid-lunge reads as visual noise rather than a menacing crowd.

> Format: single subject, full body, centered, small margin, bold clear
> silhouette readable at small size, plain flat white (`#FFFFFF`)
> background, evenly lit with no shadow or gradient, a thick bold black
> outline around the whole subject. Square aspect ratio (1:1), PNG format.

## The 3 prompts

**`zombie_0.png`**
```
A shambling zombie in torn Victorian working-class clothing (flat cap, tattered waistcoat, rolled shirt sleeves) — recognizably a person once, grey-green decayed skin, a slack posture. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and building art. Britain, 1890s — a shambling victim of the plague this game is named for, not a cartoonish monster: recognizably a person once, in torn/soiled Victorian-era clothing, grey-green decayed skin tone. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, matching every other figure in this game. Pose: shambling, arms loose at its sides, not mid-lunge. Format: single subject, full body, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`zombie_1.png`**
```
A shambling zombie in torn Victorian formal dress (a ragged frock coat, a battered top hat hanging half off) — recognizably a person once, grey-green decayed skin, one arm hanging lower than the other. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and building art. Britain, 1890s — a shambling victim of the plague this game is named for, not a cartoonish monster: recognizably a person once, in torn/soiled Victorian-era clothing, grey-green decayed skin tone. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, matching every other figure in this game. Pose: shambling, off-balance lean, not mid-lunge. Format: single subject, full body, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`zombie_2.png`**
```
A shambling zombie in a torn Victorian maid/servant's dress and apron, hair coming loose — recognizably a person once, grey-green decayed skin, head tilted at an unnatural angle. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading, matching this project's unit and building art. Britain, 1890s — a shambling victim of the plague this game is named for, not a cartoonish monster: recognizably a person once, in torn/soiled Victorian-era clothing, grey-green decayed skin tone. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, matching every other figure in this game. Pose: shambling, head tilted, arms loose, not mid-lunge. Format: single subject, full body, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

## Drop-in workflow

Generate, key out the white background, save as `assets/zombies/zombie_N.png`
(N = 0, 1, or 2), run the standard `--headless --import` pass, done. No code
changes needed — `TacticalEntityLayer` picks up whichever variants exist the
next time it redraws a horde's figures at MEDIUM/HIGH fidelity.
