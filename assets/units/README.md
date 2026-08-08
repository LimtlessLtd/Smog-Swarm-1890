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

**Revised four times now** based on direct user feedback/hands-on editing
of earlier drafts of these prompts:
- **Round 1:** most image generators can't actually produce a transparent
  background despite being asked — background removal is a required step,
  not a fallback; the original prompts never named an art style, just what
  to avoid, risking photorealistic drift; and a shared muted role palette
  across all 18 units risked every unit of the same role collapsing into
  one indistinguishable brown blob.
- **Round 2:** background color settled on flat solid black (over
  chroma-key green — both were considered); art style specified further as
  clean, simple, cartoon-baroque (not just "painterly"); added an explicit
  isometric, slightly top-down overhead view requirement; and full body
  called out explicitly so nothing gets cropped.
- **Round 3:** background switched from black to flat solid white with a
  thick bold black outline/border around every subject — a simpler, more
  robust keying technique that also reinforces the cartoon-baroque style.
- **Round 4 (this pass — direct user feedback on the prompts themselves,
  not just the art):** the prompts were too long and leaned heavily on
  "don't do X" instructions, which tends to work against most image
  generators rather than for them (a negative instruction is often parsed
  as emphasizing the very concept it's trying to rule out). Every prompt
  below is rewritten to describe what the image SHOULD be, not what it
  shouldn't — shorter, plainer, all-positive phrasing throughout. Three
  other real changes landed in the same pass: (1) the view is now
  explicitly **bird's-eye/overhead**, not "isometric, slightly top-down"
  — a stronger, more literal statement of the actual camera angle this
  game renders units from; (2) every pose is now **neutral/idle**, not
  mid-action (aiming, swinging, drawing a weapon) — a unit standing in a
  garrison or walking to its next order isn't mid-fight most of the time,
  and the art shouldn't imply it always is; (3) the setting is now
  explicit in the shared style block — **hardened survivors of a zombie
  plague, not parade-ground soldiers** — so weathering, improvised
  repairs, and a defensive posture read through even in an idle pose.
  Several units' own flavor also changed this pass because their real
  in-game identity changed alongside the art (see `todo.md`'s Phase 5.4
  entry for the full mechanical writeup): the **Chasseur** is now mounted
  and carries a real handgun (previously just a sabre, no mount), making
  it a genuinely better-armed alternative to the unarmed Outrider it
  shares a tier-progression role with.

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
the rest later. **Suggested first step given this is a four-times-revised
prompt template: generate just one or two and check the results (style,
angle, palette separation, background keys out cleanly) before running
all 18.**

## Style DNA (already baked into every prompt below — kept here only as a single source of truth if the shared style ever needs editing)

Editing this section does NOT change the prompts below — since each one is
meant to be copied standalone, the same style/format text is repeated
inside all 18. If the shared style changes, update it here first to get
the wording right, then find-and-replace it across the 18 blocks.

> Style: hand-painted / illustrated game character art — clean, bold
> cartoon-baroque style with visible brushwork and flat painterly
> cel-shading. Britain, 1890s, in the grip of a zombie plague — a
> hardened survivor-defender, not a parade-ground soldier: genuine
> Victorian Industrial-Revolution dress and equipment (wool, leather,
> brass, cast iron), practical and weathered, with a few improvised
> repairs or added protection.

> View: bird's-eye/overhead — seen from above at a steep downward
> strategy-game camera angle, face and front both readable at once.

> Pose: standing at ease or idle, not mid-action — alert and ready, not
> caught mid-swing, mid-draw, or mid-fire.

> Format: single subject, full body, centered, small margin, bold clear
> silhouette readable at small size, plain flat white (`#FFFFFF`)
> background, evenly lit with no shadow or gradient, a thick bold black
> outline around the whole subject (comic-book/cel-shaded linework).
> Square aspect ratio (1:1), PNG format.

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

Every prompt also carries a short differentiation line: same role,
different tier, must still look like a different unit (varied silhouette/
headgear/equipment), not the same figure recolored.

Tier progression: Tier 0-3 are individual soldiers in progressively more
standardized/heavier Victorian military dress. Tier 4-5 are heavy
steam-powered engineering vehicles — every Tier 4-5 prompt describes a
concrete wheeled/tracked mechanical shape (wheels, tracks, pistons,
riveted plate) specifically enough that there's nothing else for the
image to default to.

## The 18 prompts

### Tier 0 — "Free Ammo" starting tier, no tech needed

**`truncheoneer.png`** (Melee)
```
A Victorian parish constable/night-watchman standing watch: heavy wool coat, tall hat, a wooden truncheon holstered at his belt, a lantern clipped nearby, worn leather boots. Unglamorous and grounded — the plainest defender in the roster. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — a hardened survivor-defender, not a parade-ground soldier: genuine Victorian Industrial-Revolution dress and equipment (wool, leather, brass, cast iron), practical and weathered, with a few improvised repairs or added protection. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, face and front both readable at once. Pose: standing at ease, alert and watchful, not mid-swing. Palette: weathered base uniform (greys, browns, khaki), with a vivid, saturated rust-red accent (sash, trim, cap band, insignia) as a clear pop against it. Distinct silhouette and gear from other units of the same role — not a recolor. Format: single subject, full body, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`toxophilite.png`** (Ranged)
```
A civilian archer in practical Victorian outdoor dress (tweed jacket, flat cap), a traditional English longbow slung over one shoulder, unstrung and at rest. No firearm, no ammunition belt or powder horn. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — a hardened survivor-defender, not a parade-ground soldier: genuine Victorian Industrial-Revolution dress and equipment (wool, leather, brass, cast iron), practical and weathered, with a few improvised repairs or added protection. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, face and front both readable at once. Pose: standing at ease, calm and watchful, not mid-draw. Palette: weathered base uniform (greys, browns, khaki), with a vivid, saturated cobalt-blue accent (sash, trim, cap band, quiver strap) as a clear pop against it. Distinct silhouette and gear from other units of the same role — not a recolor. Format: single subject, full body, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`outrider.png`** (Special)
```
An unarmed mounted scout on a sturdy horse — a Victorian riding coat and boots, a spyglass and dispatch satchel at his side, carrying no weapon at all. His only value is speed and reconnaissance, not combat. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — a hardened survivor-defender, not a parade-ground soldier: genuine Victorian Industrial-Revolution dress and equipment (wool, leather, brass, cast iron), practical and weathered, with a few improvised repairs or added protection. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, face and front both readable at once. Pose: horse standing calmly, rider upright and watchful, at ease in the saddle. Palette: weathered base uniform (greys, browns, khaki), with a vivid, saturated violet-purple accent (sash, trim, cap band, saddle trim) as a clear pop against it. Distinct silhouette and gear from other units of the same role — not a recolor. Format: single subject, full body shown including the horse, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

### Tier 1

**`navvy.png`** (Melee)
```
A burly railway/canal labourer turned militiaman: flat cap, rolled shirt sleeves, heavy braces, a pickaxe or sledgehammer slung over one shoulder as an improvised weapon. Working-class dress — armed labour, not a trained soldier. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — a hardened survivor-defender, not a parade-ground soldier: genuine Victorian Industrial-Revolution dress and equipment (wool, leather, brass, cast iron), practical and weathered, with a few improvised repairs or added protection. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, face and front both readable at once. Pose: standing at ease, resting on his tool, not mid-swing. Palette: weathered base uniform (greys, browns, khaki), with a vivid, saturated rust-red accent (sash, trim, cap band, insignia) as a clear pop against it. Distinct silhouette and gear from other units of the same role — not a recolor. Format: single subject, full body, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`yeoman_marksman.png`** (Ranged)
```
A rural militia rifleman in practical hunting/shooting attire (flat cap or wide-brim hat, canvas jacket), an early breech-loading rifle slung over his shoulder, a leather cartridge bandolier across his chest — the first unit in this roster to actually depend on gunpowder. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — a hardened survivor-defender, not a parade-ground soldier: genuine Victorian Industrial-Revolution dress and equipment (wool, leather, brass, cast iron), practical and weathered, with a few improvised repairs or added protection. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, face and front both readable at once. Pose: standing at ease, watchful, rifle slung not raised. Palette: weathered base uniform (greys, browns, khaki), with a vivid, saturated cobalt-blue accent (sash, trim, cap band, bandolier trim) as a clear pop against it. Distinct silhouette and gear from other units of the same role — not a recolor. Format: single subject, full body, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`grenadier.png`** (Special)
```
A militia grenadier in a simple dark tunic, a satchel of hand-thrown black-powder grenades slung across his chest, one grenade held loosely at his side — ready to throw, not mid-throw. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — a hardened survivor-defender, not a parade-ground soldier: genuine Victorian Industrial-Revolution dress and equipment (wool, leather, brass, cast iron), practical and weathered, with a few improvised repairs or added protection. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, face and front both readable at once. Pose: standing at ease, alert, grenade held low and ready. Palette: weathered base uniform (greys, browns, khaki), with a vivid, saturated violet-purple accent (sash, trim, cap band, satchel strap) as a clear pop against it. Distinct silhouette and gear from other units of the same role — not a recolor. Format: single subject, full body, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

### Tier 2

**`redcoat.png`** (Melee)
```
A British Army infantryman in full dress: red wool tunic, white cross-belts, dark trousers, a shako or pith helmet, a bayoneted rifle held upright at rest against his shoulder. A disciplined, iconic Victorian regular-infantry stance. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — a hardened survivor-defender, not a parade-ground soldier: genuine Victorian Industrial-Revolution dress and equipment (wool, leather, brass, cast iron), practical and weathered, with a few improvised repairs or added protection. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, face and front both readable at once. Pose: standing at attention, rifle at rest, not mid-thrust. Palette: the tunic is already red by historical uniform — let the vivid, saturated rust-red role accent show as brighter trim, piping, and insignia standing out clearly against it; other materials (belts, trousers, helmet) stay grounded and weathered. Distinct silhouette and gear from other units of the same role — not a recolor. Format: single subject, full body, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`rifleman.png`** (Ranged)
```
A Rifle Regiment soldier in a dark green tunic (historically distinct from a redcoat's red), peaked cap, a rifle slung over his shoulder. More polished and uniform than a rural militia marksman. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — a hardened survivor-defender, not a parade-ground soldier: genuine Victorian Industrial-Revolution dress and equipment (wool, leather, brass, cast iron), practical and weathered, with a few improvised repairs or added protection. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, face and front both readable at once. Pose: standing at ease, watchful, rifle slung not raised. Palette: the dark green tunic is the historically-accurate base — with a vivid, saturated cobalt-blue accent (sash, trim, cap band, insignia) clearly visible against it. Distinct silhouette and gear from other units of the same role — not a recolor. Format: single subject, full body, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`chasseur.png`** (Special)
```
A mounted skirmisher on horseback, a short tunic with braided frogging, a revolver holstered at his hip — mounted AND genuinely armed, unlike the unarmed Outrider scout. Alert and at ease in the saddle, hand resting near the holster. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — a hardened survivor-defender, not a parade-ground soldier: genuine Victorian Industrial-Revolution dress and equipment (wool, leather, brass, cast iron), practical and weathered, with a few improvised repairs or added protection. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, face and front both readable at once. Pose: horse standing calmly, rider upright and alert, not mid-draw. Palette: weathered base uniform (greys, browns, khaki), with a vivid, saturated violet-purple accent (sash, trim, cap band, saddle trim) as a clear pop against it. Distinct silhouette and gear from other units of the same role — not a recolor. Format: single subject, full body shown including the horse, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

### Tier 3

**`highlander.png`** (Melee)
```
An elite Scottish Highland regiment soldier: kilt, sporran, feather bonnet, tartan sash, a claymore or bayoneted rifle held at rest. A proud, disciplined stance — visibly the best-equipped individual soldier in the roster. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — a hardened survivor-defender, not a parade-ground soldier: genuine Victorian Industrial-Revolution dress and equipment (wool, leather, brass, cast iron), practical and weathered, with a few improvised repairs or added protection. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, face and front both readable at once. Pose: standing tall at ease, weapon at rest, not mid-swing. Palette: weathered base uniform (greys, browns, khaki), with a vivid, saturated rust-red accent carried in the tartan/sash pattern, a clear pop against the base. Distinct silhouette and gear from other units of the same role — not a recolor. Format: single subject, full body, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`sharpshooter.png`** (Ranged)
```
A designated marksman in subdued drab/khaki dress, breaking from the brighter dress of lower-tier units, a scoped or long-barrelled precision rifle slung over his shoulder, standing watchfully. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — a hardened survivor-defender, not a parade-ground soldier: genuine Victorian Industrial-Revolution dress and equipment (wool, leather, brass, cast iron), practical and weathered, with a few improvised repairs or added protection. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, face and front both readable at once. Pose: standing at ease, watchful, rifle slung not raised. Palette: weathered base uniform (greys, browns, khaki), with a vivid, saturated cobalt-blue accent (sash, trim, cap band, insignia) as a clear pop against it. Distinct silhouette and gear from other units of the same role — not a recolor. Format: single subject, full body, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`dragoon.png`** (Special)
```
A mounted dragoon in a cavalry tunic and plumed helmet, a sabre sheathed at his hip, one hand resting near the hilt — poised to charge at a moment's notice, but calm for now. The last individual soldier-on-horse before this roster shifts entirely to steam-powered vehicles at the next tier. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — a hardened survivor-defender, not a parade-ground soldier: genuine Victorian Industrial-Revolution dress and equipment (wool, leather, brass, cast iron), practical and weathered, with a few improvised repairs or added protection. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, face and front both readable at once. Pose: horse standing alert, rider upright, sabre sheathed not drawn. Palette: weathered base uniform (greys, browns, khaki), with a vivid, saturated violet-purple accent (sash, trim, cap band, saddle trim) as a clear pop against it. Distinct silhouette and gear from other units of the same role — not a recolor. Format: single subject, full body shown including the horse, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

### Tier 4 — heavy steam engineering begins

**`steam_pram_rammer.png`** (Melee)
```
A squat, heavily armoured steam-powered traction engine on wide iron wheels, a narrow reinforced ramming prow projecting from the front, riveted iron plating, a coal-smoke stack — a mechanical vehicle silhouette, low and wheeled, built to strike fast and hard at one point of impact. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — practical, weathered Victorian engineering (iron, rivets, brass, coal soot), a few dents and improvised repairs. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, the whole vehicle silhouette readable at once. Pose: stationary, at rest, no motion blur. Palette: weathered iron/rust plating, with a vivid, saturated rust-red accent (a painted panel, warning stripe, or trim band) as a clear pop against it. Distinct silhouette from other vehicles of the same role — not a recolor. Format: single subject, full vehicle shown, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`armored_locomotive_gunner.png`** (Ranged)
```
A small armoured rail-gun platform: a stubby armoured locomotive or railcar on rail wheels, a single heavy gun barrel mounted on top, riveted plate, a small smoke stack — a mechanical vehicle on rails. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — practical, weathered Victorian engineering (iron, rivets, brass, coal soot), a few dents and improvised repairs. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, the whole vehicle silhouette readable at once. Pose: stationary, at rest, gun level not firing. Palette: weathered iron/rust plating, with a vivid, saturated cobalt-blue accent (a painted panel, warning stripe, or trim band) as a clear pop against it. Distinct silhouette from other vehicles of the same role — not a recolor. Format: single subject, full vehicle shown, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`steam_tractor_landship.png`** (Special)
```
A wide, heavily-plated steam tractor built to bulldoze through obstacles — a broad reinforced dozer-blade/plow front (not a narrow ram), thick armour plating over its entire hull, wide iron wheels or tracks, a tall coal-smoke stack. Bulkier and heavier-looking than any other vehicle in the roster — this is a slow, tough damage-absorber built to shove things aside, not a fast striker. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — practical, weathered Victorian engineering (iron, rivets, brass, coal soot), a few dents and improvised repairs. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, the whole vehicle silhouette readable at once. Pose: stationary, at rest, no motion blur. Palette: weathered iron/rust plating, with a vivid, saturated violet-purple accent (a painted panel, warning stripe, or trim band) as a clear pop against it. Distinct silhouette from other vehicles of the same role — not a recolor. Format: single subject, full vehicle shown, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

### Tier 5 — the roster's heaviest engineering

**`steam_machine_leg.png`** (Melee)
```
A heavy steam-powered breaching vehicle on wide iron wheels or tracks, a large piston-driven ram mechanism mounted at the front for crushing/breaching — a low, mechanical vehicle silhouette (the "leg" in its name is the piston-ram mechanism itself, not a walking limb). Riveted heavy iron plating throughout. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — practical, weathered Victorian engineering (iron, rivets, brass, coal soot), a few dents and improvised repairs. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, the whole vehicle silhouette readable at once. Pose: stationary, at rest, piston retracted. Palette: weathered heavy iron/rust plating, with a vivid, saturated rust-red accent (a painted panel, warning stripe, or trim band) as a clear pop against it. Distinct silhouette from other vehicles of the same role — not a recolor. Format: single subject, full vehicle shown, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`railway_siege_howitzer.png`** (Ranged)
```
A massive gun mounted on a dedicated rail carriage/flatcar, a long heavy barrel, a riveted iron armoured mount, a coal-smoke stack — unmistakably siege artillery on rails. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — practical, weathered Victorian engineering (iron, rivets, brass, coal soot), a few dents and improvised repairs. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, the whole vehicle silhouette readable at once. Pose: stationary, at rest, barrel level not firing. Palette: weathered heavy iron/rust plating, with a vivid, saturated cobalt-blue accent (a painted panel, warning stripe, or trim band) as a clear pop against it. Distinct silhouette from other vehicles of the same role — not a recolor. Format: single subject, full vehicle shown, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
```

**`war_machine_armored_car.png`** (Special)
```
A large armoured car/traction-engine hybrid on wide iron wheels, riveted plate on all sides, ammunition crates and supply canisters visibly strapped/mounted along its flanks and rear — a mobile ammunition supply dump on wheels, the roster's heaviest support vehicle. Style: hand-painted / illustrated game character art — clean, bold cartoon-baroque style with visible brushwork and flat painterly cel-shading. Britain, 1890s, in the grip of a zombie plague — practical, weathered Victorian engineering (iron, rivets, brass, coal soot), a few dents and improvised repairs. View: bird's-eye/overhead — seen from above at a steep downward strategy-game camera angle, the whole vehicle silhouette readable at once. Pose: stationary, at rest, no motion blur. Palette: weathered heavy iron/rust plating, with a vivid, saturated violet-purple accent (a painted panel, warning stripe, or trim band) as a clear pop against it. Distinct silhouette from other vehicles of the same role — not a recolor. Format: single subject, full vehicle shown, centered, small margin, bold clear silhouette readable at small size, plain flat white (#FFFFFF) background, evenly lit with no shadow or gradient, a thick bold black outline around the whole subject. Square aspect ratio (1:1), PNG format.
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
