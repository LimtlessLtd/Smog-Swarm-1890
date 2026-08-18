"""Binary wire format for one baked terrain mesh chunk (.tmesh).

Write side. The read side is TerrainMeshChunkData.gd
(scripts/world/TerrainMeshChunkData.gd) and MUST be changed in lockstep --
both files repeat the layout table below, deliberately, because a silent
disagreement between them decodes as garbage geometry rather than an error.

Little-endian throughout (Godot's PackedByteArray decode_* helpers are
little-endian, and every platform this ships to is).

  off  size  type     field
    0     4  bytes    magic "TMSH"
    4     2  uint16   format version (= 1)
    6     2  uint16   class_count -- distinct biome codes present, informational
    8     4  float32  origin_x, chunk's world-space origin
   12     4  float32  origin_y
   16     4  float32  quant -- world units per quantization step
   20     4  uint32   vert_count
   24     4  uint32   tri_count
   28     4  uint32   reserved (= 0)
   32        vert_count * 4   uint16 qx, uint16 qy per vertex
          tri_count  * 6   uint16 i0, i1, i2 per triangle
          tri_count  * 1   uint8 biome code per triangle

World position of vertex i: (origin_x + qx*quant, origin_y + qy*quant).

Quantized coordinates are uint16, so a chunk may span at most
65535 * quant world units. bake_vector_landcover.py asserts its
CHUNK_SIZE_WU / QUANT_WU stays inside that; a larger chunk needs a format
version bump to uint32, not a silently truncated coordinate.

Triangle indices are uint16 for the same reason -- a chunk may hold at most
65536 vertices. Measured on the densest chunk in the baked corridor
(Manchester city centre, 4096 world units square): 20,389 vertices. The
bake refuses to emit a chunk that exceeds the limit rather than wrapping.

Biome codes are bake_landcover._BIOME_CODE's values verbatim -- the same
append-only, "decoupled from GameEnums ordinals" contract that file already
documents, and the same numbering RealTerrainSampler._BIOME_BY_CODE indexes
into. Reusing it means the vector mesh and the existing rasters cannot
disagree about what code 7 means.
"""

import struct

MAGIC = b"TMSH"
VERSION = 1
HEADER_SIZE = 32

MAX_QUANT_STEPS = 65535  # uint16 coordinate range
MAX_VERTS = 65536        # uint16 index range


class ChunkTooLargeError(ValueError):
    """A chunk exceeded the uint16 vertex or coordinate range. Raised rather
    than wrapping, which would decode as geometry folded back on itself."""


def encode_chunk(origin_x: float, origin_y: float, quant: float,
                 verts: list[tuple[int, int]], tris: list[tuple[int, int, int]],
                 tri_classes: list[int]) -> bytes:
    """Serialize one chunk. `verts` are ALREADY-quantized integer steps
    relative to (origin_x, origin_y); quantization is the caller's job
    because the bake snaps geometry to the same grid during the overlay
    (shapely set_precision) and re-deriving it here could disagree.
    """
    if len(tris) != len(tri_classes):
        raise ValueError(f"{len(tris)} triangles but {len(tri_classes)} class codes")
    if len(verts) > MAX_VERTS:
        raise ChunkTooLargeError(f"{len(verts)} vertices exceeds uint16 index range ({MAX_VERTS})")
    for qx, qy in verts:
        if not (0 <= qx <= MAX_QUANT_STEPS and 0 <= qy <= MAX_QUANT_STEPS):
            raise ChunkTooLargeError(
                f"quantized vertex ({qx},{qy}) outside uint16 range -- chunk spans more than "
                f"{MAX_QUANT_STEPS} * quant world units")

    out = bytearray()
    out += MAGIC
    out += struct.pack("<HH", VERSION, len(set(tri_classes)))
    out += struct.pack("<fff", origin_x, origin_y, quant)
    out += struct.pack("<III", len(verts), len(tris), 0)
    assert len(out) == HEADER_SIZE, f"header is {len(out)} bytes, format says {HEADER_SIZE}"

    for qx, qy in verts:
        out += struct.pack("<HH", qx, qy)
    for i0, i1, i2 in tris:
        out += struct.pack("<HHH", i0, i1, i2)
    out += bytes(tri_classes)
    return bytes(out)


def decode_chunk(data: bytes) -> dict:
    """Read a chunk back. Exists so the bake can round-trip its own output as
    a self-check without depending on the Godot side being wired up yet --
    a format bug found here is one that would otherwise surface as
    unexplained geometry in-engine.
    """
    if data[:4] != MAGIC:
        raise ValueError(f"bad magic {data[:4]!r}, expected {MAGIC!r}")
    version, class_count = struct.unpack_from("<HH", data, 4)
    if version != VERSION:
        raise ValueError(f"format version {version}, this build writes/reads {VERSION}")
    origin_x, origin_y, quant = struct.unpack_from("<fff", data, 8)
    vert_count, tri_count, _reserved = struct.unpack_from("<III", data, 20)

    expected = HEADER_SIZE + vert_count * 4 + tri_count * 6 + tri_count
    if len(data) != expected:
        raise ValueError(f"{len(data)} bytes but header implies {expected}")

    off = HEADER_SIZE
    verts = [struct.unpack_from("<HH", data, off + i * 4) for i in range(vert_count)]
    off += vert_count * 4
    tris = [struct.unpack_from("<HHH", data, off + i * 6) for i in range(tri_count)]
    off += tri_count * 6
    tri_classes = list(data[off:off + tri_count])

    return {
        "version": version, "class_count": class_count,
        "origin": (origin_x, origin_y), "quant": quant,
        "verts": verts, "tris": tris, "tri_classes": tri_classes,
    }


def chunk_filename(chunk_x: int, chunk_y: int) -> str:
    return f"chunk_{chunk_x}_{chunk_y}.tmesh"
