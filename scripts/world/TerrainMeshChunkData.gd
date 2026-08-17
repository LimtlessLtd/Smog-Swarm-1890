class_name TerrainMeshChunkData
extends RefCounted

## One baked terrain mesh chunk, decoded. Pure data: no rendering, no
## querying, no dependencies.
##
## Read side of tools/geo_bake/vector_mesh_format.py. That file and this one
## repeat the layout table below deliberately -- a silent disagreement decodes
## as garbage geometry rather than an error, so both sides state the format
## and must change in lockstep.
##
## Little-endian throughout, matching PackedByteArray's decode_* helpers.
##
##   off  size  type     field
##     0     4  bytes    magic "TMSH"
##     4     2  uint16   format version (= 1)
##     6     2  uint16   class_count -- distinct biome codes present, informational
##     8     4  float32  origin_x, chunk's world-space origin
##    12     4  float32  origin_y
##    16     4  float32  quant -- world units per quantization step
##    20     4  uint32   vert_count
##    24     4  uint32   tri_count
##    28     4  uint32   reserved (= 0)
##    32        vert_count * 4   uint16 qx, uint16 qy per vertex
##           tri_count  * 6   uint16 i0, i1, i2 per triangle
##           tri_count  * 1   uint8 biome code per triangle
##
## Vertices arrive quantized as integer steps from the chunk origin and are
## expanded to world space on load (origin + q * quant), so callers never see
## the quantization.
##
## `triangle_biomes` holds the bake's own biome CODES, not GameEnums.BiomeType
## ordinals -- the same "decoupled from GameEnums, append-only" contract
## bake_landcover.py's _BIOME_CODE documents and RealTerrainSampler's
## _BIOME_BY_CODE already indexes into. Use RealTerrainSampler.biome_from_code()
## to convert; mapping it here would be a second, divergeable copy of that table.

## "TMSH". A plain int Array, not a PackedByteArray — GDScript rejects
## `PackedByteArray([...])` in a const as "not a constant expression".
const MAGIC: Array[int] = [0x54, 0x4D, 0x53, 0x48]
const SUPPORTED_VERSION: int = 1
const HEADER_SIZE: int = 32

## Directory holding chunk_<x>_<y>.tmesh. These are raw binary, not Godot
## resources, so an exported build only ships them if the export preset's
## non-resource include filter covers *.tmesh.
const CHUNK_DIR: String = "res://assets/terrain_data/mesh/"

var origin: Vector2  ## Chunk's world-space origin (its minimum corner).
var quant: float  ## World units per quantization step, as baked.
var vertices: PackedVector2Array  ## World-space, absolute (origin already applied).
var indices: PackedInt32Array  ## 3 per triangle, into `vertices`.
var triangle_biomes: PackedByteArray  ## One bake biome code per triangle.


## Loads chunk (chunk_x, chunk_y), or null if it wasn't baked or is malformed.
## A missing chunk is an ordinary "not baked here" case (the bake writes
## nothing where there's no geometry), so it prints nothing; a chunk that
## exists but fails to decode is a real fault and pushes an error.
static func load_chunk(chunk_x: int, chunk_y: int) -> TerrainMeshChunkData:
	var path := "%schunk_%d_%d.tmesh" % [CHUNK_DIR, chunk_x, chunk_y]
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("TerrainMeshChunkData: cannot open %s (error %d)" % [path, FileAccess.get_open_error()])
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return from_bytes(bytes, path)


## Decodes a chunk blob. `source` names the origin for error messages only.
static func from_bytes(bytes: PackedByteArray, source: String = "<bytes>") -> TerrainMeshChunkData:
	if bytes.size() < HEADER_SIZE:
		push_error("TerrainMeshChunkData: %s is %d bytes, shorter than the %d-byte header" % [source, bytes.size(), HEADER_SIZE])
		return null
	for i in 4:
		if bytes[i] != MAGIC[i]:
			push_error("TerrainMeshChunkData: %s has bad magic, expected \"TMSH\"" % source)
			return null

	var version := bytes.decode_u16(4)
	if version != SUPPORTED_VERSION:
		push_error("TerrainMeshChunkData: %s is format version %d, this build reads %d" % [source, version, SUPPORTED_VERSION])
		return null

	var data := TerrainMeshChunkData.new()
	data.origin = Vector2(bytes.decode_float(8), bytes.decode_float(12))
	data.quant = bytes.decode_float(16)
	var vert_count := bytes.decode_u32(20)
	var tri_count := bytes.decode_u32(24)

	# Validate the declared sizes against the real file BEFORE indexing
	# anything, so a truncated chunk is one error rather than a decode running
	# off the end of the buffer.
	var expected := HEADER_SIZE + vert_count * 4 + tri_count * 6 + tri_count
	if bytes.size() != expected:
		push_error("TerrainMeshChunkData: %s is %d bytes but its header implies %d (%d verts, %d tris)" % [source, bytes.size(), expected, vert_count, tri_count])
		return null

	data.vertices.resize(vert_count)
	var off := HEADER_SIZE
	for i in vert_count:
		data.vertices[i] = data.origin + Vector2(
			float(bytes.decode_u16(off)) * data.quant,
			float(bytes.decode_u16(off + 2)) * data.quant)
		off += 4

	data.indices.resize(tri_count * 3)
	for i in tri_count * 3:
		var index := bytes.decode_u16(off)
		if index >= vert_count:
			push_error("TerrainMeshChunkData: %s index %d at triangle %d is out of range (%d verts)" % [source, index, i / 3, vert_count])
			return null
		data.indices[i] = index
		off += 2

	data.triangle_biomes = bytes.slice(off, off + tri_count)
	return data


## Chunk-grid address containing `world_pos`. Must match
## bake_vector_landcover.CHUNK_SIZE_WU; the bake names its files from exactly
## this division.
const CHUNK_SIZE_WU: float = 4096.0

static func chunk_address(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(world_pos.x / CHUNK_SIZE_WU)), int(floor(world_pos.y / CHUNK_SIZE_WU)))


func triangle_count() -> int:
	return triangle_biomes.size()


## World-space corners of triangle `tri_index`.
func triangle_points(tri_index: int) -> PackedVector2Array:
	var base := tri_index * 3
	return PackedVector2Array([
		vertices[indices[base]],
		vertices[indices[base + 1]],
		vertices[indices[base + 2]],
	])
