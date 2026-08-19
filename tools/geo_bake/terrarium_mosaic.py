"""Bulk Terrarium elevation sampling: stitches the z-level tiles covering a
world-space region into one numpy array, so a caller can sample a whole grid
at once.

fetch_terrarium.terrarium_elevation_at() answers ONE point per call in pure
Python. That is right for bake_landcover.py, which samples a few tens of
thousands of points. It is the wrong shape for per-hex relief tiles: 333x333
per hex across the 3,876-hex corridor is ~430 million samples, and at the
~100k samples/sec a per-point Python function manages that is well over an
hour of pure interpreter overhead before any tile is written.

This module inverts the access pattern -- decode each tile once into numpy,
mosaic the tiles a region touches, and let the caller index the result with
vectorised arithmetic. The same tile is usually needed by several adjacent
hexes, so decoded tiles are cached in memory (bounded, see _MAX_CACHED_TILES)
on top of the on-disk PNG cache fetch_terrarium already maintains.

Zoom is a parameter, not a constant, because the right zoom is set by the
output resolution: a bake writing 30 m pixels needs a source finer than 30 m,
which is z12 (~22.5 m/px at GB latitude). fetch_terrarium's own z9 (~180 m/px)
is fine for the coarse whole-corridor raster and far too coarse here.

Terrarium RGB encoding, same as fetch_terrarium documents:
    elevation_metres = (R * 256 + G + B / 256) - 32768
"""

import math
import os
import time
import urllib.error
import urllib.request

import numpy as np

from png_codec import decode_png_rgb8

_CACHE_DIR = os.path.join(os.path.dirname(__file__), "cache", "terrarium")
_TILE_SIZE = 256

## Decoded tiles held in memory. Each is 256x256 float32 = 256 KB, so this is
## a ~256 MB ceiling. Sized to comfortably hold every tile a single hex's
## neighbourhood touches many times over, while never growing unbounded across
## a 3,876-hex run.
_MAX_CACHED_TILES = 1024

_tile_cache: dict[tuple[int, int, int], np.ndarray | None] = {}
_fetch_stats = {"hits": 0, "downloads": 0, "failures": 0}


def lonlat_to_tile_fractional(lon: np.ndarray, lat: np.ndarray, z: int):
    """Vectorised Web-Mercator tile address, kept fractional.

    Returns (x, y) in tile units -- the integer part is the tile index and the
    fraction is the position inside it. Same formula fetch_terrarium uses per
    point; kept in one place conceptually but written for arrays here because
    calling that per-point version 430 million times is exactly the cost this
    module exists to avoid.
    """
    n = 2.0 ** z
    lat_rad = np.radians(lat)
    x = (lon + 180.0) / 360.0 * n
    y = (1.0 - np.log(np.tan(lat_rad) + 1.0 / np.cos(lat_rad)) / math.pi) / 2.0 * n
    return x, y


def _tile_path(z: int, x: int, y: int) -> str:
    return os.path.join(_CACHE_DIR, f"{z}_{x}_{y}.png")


def _load_tile(z: int, x: int, y: int) -> np.ndarray | None:
    """One tile as a 256x256 float32 array of metres, or None if unavailable.

    A failed fetch is cached as None so a tile that genuinely does not exist
    (off the edge of the dataset) is not re-requested once per hex that
    touches it -- the same "cache the miss too" rule
    RealTerrainSampler._fine_tile_for() applies on the Godot side.
    """
    key = (z, x, y)
    if key in _tile_cache:
        _fetch_stats["hits"] += 1
        return _tile_cache[key]

    if len(_tile_cache) >= _MAX_CACHED_TILES:
        _tile_cache.pop(next(iter(_tile_cache)))

    os.makedirs(_CACHE_DIR, exist_ok=True)
    path = _tile_path(z, x, y)
    data = None
    if os.path.exists(path):
        with open(path, "rb") as handle:
            data = handle.read()
    else:
        url = f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                data = response.read()
            with open(path, "wb") as handle:
                handle.write(data)
            _fetch_stats["downloads"] += 1
        except (urllib.error.URLError, OSError, TimeoutError) as exc:
            print(f"  WARN: terrarium {z}/{x}/{y} unavailable: {exc}")
            _fetch_stats["failures"] += 1
            _tile_cache[key] = None
            return None

    width, height, rgb = decode_png_rgb8(data)
    raw = np.frombuffer(rgb, dtype=np.uint8).reshape(height, width, 3).astype(np.float32)
    metres = raw[:, :, 0] * 256.0 + raw[:, :, 1] + raw[:, :, 2] / 256.0 - 32768.0
    _tile_cache[key] = metres
    return metres


def sample_metres(lon: np.ndarray, lat: np.ndarray, z: int) -> np.ndarray:
    """Elevation in metres for arrays of lon/lat, sampled bilinearly at zoom z.

    Bilinear, not nearest: this is the exact interpolation whose ABSENCE
    produced the artefact that started this work. bake_landcover.py sampled
    every 4th pixel and upsampled nearest-neighbour, so its elevation raster
    holds 4x4 blocks of identical values and any gradient operator run over it
    renders those blocks as rectangular terraces across flat ground. Sampling
    a smooth field with nearest-neighbour and then differentiating it is the
    thing to avoid, at any resolution.

    Missing tiles contribute 0.0 (sea level) rather than NaN -- a disclosed
    degradation matching fetch_terrarium's own contract, so one unavailable
    tile leaves a flat patch instead of poisoning the arithmetic downstream.
    """
    tx, ty = lonlat_to_tile_fractional(lon, lat, z)
    # Position in whole-pyramid pixel space, offset by half a pixel so that
    # integer coordinates land on pixel CENTRES rather than corners.
    px = tx * _TILE_SIZE - 0.5
    py = ty * _TILE_SIZE - 0.5
    x0 = np.floor(px).astype(np.int64)
    y0 = np.floor(py).astype(np.int64)
    fx = (px - x0).astype(np.float32)
    fy = (py - y0).astype(np.float32)

    top_left = _gather(x0, y0, z)
    top_right = _gather(x0 + 1, y0, z)
    bottom_left = _gather(x0, y0 + 1, z)
    bottom_right = _gather(x0 + 1, y0 + 1, z)
    top = top_left + (top_right - top_left) * fx
    bottom = bottom_left + (bottom_right - bottom_left) * fx
    return top + (bottom - top) * fy


def _gather(px: np.ndarray, py: np.ndarray, z: int) -> np.ndarray:
    """Elevation at absolute pyramid pixel coordinates, tile lookups batched.

    Grouped by owning tile so each distinct tile is loaded and indexed once
    per call rather than once per sample. np.unique over the tile addresses is
    what makes this O(tiles touched) instead of O(samples).
    """
    out = np.zeros(px.shape, dtype=np.float32)
    n = 2 ** z
    tile_x = np.clip(px // _TILE_SIZE, 0, n - 1)
    tile_y = np.clip(py // _TILE_SIZE, 0, n - 1)
    in_x = np.clip(px - tile_x * _TILE_SIZE, 0, _TILE_SIZE - 1)
    in_y = np.clip(py - tile_y * _TILE_SIZE, 0, _TILE_SIZE - 1)

    addresses = tile_x.astype(np.int64) * (2 ** 32) + tile_y.astype(np.int64)
    for address in np.unique(addresses):
        mask = addresses == address
        tx = int(address // (2 ** 32))
        ty = int(address % (2 ** 32))
        tile = _load_tile(z, tx, ty)
        if tile is None:
            continue
        out[mask] = tile[in_y[mask], in_x[mask]]
    return out


def prefetch(tiles: set[tuple[int, int]], z: int, workers: int = 16) -> None:
    """Downloads every missing tile in `tiles` concurrently, before any baking.

    The bake itself is CPU work on numpy arrays and takes milliseconds per
    hex; measured on one hex, essentially all of the wall-clock went to
    fetching six z12 tiles one at a time at roughly a second each, which
    extrapolated to about four hours for the corridor. The tiles are
    independent public S3 objects, so fetching them serially is latency being
    paid one round trip at a time rather than any real cost.

    Only tiles absent from the on-disk cache are requested, so an interrupted
    run resumes rather than restarting, and a re-bake at the same zoom costs
    no network at all.

    Failures are left for _load_tile() to report and record as a hole; this
    is a warm-up, not a gate.
    """
    from concurrent.futures import ThreadPoolExecutor

    os.makedirs(_CACHE_DIR, exist_ok=True)
    missing = [(x, y) for (x, y) in sorted(tiles) if not os.path.exists(_tile_path(z, x, y))]
    if not missing:
        print(f"  all {len(tiles)} z{z} tiles already cached")
        return

    print(f"  fetching {len(missing)} of {len(tiles)} z{z} tiles with {workers} workers...")
    started = time.time()
    done = 0
    last_print = started

    def fetch_one(address: tuple[int, int]) -> None:
        x, y = address
        url = f"https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
        path = _tile_path(z, x, y)
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                data = response.read()
        except (urllib.error.URLError, OSError, TimeoutError) as exc:
            print(f"  WARN: terrarium {z}/{x}/{y} unavailable: {exc}")
            _fetch_stats["failures"] += 1
            return
        # Written via a temp name then renamed, so an interrupted run can never
        # leave a truncated PNG that a later run would treat as cached.
        tmp = path + ".part"
        with open(tmp, "wb") as handle:
            handle.write(data)
        os.replace(tmp, path)
        _fetch_stats["downloads"] += 1

    with ThreadPoolExecutor(max_workers=workers) as pool:
        for _ in pool.map(fetch_one, missing):
            done += 1
            now = time.time()
            if now - last_print > 15:
                rate = done / max(now - started, 0.001)
                print(f"  {done}/{len(missing)} tiles  {rate:.1f}/s  "
                      f"~{(len(missing) - done) / max(rate, 0.001) / 60:.1f} min left")
                last_print = now
    print(f"  fetched {done} tiles in {(time.time() - started) / 60:.1f} min")


def tiles_covering(lon: np.ndarray, lat: np.ndarray, z: int) -> set[tuple[int, int]]:
    """Tile addresses touched by the given lon/lat samples, including the
    +1 neighbours sample_metres() reads for its bilinear filter."""
    tx, ty = lonlat_to_tile_fractional(np.asarray(lon), np.asarray(lat), z)
    px = tx * _TILE_SIZE - 0.5
    py = ty * _TILE_SIZE - 0.5
    out: set[tuple[int, int]] = set()
    n = 2 ** z
    for dx in (0, 1):
        for dy in (0, 1):
            ix = np.clip((np.floor(px).astype(np.int64) + dx) // _TILE_SIZE, 0, n - 1)
            iy = np.clip((np.floor(py).astype(np.int64) + dy) // _TILE_SIZE, 0, n - 1)
            out.update(zip(ix.ravel().tolist(), iy.ravel().tolist()))
    return out


def stats() -> dict:
    """Fetch counters, for a bake run that wants to report how much of its
    time went to the network versus local decoding."""
    return dict(_fetch_stats)
