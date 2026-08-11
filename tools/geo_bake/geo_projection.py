"""Real lon/lat <-> game world-space projection, fit by calibration.

The ORIGINAL coastline bake (PR #34, 2026-08-08) used an equirectangular
projection with longitude scaled by cos(mean_latitude), fit to hex-axial
space with one uniform scale factor. That pipeline was run entirely
offline and never committed to this repo -- only its OUTPUT (the land/
ocean RLE mask and 17 hand-placed GeographyFeature anchors baked into
BritishGeographyData.gd) and a prose description of the method survive.
The exact numeric constants (mean latitude used, scale factor, offset)
are lost and cannot be exactly reproduced.

This module does NOT try to reverse-engineer those lost constants. It
fits a FRESH 6-parameter affine transform directly from (lon, lat) to
game WORLD-SPACE (the same coordinate space HexCoord.axial_to_world()
already produces), calibrated against the CURRENT hex positions of the
17 named anchors already baked into BritishGeographyData.gd. This is
safe to do (verified by grepping the whole codebase): nothing outside
BritishGeographyData.gd hardcodes any anchor's hex coordinate --
BuildingManager.gd's own doc comment (~line 220) explains starting-
settlement resolution is deliberately done by region_name string match,
"not a hardcoded coordinate," specifically because Manchester's position
has shifted before without incident.

Fitting straight to world-space (rather than to axial q,r) means the
SAME transform directly serves three consumers with one source of truth:
  1. Re-baking the Natural Earth coastline under a self-consistent frame.
  2. Re-projecting the 17 named-feature anchors.
  3. Placing every pixel of the new sub-hex land-cover/elevation rasters.

The fit is an unconstrained 6-parameter affine (anisotropic scale, no
forced orthogonality), which is a strict superset of "equirectangular +
uniform hex-space scale" (itself just anisotropic scale with no
rotation/shear) -- so an ordinary least-squares fit recovers geography
that's self-consistent even though it won't bit-for-bit reproduce the
lost original numbers.

HexCoord.axial_to_world()'s formula (scripts/world/HexCoord.gd) is
reimplemented here in Python -- it's five lines, not worth shelling out
to Godot for.
"""

import math

import numpy as np

# HexCoord.HEX_SIZE (scripts/world/HexCoord.gd) -- world-unit circumradius
# of one hex. Must match the live constant; if that constant ever changes,
# re-run this bake.
HEX_SIZE = 512.0

SQRT3 = math.sqrt(3.0)


def axial_to_world(q: float, r: float) -> tuple[float, float]:
    """Direct port of HexCoord.axial_to_world() (scripts/world/HexCoord.gd)."""
    x = HEX_SIZE * (SQRT3 * q + SQRT3 / 2.0 * r)
    y = HEX_SIZE * (3.0 / 2.0 * r)
    return x, y


# (lon, lat, q, r) calibration correspondence table.
#
# lon/lat for the 3 major cities were verified via live web search this
# session (2026-08-10) against multiple independent sources. The
# remaining ~17 rows (mountain-range/river/wetland/farmland endpoints)
# use well-established approximate real-world coordinates for named UK
# geographic features -- NOT independently re-verified point by point,
# since a) they are secondary calibration weight (the 3 verified city
# anchors + the sheer number of rows dominate the least-squares fit) and
# b) a few hundred metres to ~1km of slack on a minor secondary anchor is
# a small fraction of one ~8km hex and won't meaningfully skew the fit.
# The (q, r) side of every row is copied verbatim from the CURRENT
# BritishGeographyData.gd (git history, PR #34/#40-ish era) so the fit
# reproduces today's relative geography, not the literal lost original.
CALIBRATION_POINTS = [
    # name, lon, lat, q, r
    ("Manchester", -2.2446, 53.4840, 80, 118),
    ("Birmingham", -1.9030, 52.4796, 76, 132),
    ("London (Tower of London)", -0.0761, 51.5085, 81, 147),
    ("Pennines north (Cross Fell area)", -2.35, 54.70, 91, 95),
    ("Pennines south (Peak District)", -1.82, 53.38, 83, 119),
    ("Chilterns SW (Goring)", -1.14, 51.53, 74, 146),
    ("Chilterns NE (Dunstable Downs)", -0.42, 51.88, 81, 141),
    ("Cotswolds S (Bath)", -2.36, 51.38, 64, 149),
    ("Cotswolds N (Chipping Campden)", -1.78, 52.05, 73, 139),
    ("Mersey (Warrington/estuary approach)", -2.75, 53.35, 74, 120),
    ("Trent source (Stoke area)", -2.18, 53.00, 78, 123),
    ("Trent mouth (Humber)", -0.71, 53.70, 93, 114),
    ("Thames Head (Kemble)", -2.03, 51.68, 69, 144),
    ("Thames Estuary (Southend approach)", 0.71, 51.53, 86, 148),
    ("Grand Union / Brentford", -0.31, 51.48, 80, 147),
    ("Chat Moss", -2.40, 53.47, 79, 118),
    ("The Fens (Ely)", 0.2620, 52.3989, 90, 131),
    ("Thames Estuary Marshes (Sheppey)", 0.75, 51.43, 87, 149),
    ("Cheshire Plain (Nantwich)", -2.5236, 53.0667, 76, 122),
    ("Midlands Farmland (Warwick)", -1.5850, 52.2820, 80, 131),
    ("Industrial Slag Heaps (Oldham/Rochdale)", -2.12, 53.57, 81, 117),
]


def fit_affine(points=CALIBRATION_POINTS):
    """Fit world_x = a*lon + b*lat + c, world_y = d*lon + e*lat + f.

    Returns a 2x3 numpy array [[a,b,c],[d,e,f]] and prints a residual
    sanity table (this is the first, cheapest verification step -- run
    before any network I/O).
    """
    lons = np.array([p[1] for p in points])
    lats = np.array([p[2] for p in points])
    target_xy = np.array([axial_to_world(p[3], p[4]) for p in points])

    A = np.stack([lons, lats, np.ones_like(lons)], axis=1)  # (N, 3)
    coeffs_x, *_ = np.linalg.lstsq(A, target_xy[:, 0], rcond=None)
    coeffs_y, *_ = np.linalg.lstsq(A, target_xy[:, 1], rcond=None)
    transform = np.array([coeffs_x, coeffs_y])  # shape (2, 3)

    print("Affine fit residuals (world units; HEX_SIZE=512 -> 1 hex ~= 512-886 units):")
    max_err = 0.0
    for (name, lon, lat, q, r), (tx, ty) in zip(points, target_xy):
        wx, wy = apply_affine(transform, lon, lat)
        err = math.hypot(wx - tx, wy - ty)
        max_err = max(max_err, err)
        print(f"  {name:42s} target=({tx:9.1f},{ty:9.1f}) fit=({wx:9.1f},{wy:9.1f}) err={err:7.1f}")
    print(f"  max residual: {max_err:.1f} world units (~{max_err / HEX_SIZE:.2f} hex radii)")
    return transform


def apply_affine(transform, lon: float, lat: float) -> tuple[float, float]:
    x = transform[0, 0] * lon + transform[0, 1] * lat + transform[0, 2]
    y = transform[1, 0] * lon + transform[1, 1] * lat + transform[1, 2]
    return x, y


def invert_affine(transform):
    """Return the inverse map: world (x,y) -> (lon, lat)."""
    linear = transform[:, :2]  # 2x2
    offset = transform[:, 2]  # 2
    inv_linear = np.linalg.inv(linear)
    return inv_linear, offset


def world_to_lonlat(inv_linear, offset, x: float, y: float) -> tuple[float, float]:
    dx = x - offset[0]
    dy = y - offset[1]
    lon = inv_linear[0, 0] * dx + inv_linear[0, 1] * dy
    lat = inv_linear[1, 0] * dx + inv_linear[1, 1] * dy
    return lon, lat


if __name__ == "__main__":
    fit_affine()
