class_name VerticalSliceConfig
extends RefCounted

## Every authored number of the vertical slice in one place: where it starts,
## what the player is handed, which hex they are asked to take, where the horde
## comes from and when. Everything else in the slice is the real game running.
##
## The ask, verbatim: "Produce a 10–20 minute vertical slice where I can start
## with a tiny settlement, expand into zombie territory, encounter a genuinely
## frightening horde, use noise/light/going-dark to manipulate the threat, fight
## it, clear the territory, and immediately understand why what I did mattered."
##
## Positions were chosen from the real map by scripts/test/diagnose_slice_start.gd
## (--around=80,119 lists the neighbourhood with D7's seeded counts):
##
## - START_HEX (80, 119) is a Manchester URBAN hex on the city's south-east edge,
##   so D99's "the start stays inside Manchester" holds. Its neighbours include open
##   moor; the canonical campaign start (79, 118) touches only Manchester core, canal
##   and Chat Moss bog. (79, 119), the first choice, was impassable when this was
##   chosen: HexMapGenerator left Chat Moss's PEAT_BOG under Manchester's settlement
##   stamp (fixed 2026-09-17, verify_settlement_passability.gd). The start was not
##   moved back, so the playtest baseline is the one the scripted players measured.
## - TARGET_HEX (79, 120), moorland south-west of the start, capacity 3,258: D7 seeds
##   815 residents and D2 clears it below 163, so the clear is ~650 kills — about
##   four real minutes for ten Tier 0 units at frontage 1
##   (ResidentDefenseController). Moorland takes farms and coal mines
##   (BuildingCatalog._FARM_BIOMES, _COAL_BIOMES): the ground is worth having.
## - HORDE_SOURCE_HEX (82, 120), open moorland 3 hexes east-south-east, capacity
##   4,974 and 3,731 seeded residents. HORDE_SIZE of them leave as one horde through
##   InfestationManager.condense_defenders(), so the count is conserved (D1) — the
##   dead are moved, not invented.
## - HORDE_DRIFT_HEX (82, 119), moorland 2 hexes east. The one authored movement:
##   the horde's first wander is sent there (HordeManager.send_wandering_toward())
##   so that at dusk it stands 2 hexes out. Everything after is the ordinary rules.
##   At 2 hexes three lamps (4.5) draw it, two (3.0) are a coin-flip on its
##   susceptibility, and one (1.5) does not; the Brickworks' night noise reaches a
##   horde only at 1 hex (~5), so a horde that wanders adjacent hears it anyway.
##   The first try drifted it to (81,119), adjacent: attraction and siege began in
##   the same second at dusk, leaving nothing to react to.

const START_HEX := Vector2i(80, 119)
const TARGET_HEX := Vector2i(79, 120)
const TARGET_NAME := "the southern moor"
const HORDE_SOURCE_HEX := Vector2i(82, 120)
const HORDE_DRIFT_HEX := Vector2i(82, 119)
## Big enough that the ten units the slice starts with lose a night siege of the
## wall piece it hits, and a prepared defence wins it: at night 39 zombies claw a
## Wooden piece down in ~103 real s, and ten defenders need ~150 s to kill 1,500 —
## sixteen need ~94 s (WallDefenseController two kills a strike). So the player
## trains archers in the warning, buys time by going dark, or both.
const HORDE_SIZE: int = 1500

## Game-seconds after the start at which the horde leaves the moor. At the default
## 5x that is 2:30 real, leaving 1:30 of daylight to answer the report before
## TimeCycleManager's dusk at 1,200 game-seconds lights the lamps.
const HORDE_RELEASE_SECONDS: float = 750.0
## Game-seconds after the start the slice gives up waiting and debriefs anyway —
## 20 real minutes at 5x, the top of the requested length.
const TIME_LIMIT_SECONDS: float = 6000.0
## A horde this many hexes from the start at dawn, with nothing drawing it, counts
## as driven off.
const DRIVEN_OFF_HEXES: int = 5

## Handed over already built, in grant order: producers of Energy and Population
## first, so the consumers after them draw on capacity that exists
## (CapacityAllocator). Local positions are world units from the hex centre (a hex
## is ~512 wu, ~5 km, corner to centre).
const STARTING_BUILDINGS: Array = [
	[GameEnums.BuildingType.WOODEN_HOUSES, Vector2(40.0, 170.0)],
	[GameEnums.BuildingType.WOODEN_HOUSES, Vector2(-60.0, -170.0)],
	[GameEnums.BuildingType.STEAM_FURNACE, Vector2(-160.0, 120.0)],
	[GameEnums.BuildingType.GARRISON, Vector2(-40.0, -40.0)],
	[GameEnums.BuildingType.CLAY_PIT, Vector2(-220.0, -40.0)],
	[GameEnums.BuildingType.BRICKWORKS, Vector2(200.0, 60.0)],
	[GameEnums.BuildingType.WATCHTOWER, Vector2(300.0, -150.0)],
	[GameEnums.BuildingType.WATCHTOWER, Vector2(310.0, 180.0)],
	[GameEnums.BuildingType.WATCHTOWER, Vector2(-300.0, 170.0)],
]
## Six Truncheoneers and four Toxophilites: enough to clear TARGET_HEX inside the
## slice, not enough to hold a wall against HORDE_SIZE at night unaided. The
## Garrison above trains more (Toxophilite 30 Wood, one in-game hour, 20 real s).
const STARTING_UNITS: Array = [
	[GameEnums.UnitType.TRUNCHEONEER, 6],
	[GameEnums.UnitType.TOXOPHILITE, 4],
]
const STARTING_RESOURCES: Dictionary = {
	GameEnums.ResourceType.WOOD: 350.0,
	GameEnums.ResourceType.FOOD: 300.0,
}
