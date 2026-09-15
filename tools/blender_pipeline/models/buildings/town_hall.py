"""assets/buildings/town_hall.png — GameEnums.BuildingType.TOWN_HALL, Tier 3
Housing & Civil. The colony's founding building, and the civic family's
reference model.

Re-authored 2026-09-15 for the straight-down camera. Everything that used to
distinguish this building was vertical — a clock face on the side of a tower, a
gabled facade, wall colour — and none of it projects: rendered overhead, the old
model came out as two brown rectangles and a circle. The identity now lives in
the roof plan: the civic family's pale stone forecourt, a hipped slate hall, and
the pyramid-capped tower with a gold finial that no other family uses.

Civic is the one family that keeps a straight-edged paved area, because a dressed
stone forecourt genuinely has one — but it is now a small rectangle INSIDE an
irregular ground patch rather than a slab filling the whole frame, so the site's
own outer edge is ragged and the terrain carries through around it.
"""

import bpy
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from render_common import (  # noqa: E402
    flat_material, part, hip_roof, yard_plate, roof_vent, ground_patch, path,
    family_materials,
)


def build():
    stone_mat, roof_mat, gold_mat = family_materials("civic")
    tower_roof_mat = flat_material("TowerRoof", (0.196, 0.227, 0.282))
    lawn_mat = flat_material("Lawn", (0.404, 0.451, 0.286), alpha=0.72)
    gravel_mat = flat_material("Gravel", (0.596, 0.565, 0.494), alpha=0.88)

    # Grounds: a soft irregular lawn under the whole site, so the building sits
    # in something rather than on a tile.
    ground_patch(lawn_mat, (-0.02, 0.0, 0.002), radius_x=0.60, radius_y=0.50,
                 sides=15, jitter=0.20, seed=5, name="Grounds")

    # Approach walk up to the steps, and a service path round to the back.
    path(gravel_mat, [(-0.08, -0.70), (-0.09, -0.52), (-0.08, -0.38)],
         width=0.12, seed=9)
    path(gravel_mat, [(-0.52, -0.10), (-0.46, 0.20), (-0.20, 0.34), (0.20, 0.36)],
         width=0.09, seed=17)

    # Paved forecourt — deliberately rectangular, and deliberately small.
    yard_plate(stone_mat, location=(-0.08, -0.20, 0.004), width=0.74, depth=0.30,
               thickness=0.012)

    # Main hall. The plinth is wider than the roof so a pale stone border rings
    # the dark slate — the ring is what stops the hall merging into the ground.
    part(bpy.ops.mesh.primitive_cube_add, stone_mat, (-0.08, 0.06, 0.10),
         scale=(0.80, 0.56, 0.16), size=1.0)
    hip_roof(roof_mat, (-0.08, 0.06, 0.18), width=0.76, depth=0.52,
             height=0.20, ridge_fraction=0.52)

    # Four chimneys in a rectangle. The hall's own rhythm, against the
    # tenement's single continuous row.
    for x in (-0.32, 0.10):
        for y in (-0.10, 0.22):
            roof_vent(stone_mat, (x, y, 0.36), radius=0.042, height=0.10)

    # Clock tower: square plinth, pyramid cap (ridge_fraction 0, so four
    # triangles meet at a point) and a gold finial. The finial is the single
    # brightest pixel cluster on any civic building and is what the eye finds
    # first at map zoom.
    part(bpy.ops.mesh.primitive_cube_add, stone_mat, (0.42, 0.06, 0.16),
         scale=(0.28, 0.28, 0.32), size=1.0)
    hip_roof(tower_roof_mat, (0.42, 0.06, 0.32), width=0.32, depth=0.32,
             height=0.26, ridge_fraction=0.0, name="TowerCap")
    part(bpy.ops.mesh.primitive_uv_sphere_add, gold_mat, (0.42, 0.06, 0.60),
         segments=10, ring_count=6, radius=0.048)

    # Entrance steps: three bands off the forecourt. With the facade gone this
    # is the only thing that says which side the building faces.
    for i, y in enumerate((-0.24, -0.28, -0.32)):
        part(bpy.ops.mesh.primitive_cube_add, stone_mat, (-0.08, y, 0.014 + i * 0.002),
             scale=(0.42 - i * 0.06, 0.03, 0.02), size=1.0)
