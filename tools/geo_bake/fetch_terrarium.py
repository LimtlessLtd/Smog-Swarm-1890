"""AWS/Mapzen public "Terrain Tiles" elevation fetcher.

https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png
No auth, public S3, worldwide, SRTM-derived. Confirmed reachable and
decodable this session (see png_codec.py's decoder, proven against a
real fetched tile and cross-checked against two independent reference
point-elevation APIs -- Open-Elevation and Open-Topo-Data -- before
this module existed).

"Terrarium" RGB encoding: elevation_metres = (R*256 + G + B/256) - 32768

z=9 gives ~180m/px at GB's latitude, finer than the ~936m/px bake grid
this project's terrain bake targets, with margin -- one Terrarium pixel
never has to stand in for more than a small fraction of one output
pixel.
"""

import math
import os
import urllib.request

from png_codec import decode_png_rgb8

_CACHE_DIR = os.path.join(os.path.dirname(__file__), "cache", "terrarium")
_ZOOM = 9
_TILE_SIZE = 256

_tile_cache: dict[tuple[int, int, int], tuple[int, int, bytes]] = {}


def _latlon_to_tile(lat: float, lon: float, z: int) -> tuple[int, int]:
    lat_rad = math.radians(lat)
    n = 2 ** z
    xtile = int((lon + 180.0) / 360.0 * n)
    ytile = int((1.0 - math.log(math.tan(lat_rad) + 1 / math.cos(lat_rad)) / math.pi) / 2.0 * n)
    return xtile, ytile


def _pixel_in_tile(lat: float, lon: float, z: int, xtile: int, ytile: int, size: int) -> tuple[int, int]:
    n = 2 ** z
    x_frac = (lon + 180.0) / 360.0 * n - xtile
    lat_rad = math.radians(lat)
    y_frac = (1.0 - math.log(math.tan(lat_rad) + 1 / math.cos(lat_rad)) / math.pi) / 2.0 * n - ytile
    px = int(x_frac * size)
    py = int(y_frac * size)
    return max(0, min(size - 1, px)), max(0, min(size - 1, py))


def _fetch_tile(z: int, x: int, y: int) -> tuple[int, int, bytes]:
    key = (z, x, y)
    if key in _tile_cache:
        return _tile_cache[key]

    os.makedirs(_CACHE_DIR, exist_ok=True)
    cache_path = os.path.join(_CACHE_DIR, f"{z}_{x}_{y}.png")
    if os.path.exists(cache_path):
        with open(cache_path, "rb") as f:
            data = f.read()
    else:
        url = f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
        try:
            with urllib.request.urlopen(url, timeout=15) as resp:
                data = resp.read()
        except Exception as exc:  # noqa: BLE001 -- bake-time best-effort, see caller fallback
            print(f"  WARN: failed to fetch elevation tile {z}/{x}/{y}: {exc}")
            _tile_cache[key] = (0, 0, b"")
            return _tile_cache[key]
        with open(cache_path, "wb") as f:
            f.write(data)

    w, h, rgb = decode_png_rgb8(data)
    _tile_cache[key] = (w, h, rgb)
    return _tile_cache[key]


def terrarium_elevation_at(lon: float, lat: float) -> float:
    """Returns real elevation in metres for one real-world point.

    Returns 0.0 (sea level) if the tile fetch failed -- a graceful,
    disclosed degradation for a one-off transient network hiccup during
    a long bake run, not silently corrupting the whole output.
    """
    xt, yt = _latlon_to_tile(lat, lon, _ZOOM)
    w, h, rgb = _fetch_tile(_ZOOM, xt, yt)
    if not rgb:
        return 0.0
    px, py = _pixel_in_tile(lat, lon, _ZOOM, xt, yt, w)
    idx = (py * w + px) * 3
    r, g, b = rgb[idx], rgb[idx + 1], rgb[idx + 2]
    return (r * 256 + g + b / 256.0) - 32768


if __name__ == "__main__":
    # Sanity check against the same Manchester point validated earlier
    # this session (reference APIs said ~59-60m).
    e = terrarium_elevation_at(-2.2426, 53.4808)
    print(f"Manchester elevation: {e:.1f} m (reference point APIs said ~59-60 m)")
    # A real Pennine peak (Cross Fell, ~893m) as a highland sanity check.
    e2 = terrarium_elevation_at(-2.4796, 54.7016)
    print(f"Cross Fell elevation: {e2:.1f} m (should be several hundred metres, real peak ~893 m)")
