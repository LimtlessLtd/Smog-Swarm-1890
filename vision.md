# Vision — The Smog & The Swarm

> Authored 2026-08-27 from a direct interview with the user, then sharpened across a
> 30-question design review the same day. Everything below is a user decision, not an
> inference from the codebase. Where the user's own words settle a question they are
> quoted verbatim, per `CLAUDE.md` §2.
>
> **This document's job:** be the thing a backlog item gets checked against.
> `design_doc.md` says what the numbers are. This says what the game is for, and
> therefore what gets built next. A feature can be fully specified in `design_doc.md`
> and still not be next, if it doesn't serve a pillar below.

---

## 1. What this is

A sit-down RTS played in real sessions with full attention — 1-3 hours, like *They
Are Billions* or *Anno*. `BackgroundExecutionManager` exists so the world doesn't
freeze on alt-tab; it is a convenience, **not** a core idle/persistent mode. Design
for engagement density, not for legible catch-up after hours away.

The reference remains the standing directive in `todo.md`: design against *They Are
Billions*, don't invent new mechanics. Research how TAB does a thing before deriving
a new model from first principles.

---

## 2. Pillars

### P1 — The map is hostile everywhere. Expansion *is* combat.

> "there are zombies pretty much everywhere except the starting hex tile the player
> starts on. This means that whenever the user tries expanding their base, they will
> have to clear the zombies that are in the way"

There is no neutral ground. Every hex the player wants costs a fight. This is the
primary engine of tension — not a doom clock, not scheduled waves.

Fully specified as of 2026-08-27 in `design_doc.md` §2.1: infestation is a derived
ratio of `zombie_count / total_zombie_pop`, capacity is baked from real 1890s
population, and the world starts at 0/25/50/75/100% in rings out from the player's
hex. **None of it is built yet** — `infestation` appears nowhere in the code, and the
map currently holds ~45-75 zombies total across 4,692 hexes. This is the largest gap
between the vision and the build.

### P2 — Hordes big enough to end the run, and the counterplay is going quiet

> "large roaming hordes of zombies. Roaming Hordes so large that they threaten to end
> the players game, the user may have to turn off noisy/light emitting buildings
> (something we need to add) or a user could try and draw the horde away from the
> users city/base with some military units"

And on clearing ground:

> "this may draw more zombies into the area from the firing of the guns and the noise
> and perhaps the smell of blood"

**Noise and light are the player's primary control surface over threat.** That
reframes `design_doc.md` §6 (Vision, Sound, Light & Zombie AI) from "the largest
unimplemented section of the spec" into **the core tension engine of the game**. It
is not a polish tier.

Build state, checked 2026-08-27:
- **Noise attraction is already built** — `HordeManager`'s ATTRACTED state and
  `_pick_attraction_target()` read `NoiseManager` and path toward the loudest nearby
  hex. What's broken is *emission*: a flat 2-hex building-only aura, ~40x the reach
  of §6's loudest listed sound.
- **Buildings cannot be switched off.** No such mechanic exists. This is the most
  direct expression of the pillar and probably the smallest piece of work in it.
- **Light attraction does not exist**, but a crude version is nearly free —
  buildings already carry `lit_at_night`. Full §6 line-of-sight illumination is a
  later increment, not a prerequisite.
- **Blood attraction** is raised and explicitly deferred by the user. Discuss before
  building.

### P3 — Core game first. Campaign after.

> "We should focus on creating the core game first. The campaign comes afterwards."

> "This is not something we should be worrying about yet. We can worry about it when
> we get there. We dont even have a working base game yet."

Said in answer to two separate questions (late-game settlement scale, and how much
narrative weight the mystery carries). Treat it as general: **do not spend design or
build effort on problems that only exist once the core loop works.**

### P4 — Losing is real

Total loss genuinely ends a campaign and you start over. Rare, but it must be able to
happen or nothing is at stake. Implies saves, difficulty settings, and clear warning
before the point of no return. This supersedes nothing in `todo.md` 7.6's
"economic/capability elimination, not territorial" decision — that's *how* you lose;
this is *how much it costs*.

### P5 — Scale is literal, not faked

> "I want this to truly be TABs on an absolutely massive scale."

A London hex genuinely holds order 1e6 zombies, and what the player sees is
individual figures. Measured (`scripts/test/bench_zombie_scale.gd`): ~60,000 live
movers is the realistic budget, against TAB's ~20,000 endgame swarm. Counts stay
literal; entity instantiation is bounded by what the player can observe. See
`design_doc.md` §2.1's simulation model.

This pillar is why real-geography data earns its keep: capacity is drawn from real
1890s population, so **history decides the difficulty curve** and the
Manchester → London arc ramps because the census says it does.

### P6 — The whole island is the destination, not the current problem

Reclaiming Britain and Ireland fully lit is the eventual win condition. It implies
hundreds of hours, heavy automation, and macro tools for many settlements. Per P3,
**none of that is a current concern** and no work should be justified by it today.

---

## 3. Deferred — not forgotten, not now

Raised, answered with "not yet," and to be revisited only once the core loop works:

- Late-game settlement-count tedium and the automation/governor systems that answer
  it. Acknowledged as a real consequence of §2.1's "killing is the only suppression."
- How much weight the mystery carries (observatories, craters, Victoria's bunker).
- Blood/smell as a zombie attractor.
- Full §6 line-of-sight light propagation (the crude `lit_at_night` version is not
  deferred).
- Physical goods transport with travelling carts and trains — §2.2 ships
  throughput-limited pooling first, which is an upgrade path, not a rewrite.

---

## 4. Cut order for v1.0

If scope has to come off, in this order:

1. **Phase 3 — Sewers / Underground.** Cuttable.
2. **Phase 7.5 — Naval Logistics / Ireland.** Cuttable.
3. **Phase 7 — Narrative Campaign.** **Ships in v1.0**, but only started once the
   core mechanics and base game are figured out.

Note the consequence: cutting Naval/Ireland contradicts P6's "whole island." The user
accepted that trade knowingly. Britain-only is an acceptable v1.0.

---

## 5. The check

Every backlog item must pass all three before it is scheduled:

1. **Does it make the map more hostile, or the player's counterplay to hostility
   richer?** (P1, P2 — the core loop.)
2. **Would a player notice it in a single sit-down session of the *core* game**, with
   no campaign, no sewers, no navy?
3. **Does it avoid solving a problem that only exists after the core loop works?**
   (P3.)

An item that fails #3 goes to `backlog.md` under Deferred and is not worked on,
however well specified it is.
