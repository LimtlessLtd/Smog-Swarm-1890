# Will the baked terrain assets load in an exported build?

`research/` is new as of this note. It is the intended home for investigation write-ups
that are neither a settled decision (`decisions.md`), a spec (`design_doc.md`), nor
completed work (`devlog/`) — findings gathered from sources outside this repo, kept so
the reading is not redone. Nothing here is authoritative over `decisions.md`; when a
finding here settles a design question, fold it there and cite this file.

**Question:** `backlog.md` Now section, *"Relief tiles will not load in an exported
build"* — it says "Verify by exporting, not by reasoning." Exporting was not available
to this investigation. Most of it turned out to be decidable from Godot's own source and
docs; the parts that are not are listed under [Unresolved](#unresolved) with the exact
experiment.

**Engine:** Godot 4.7.1-stable. Every source citation below is from the
`godotengine/godot` tree at tag [`4.7.1-stable`](https://github.com/godotengine/godot/tree/4.7.1-stable)
unless stated. Where behaviour was checked against other 4.x minors that is called out
explicitly.

---

## Verdict

| Asset | Ships in the `.pck`? | Does the current reader find it? | Silent? |
|---|---|---|---|
| `assets/terrain_data/relief/*.png` (3,876) | **Source PNG: no.** `.import` + `.godot/imported/*.ctex`: yes | **No** | **Yes** — silent |
| `assets/terrain_data/fine/*.png` (3,876) | same | **No** | **Yes** — silent |
| `assets/terrain_data/elevation_fine/*.png` (3,876) | same | **No** | **Yes** — silent |
| `assets/terrain_data/landcover.png`, `elevation.png` | same | **No** | **Yes** — silent |
| `assets/terrain_data/zombie_population.zpop` | **Only if `include_filter` covers `*.zpop`** | yes iff shipped | one `push_warning`, then a flat map |
| `assets/terrain_data/mesh/*.tmesh` (300) | **Only if `include_filter` covers `*.tmesh`** | yes iff shipped | **Yes** — silent by design |

**Relief silently disappears on export: yes.** Settled from source, not inferred — see
[§1.1](#11-what-the-exporter-actually-writes-for-a-png-that-has-an-import-sidecar) and
[§1.2](#12-therefore-fileaccessfile_exists-returns-false-in-an-exported-build).

**It is worse than relief.** `backlog.md` frames this as a visual defect. It is not.
`RealTerrainSampler._ensure_loaded()` (`scripts/world/RealTerrainSampler.gd:156-167`)
loads the coarse `landcover.png` / `elevation.png` the same way, and
`RealTerrainSampler.is_available()` is what `HexMapGenerator` branches on
(`scripts/world/generation/HexMapGenerator.gd:141`). In an exported build every
`Image.load()` call site fails its `FileAccess.file_exists()` guard, so
`is_available()` is false and **the entire real-geography derivation falls back to
procedural** — biome, terrain feature, elevation, and everything downstream of
`SubHexTerrainQuery` (pathfinding, portals, boundary blocking, noise propagation,
detail scatter, sea view, terrain mesh view). The exported game would generate a
different, non-British map from the one the editor shows.

**`.zpop` / `.tmesh`: not broken, but not configured.** The mechanism the two doc
comments describe is correct and confirmed against source. It is simply not switched on,
because `export_presets.cfg` does not exist. A one-line `include_filter` fixes both.

**The single highest-value action** is not a code fix: it is
[§4.2](#42-detecting-this-without-a-full-export), a `--export-pack` to a `.zip` that
needs no export templates and produces a plain zip a Python script can assert against.
That turns "verify by exporting" into a gate.

### Confirmed at runtime, 2026-09-07

The reasoning above was from Godot's source. The engine then said it out loud, without
being asked. A headless run of `scenes/test/diagnose_horde_contact.tscn` — an unrelated
gameplay diagnostic — emitted this **2,381 times** during one map generation:

```
WARNING: Loaded resource as image file, this will not work on export:
'res://assets/terrain_data/landcover.png'. Instead, import the image file as
an Image resource and load it normally as a resource.
   at: load (core/io/image.cpp:2770)
```

Backtrace, every time: `_fine_tile_for` -> `sample_at_hex` -> `sample_grid` ->
`majority_biome` -> `_apply_real_terrain` (`HexMapGenerator.gd:141`) -> `generate` ->
`generate_map`. That is exactly the call chain [§1.2](#12-therefore-fileaccessfile_exists-returns-false-in-an-exported-build)
predicts will fail, reached through exactly the branch the Verdict above names as the
worst site. Both `landcover.png` and `elevation.png` appear.

This is the engine's own warning, in this project, on this machine, today — not an
inference. It does not replace the `--export-pack` gate ([§4.2](#42-detecting-this-without-a-full-export)),
which is still the thing that would catch a regression; it removes any remaining doubt
about whether the problem is real.

---

## 1. Imported images loaded by raw path

Three call sites, plus a fourth this brief did not list:

| Call site | Path constant | What it does with the `Image` |
|---|---|---|
| `scripts/world/ReliefTileView.gd:212` `_load_tile()` | `res://assets/terrain_data/relief` | `ImageTexture.create_from_image()` at line 252 — display only, never reads a pixel |
| `scripts/world/RealTerrainSampler.gd:297` `_fine_tile_for()` | `res://assets/terrain_data/fine` | `get_pixelv()` — data only |
| `scripts/world/FineElevationTiles.gd:124` `_tile_for()` | `res://assets/terrain_data/elevation_fine` | `get_pixelv()` — data only |
| **`scripts/world/RealTerrainSampler.gd:156` `_ensure_loaded()`** | `landcover.png`, `elevation.png` | `get_pixelv()` — data only. **Not in the backlog item.** |

All four `.png` trees carry a committed `.import` sidecar: 3,876 in each of `fine`,
`relief`, `elevation_fine` (11,628 total, measured), plus the two coarse rasters.

### 1.1 What the exporter actually writes for a `.png` that has an `.import` sidecar

`EditorExportPlatform::export_project_files()` builds the path set, then loops over it.
For each path it checks for a sidecar:

> `bool has_import_file = FileAccess::exists(path + ".import");`
> — [`editor/export/editor_export_platform.cpp:1525`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/export/editor_export_platform.cpp#L1525)

When the sidecar exists and the importer is neither `"keep"` nor `"skip"`, control
reaches the branch whose own comment states the answer:

> ```cpp
> } else {
>     // File is imported and not customized, replace by what it imports.
>     Vector<String> remaps = config->get_section_keys("remap");
>     ...
>     if (remap == "path") {
>         String remapped_path = config->get_value("remap", remap);
>         Vector<uint8_t> array = FileAccess::get_file_as_bytes(remapped_path);
>         err = save_proxy.save_file(p_preset, p_udata, remapped_path, ...);
>     }
> ```
> — [`editor_export_platform.cpp:1642-1666`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/export/editor_export_platform.cpp#L1642-L1666)

and then writes the rewritten sidecar (with `[deps]` and `[params]` erased):

> `err = save_proxy.save_file(p_preset, p_udata, path + ".import", sarr, ...);`
> — [`editor_export_platform.cpp:1699`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/export/editor_export_platform.cpp#L1699)

There is **no call anywhere in that branch that writes `path` itself**. Two files enter
the pack per tile, and the source PNG is not one of them:

- `res://.godot/imported/100_100.png-b2491f7c….ctex` (the value of `remap/path`)
- `res://assets/terrain_data/fine/100_100.png.import`

The docs state the same thing about the folder involved: the `.ctex`/`.md5` pair lives in
`res://.godot/imported/`, generated per source asset
([`import_process.rst`, "Files generated"](https://github.com/godotengine/godot-docs/blob/master/tutorials/assets_pipeline/import_process.rst)).

**Version check:** this branch is structurally identical in `4.0-stable`, `4.3-stable`,
`4.5-stable` and `4.7.1-stable` (verified by fetching each tag's
`editor_export_platform.cpp` / `editor_export.cpp` and locating the `importer_type ==
"keep"` and "File is imported and not customized" markers). This is not a 4.7 regression.

**An `include_filter` of `*.png` does not change this.** The include filter runs at
[`editor_export_platform.cpp:1370`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/export/editor_export_platform.cpp#L1370),
*before* the loop, and only inserts paths into a `HashSet<String>`. The PNG is already in
that set (it is a normal EditorFileSystem file). The loop then still sees
`has_import_file == true` and still takes the remap branch. **The include filter cannot
override the import remap for a file the importer owns.** This is worth stating plainly
because it is the first thing anyone tries.

### 1.2 Therefore: `FileAccess.file_exists()` returns **false** in an exported build

GDScript's `FileAccess.file_exists()` is bound directly to the C++ `FileAccess::exists`:

> `ClassDB::bind_static_method("FileAccess", D_METHOD("file_exists", "path"), &FileAccess::exists);`
> — [`core/io/file_access.cpp:1074`](https://github.com/godotengine/godot/blob/4.7.1-stable/core/io/file_access.cpp#L1074)

which is exactly two checks:

> ```cpp
> bool FileAccess::exists(const String &p_name) {
>     if (PackedData::get_singleton() && !PackedData::get_singleton()->is_disabled() && PackedData::get_singleton()->has_path(p_name)) {
>         return true;
>     }
>     // Using file_exists because it's faster than trying to open the file.
>     Ref<FileAccess> ret = create_for_path(p_name);
>     return ret->file_exists(p_name);
> }
> ```
> — [`file_access.cpp:54-62`](https://github.com/godotengine/godot/blob/4.7.1-stable/core/io/file_access.cpp#L54-L62)

1. **`PackedData::has_path`** — the pack's directory is built from the pack file's own
   file table, one `add_path()` per entry
   ([`core/io/file_access_pack.cpp:352-371`](https://github.com/godotengine/godot/blob/4.7.1-stable/core/io/file_access_pack.cpp#L352-L371)).
   Per §1.1 the source PNG was never written as an entry, so it is not in the table.
   **False.**
2. **Fallback to the real filesystem.** `create_for_path` returns an
   `ACCESS_RESOURCES` `FileAccess` (`file_access.cpp:68-72`), whose `fix_path` resolves
   `res://` against `ProjectSettings::get_resource_path()`
   ([`file_access.cpp:271-277`](https://github.com/godotengine/godot/blob/4.7.1-stable/core/io/file_access.cpp#L271-L277)).
   On an exported Windows build `resource_path` is left empty — `OS::get_resource_dir()`
   just returns `ProjectSettings::get_resource_path()`
   ([`core/os/os.cpp:357-359`](https://github.com/godotengine/godot/blob/4.7.1-stable/core/os/os.cpp#L357-L359)),
   so the `_setup()` branch that would fill it is skipped
   ([`core/config/project_settings.cpp:678-685`](https://github.com/godotengine/godot/blob/4.7.1-stable/core/config/project_settings.cpp#L678-L685))
   and the exec-relative `.pck` discovery path never sets it
   ([`project_settings.cpp:707-744`](https://github.com/godotengine/godot/blob/4.7.1-stable/core/config/project_settings.cpp#L707-L744)).
   With an empty `resource_path`, `res://x` degrades to the **process-CWD-relative**
   path `x` (`file_access.cpp:276`). In a normal install there is no `assets/` beside
   the exe. **False.**

> **Test-hygiene trap, from that same code.** Because step 2 is CWD-relative, an exported
> exe *launched with the working directory set to this project's source tree* will find
> the real PNGs on disk and appear to work. Any export test must write its output to a
> directory outside `E:\Source\SMOG-SWARM-1890` and be launched from there, or it will
> produce a false pass.

All four call sites treat a `false` here as "no tile" and return without printing
anything: `ReliefTileView.gd:214-216` (`_missing[coord] = true`),
`RealTerrainSampler.gd:302` and `160/164` (leave the `Image` null),
`FineElevationTiles.gd:135` (caches `null`). **The guard is what makes the failure
silent** — see §1.4.

### 1.3 `Image.load()` on a `res://` path in an exported build

`Image::load` is a thin wrapper:

> ```cpp
> Error Image::load(const String &p_path) {
>     String path = ResourceUID::ensure_path(p_path);
> #ifdef DEBUG_ENABLED
>     if (path.begins_with("res://") && ResourceLoader::exists(path)) {
>         WARN_PRINT(vformat("Loaded resource as image file, this will not work on export: '%s'. ..."));
>     }
> #endif
>     return ImageLoader::load_image(path, this);
> }
> ```
> — [`core/io/image.cpp:2766-2774`](https://github.com/godotengine/godot/blob/4.7.1-stable/core/io/image.cpp#L2766-L2774)
> (identical body at `image.cpp:2776-2790` for the static `load_from_file`)

`ImageLoader::load_image` opens the path with `FileAccess::open` and fails there:

> `f = FileAccess::open(file, FileAccess::READ, &err);`
> `ERR_FAIL_COND_V_MSG(f.is_null(), err, vformat("Error opening file '%s'.", file));`
> — [`core/io/image_loader.cpp:90-91`](https://github.com/godotengine/godot/blob/4.7.1-stable/core/io/image_loader.cpp#L90-L91)

`FileAccess::open` tries `PackedData::try_open_path` first and then the real filesystem
([`file_access.cpp:160-185`](https://github.com/godotengine/godot/blob/4.7.1-stable/core/io/file_access.cpp#L160-L185)),
i.e. the same two lookups as §1.2. So **`Image.load()` returns `ERR_FILE_NOT_FOUND` (7)
and prints `Error opening file '…'`.** It never returns a partially-valid image.

Two things follow that matter here:

- **The warning is compiled out of a release export.** It sits inside `#ifdef
  DEBUG_ENABLED` (`image.cpp:2768`). A release-template build prints nothing at all from
  `Image::load`. The warning you see in the editor and in `run_verifications.py` logs is
  the *only* place it appears, and it is a warning about a build you have never made.
- **The one error that would still print never fires**, because all four call sites gate
  on `FileAccess.file_exists()` first (§1.2) and so never reach `Image.load()`. The guard
  converts a loud `ERR_FAIL_COND_V_MSG` into no output.

The class reference says the same in one line:

> "**Warning:** This method should only be used in the editor or in cases when you need
> to load external images at run-time, such as images located at the `user://` directory,
> and may not work in exported projects."
> — [`doc/classes/Image.xml:338`](https://github.com/godotengine/godot/blob/4.7.1-stable/doc/classes/Image.xml#L338)
> ([rendered](https://docs.godotengine.org/en/stable/classes/class_image.html#class-image-method-load))

`SaveLoadManager.get_slot_thumbnail()` (`scripts/persistence/SaveLoadManager.gd:198-209`)
uses `Image.load()` too and is **correct as written** — its paths are `user://`, which is
exactly the case the warning carves out.

### 1.4 The stale comment at `RealTerrainSampler.gd:32`

The comment claims `Image.load_from_file()` "(NOT `load()`/`ResourceLoader`)" is used
deliberately. The code at `RealTerrainSampler.gd:162`, `:166` and `:304` calls
`img.load(path)` — the instance method, not the static one. The comment does not describe
the code.

It also does not change the analysis: `Image::load_from_file` has a byte-identical body
to `Image::load` (`image.cpp:2776-2790`), same `DEBUG_ENABLED` warning, same
`ImageLoader::load_image` call. Both fail identically in an export. The only difference
is that `load_from_file` additionally `ERR_FAIL`s with "Failed to load image. Error %d"
on failure (`image.cpp:2787`), which would at least be visible — but again, the
`file_exists()` guard means it is never reached.

The stated *reason* in that comment — bypassing the import pipeline so classification
bytes are not re-encoded — is a real requirement and is preserved by the fix in §1.5.

### 1.5 The correct 4.x way to read an imported image at runtime

There are two supported routes, and **this project needs both, split by call site.**

#### Route A — `Import As: Image` (the one the warning is telling you to use)

The warning says "import the image file as an Image resource and load it normally as a
resource." That is a literal instruction: Godot ships an importer named `image` whose
output resource type is `Image`.

> ```cpp
> String ResourceImporterImage::get_importer_name() const { return "image"; }
> String ResourceImporterImage::get_visible_name() const { return "Image"; }
> String ResourceImporterImage::get_save_extension() const { return "image"; }
> String ResourceImporterImage::get_resource_type() const { return "Image"; }
> ```
> — [`editor/import/resource_importer_image.cpp:36-54`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/import/resource_importer_image.cpp)

**Its `import()` does not decode or re-encode anything.** It copies the source file's
bytes verbatim behind a 5-byte header:

> ```cpp
> f->get_buffer(data.ptrw(), len);          // whole source file
> f = FileAccess::open(p_save_path + ".image", FileAccess::WRITE);
> const uint8_t header[4] = { 'G', 'D', 'I', 'M' };
> f->store_buffer(header, 4);
> f->store_pascal_string(p_source_file.get_extension().to_lower());
> f->store_buffer(data.ptr(), len);          // ...unchanged
> ```
> — [`resource_importer_image.cpp:71-93`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/import/resource_importer_image.cpp)

and the loader reads that header and hands the bytes to the ordinary PNG decoder:

> — [`core/io/image_resource_format.cpp:33-101`](https://github.com/godotengine/godot/blob/4.7.1-stable/core/io/image_resource_format.cpp)
> (`handles_type("Image")`, extension `"image"`, decodes `GDIM` + pascal-string extension,
> then `ImageLoader::loader[idx]->load_image(image, f)`)

So `ResourceLoader.load("res://assets/terrain_data/fine/100_100.png")` returns an
**`Image`**, decoded from the *unmodified original PNG bytes*. Byte-for-byte identical to
what `Image.load()` returns today. No texture, no GPU, no mipmaps, no compression
setting, no `detect_3d`. The importer has **zero** import options
(`get_import_options()` is empty, `resource_importer_image.cpp:68`), so there is nothing
that can later be flipped to a lossy mode.

The docs describe the type in one sentence, and it is exactly this project's use case:

> "Import the image as-is. This resource type cannot be displayed directly onto 2D or 3D
> nodes, but the pixel values can be queried from a script using `get_pixel`."
> — [Importing images → Changing import type](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html)

The runtime path works in an export because both the rewritten `.import` and the
`.godot/imported/*.image` file are in the pack (§1.1), and `ResourceFormatImporter`
resolves one to the other:

> `Error err = _get_path_and_type(p_path, pat, true);`
> `Ref<Resource> res = ResourceLoader::_load(pat.path, p_path, pat.type, ...);`
> — [`core/io/resource_importer.cpp:174-191`](https://github.com/godotengine/godot/blob/4.7.1-stable/core/io/resource_importer.cpp#L172-L201)

**The existence guard also has an export-safe replacement.** `ResourceLoader.exists(path)`
bottoms out in
> `bool ResourceFormatImporter::recognize_path(...) const { return FileAccess::exists(p_path + ".import"); }`
> `bool ResourceFormatImporter::exists(const String &p_path) const { return FileAccess::exists(p_path + ".import"); }`
> — [`resource_importer.cpp:247-253`](https://github.com/godotengine/godot/blob/4.7.1-stable/core/io/resource_importer.cpp#L247-L253)

and the `.import` **is** in the pack, so `ResourceLoader.exists()` is true in an exported
build for exactly the tiles that were baked, and false for the rest. It is a drop-in for
the current `FileAccess.file_exists()` guard with the same semantics and no per-tile cost
beyond a `PackedData` hash lookup. (This is already the convention elsewhere in the repo:
`BuildingVisuals.gd:199`, `WallVisuals.gd:238`, `PropVisuals.gd:39`, `UnitVisuals.gd:94`
all gate on `ResourceLoader.exists()`.)

Applies to: `RealTerrainSampler` (`fine/`, `landcover.png`, `elevation.png`) and
`FineElevationTiles` (`elevation_fine/`) — 7,754 files.

#### Route B — `ResourceLoader.load()` → `CompressedTexture2D`, for display only

`ReliefTileView` never reads a pixel; it converts straight to an `ImageTexture`
(`ReliefTileView.gd:252`) and assigns it to `Polygon2D.texture`. With the existing
`importer="texture"` sidecars, `ResourceLoader.load(path)` in an exported build returns a
`CompressedTexture2D` (the `type` recorded in every relief `.import`), which **is** a
`Texture2D` and can be assigned to `polygon.texture` directly. That removes a CPU PNG
decode and an `ImageTexture` upload per tile rather than adding work.

The relief tiles' `.import` files carry `compress/mode=0` (Lossless). That path stores
WebP-lossless (or PNG) and preserves the source `Image::Format` field verbatim:

> ```cpp
> case COMPRESS_LOSSLESS: {
>     bool use_webp = !lossless_force_png && p_image->get_width() <= 16383 && ...;
>     f->store_32(use_webp ? CompressedTexture2D::DATA_FORMAT_WEBP : ...DATA_FORMAT_PNG);
>     ... f->store_32(p_image->get_format());
>     data = Image::webp_lossless_packer(...);
> ```
> — [`editor/import/resource_importer_texture.cpp:272-298`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/import/resource_importer_texture.cpp#L272-L298)

and `_webp_packer` with `p_lossless = true` keeps an alpha-free image as `FORMAT_RGB8`
([`modules/webp/webp_common.cpp:54-70`](https://github.com/godotengine/godot/blob/4.7.1-stable/modules/webp/webp_common.cpp#L54-L70)).
Measured on this repo's own imported cache: `relief/100_100.png` is 11,436 B on disk and
its `.ctex` is 9,238 B — smaller, and lossless.

**Do NOT use Route B to get pixel data back.** `CompressedTexture2D` has no
`get_image()` of its own; it inherits `Texture2D.get_image()`, which is a **GPU
read-back**:

> `Ref<Image> CompressedTexture2D::get_image() const { ... return RS::get_singleton()->texture_2d_get(texture); }`
> — [`scene/resources/compressed_texture.cpp:243-249`](https://github.com/godotengine/godot/blob/4.7.1-stable/scene/resources/compressed_texture.cpp#L243-L249)

and in the GL Compatibility driver this project uses (`project.godot`
`renderer/rendering_method="gl_compatibility"`) the CPU-side shortcut is editor-only:

> ```cpp
> #ifdef TOOLS_ENABLED
>     if (texture->image_cache_2d.is_valid() && !texture->is_render_target) {
>         return texture->image_cache_2d;
>     }
> #endif
> ```
> — [`drivers/gles3/storage/texture_storage.cpp:1519-1523`](https://github.com/godotengine/godot/blob/4.7.1-stable/drivers/gles3/storage/texture_storage.cpp#L1515-L1523)

In an exported build it always goes to the GPU. On desktop native GL it is a
`glGetTexImage` and exact (`texture_storage.cpp:1527-1566`). On the non-`is_gles_over_gl`
path — web, mobile, and Windows when ANGLE is in use — it **renders the texture through
`CopyEffects::copy_to_rect()` into an RGBA8 FBO and `glReadPixels` it back**
(`texture_storage.cpp:1569-1631`). That is a shader blit, and elevation bytes whose exact
values are the data must not travel through one. Route A avoids the question entirely.

### 1.6 Making Godot ship the ORIGINAL file

Three candidate routes; only one works, and it is the wrong trade at this scale.

**`Keep File (exported as is)` — works, but destroys the assets as far as the editor is
concerned.** The Import dock writes a two-line sidecar:

> ```cpp
> config->clear();
> if (params->skip) { config->set_value("remap", "importer", "skip"); }
> else               { config->set_value("remap", "importer", "keep"); }
> ```
> — [`editor/docks/import_dock.cpp:680-690`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/docks/import_dock.cpp#L680-L690)

and the exporter special-cases it before the remap branch:

> ```cpp
> if (importer_type == "keep") {
>     // Just keep file as-is.
>     Vector<uint8_t> array = FileAccess::get_file_as_bytes(path);
>     err = save_proxy.save_file(p_preset, p_udata, path, array, ...);
>     continue;
> }
> ```
> — [`editor_export_platform.cpp:1587-1597`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/export/editor_export_platform.cpp#L1587-L1597)

Docs: *"Select `Keep File (exported as is)` as resource type to skip file import, files
with this resource type will be preserved as is during project export."*
([`import_process.rst:131-132`](https://github.com/godotengine/godot-docs/blob/master/tutorials/assets_pipeline/import_process.rst))

Cost at this scale: `.pck` grows by the full **268 MB** of source PNG (measured: `fine`
19.4 MB, `relief` 147.4 MB, `elevation_fine` 101.4 MB) with no compressed variant, and
`ReliefTileView` loses the ability to load a tile as a texture at all — a `keep` file has
no resource type, so `ResourceLoader.load()` fails on it. It also leaves 11,628
`Image.load()` calls in place, i.e. the fix would work but the code would still be the
thing the engine warns about. **Not recommended.** Route A is smaller (`.image` = source
bytes + 5, so 121 MB for the two data trees) *and* keeps the relief tiles compressible.

> Note for whoever fixes this: with `importer="keep"`, `ResourceLoader::exists()` still
> returns true (it only checks that a `.import` exists — `resource_importer.cpp:247`), so
> the `image.cpp:2769` warning **would keep firing even though the code now works.** The
> warning is not a reliable pass/fail signal after a `keep` fix.

**`Skip File (not exported)`** is the opposite: `importer="skip"` makes the export loop
`continue` before anything is written (`editor_export_platform.cpp:1537-1540`). Never
useful here.

**`.gdignore` does the opposite of what it is usually suggested for.** A `.gdignore` in a
directory makes `EditorFileSystem::_should_skip_directory()` return true
([`editor/file_system/editor_file_system.cpp:3502-3505`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/file_system/editor_file_system.cpp#L3488-L3508)),
which removes the directory from the EditorFileSystem scan — and, critically, **also from
the include-filter walk**, which calls the same predicate before recursing:

> ```cpp
> if (EditorFileSystem::_should_skip_directory(cur_dir + dir)) { continue; }
> ```
> — [`editor_export_platform.cpp:729`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/export/editor_export_platform.cpp#L723-L736)

So the widely-repeated recipe "`.gdignore` the folder, then add an `include_filter`" does
**not** work in 4.x: the filter walk cannot see inside an ignored directory. The docs say
the same outcome in plain words: *"Ignoring a folder also results in its contents not
being exported with the project, therefore reducing the exported PCK size."*
([`import_process.rst`, "Ignoring specific folders"](https://github.com/godotengine/godot-docs/blob/master/tutorials/assets_pipeline/import_process.rst)).
Same code in `4.0-stable` (line 424) through `4.7.1-stable` (line 729).

The only `.gdignore`-based route that could work is to *also* rename the extension so the
importer does not claim the file (e.g. `100_100.bin`) — at which point you have hand-built
Route A badly.

### 1.7 Landmine to fix while you are in there: `detect_3d/compress_to=1`

Every one of the 11,628 sidecars currently has `compress/mode=0` (Lossless) **and**
`detect_3d/compress_to=1`. If any of these textures is ever assigned into a 3D material,
the editor rewrites the sidecar behind your back:

> ```cpp
> if (E.value.flags & MAKE_3D_FLAG && bool(cf->get_value("params", "detect_3d/compress_to"))) {
>     cf->set_value("params", "detect_3d/compress_to", 0);
>     if (compress_to == 1) { cf->set_value("params", "compress/mode", COMPRESS_VRAM_COMPRESSED); ... }
>     cf->set_value("params", "mipmaps/generate", true);
> ```
> — [`resource_importer_texture.cpp:125-147`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/import/resource_importer_texture.cpp#L125-L147)

VRAM compression is block-lossy. On a Terrarium-packed elevation tile
(`metres = r*256 + g + b/256 - 32768`) that is not a quality regression, it is corrupt
data — and it would arrive as a 3,876-file diff nobody asked for. Route A removes the
risk for the two data trees (the `image` importer has no such option); for `relief/`,
set `detect_3d/compress_to=0` explicitly.

---

## 2. Raw binary that is not a resource

`ZombiePopulationData.gd:61` (`res://assets/terrain_data/zombie_population.zpop`,
110,296 B) and `TerrainMeshChunkData.gd:47`
(`res://assets/terrain_data/mesh/`, **300 `.tmesh` files, 64.2 MB, all tracked in git** —
the directory is not empty; the brief's `assets/terrain_data/chunks` path does not exist).

### 2.1 How a file with an unrecognised extension gets into the pack

**It cannot get in via the resource walk.** `EditorFileSystem` refuses to record a file
whose extension is not in `valid_extensions`:

> ```cpp
> String ext = f.get_extension().to_lower();
> if (!valid_extensions.has(ext)) {
>     continue; //invalid
> }
> ```
> — [`editor_file_system.cpp:1512-1515`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/file_system/editor_file_system.cpp#L1511-L1516)

and `valid_extensions` is built from the registered resource loaders plus two editor
settings ([`editor_file_system.cpp:3743-3777`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/file_system/editor_file_system.cpp#L3743-L3777)),
whose defaults are:

> `_initial_set("docks/filesystem/textfile_extensions", "txt,md,cfg,ini,log,json,yml,yaml,toml,xml");`
> `_initial_set("docks/filesystem/other_file_extensions", "ico,icns");`
> — [`editor/settings/editor_settings.cpp:717-718`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/settings/editor_settings.cpp#L717-L718)

`zpop` and `tmesh` are in neither list, so `_export_find_resources()`
(`editor_export_platform.cpp:639-650`), which iterates the EditorFileSystem, never sees
them — regardless of which `export_filter` mode the preset uses.

**The include filter is a separate, filesystem-level walk, and it is the only way in.**

> ```cpp
> _edit_filter_list(paths, p_preset->get_include_filter(), false);
> _edit_filter_list(paths, p_preset->get_exclude_filter(), true);
> ```
> — [`editor_export_platform.cpp:1370-1371`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/export/editor_export_platform.cpp#L1370-L1371)

`_edit_filter_list` splits the string on **commas** (`strip_edges()` per entry, empties
dropped) and walks `DirAccess::ACCESS_RESOURCES` from `res://`, matching each file with
`String::matchn()` against both the full `res://…` path and the path with the prefix
stripped:

> ```cpp
> Vector<String> split = p_filter.split(",");
> ... String f = split[i].strip_edges(); ... filters.push_back(f);
> ```
> — [`editor_export_platform.cpp:739-756`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/export/editor_export_platform.cpp#L739-L756)
> ```cpp
> // Test also against path without res:// so that filters like `file.txt` can work.
> if (fullpath.matchn(p_filters[i]) || fullpath_no_prefix.matchn(p_filters[i])) { r_list.insert(fullpath); }
> ```
> — [`editor_export_platform.cpp:705-716`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/export/editor_export_platform.cpp#L691-L737)

So the syntax the doc comments guess at is correct: **`include_filter="*.zpop, *.tmesh"`**
(commas, whitespace tolerated, glob).

Once in `paths`, the file has no `.import`, so the export loop takes the plain branch:

> ```cpp
> } else {
>     // Just store it as it comes.
>     String export_path;
>     if (type.is_empty()) { export_path = path; }
>     ...
>     Vector<uint8_t> array = FileAccess::get_file_as_bytes(export_path);
>     err = save_proxy.save_file(p_preset, p_udata, export_path, array, ...);
> ```
> — [`editor_export_platform.cpp:1706-1728`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/export/editor_export_platform.cpp#L1706-L1728)

`ResourceLoader::get_resource_type()` returns `""` for `.zpop`/`.tmesh`, so
`export_path == path` and the bytes are stored verbatim at their `res://` path. At
runtime `FileAccess.file_exists()` hits `PackedData::has_path` and returns true, and
`FileAccess.open()` returns a `FileAccessPack`
(`file_access.cpp:164-171` → `PackedSourcePCK::get_file`, `file_access_pack.cpp:376`).
**The two doc comments are accurate.**

Two limits on the include filter worth knowing:

- **It cannot reach into a dot-directory.** `_edit_files_with_filter` skips any subdir
  starting with `.` (`editor_export_platform.cpp:725-727`), and the docs state it as a
  rule: *"Files and folders whose name begin with a period will never be included in the
  exported project."*
  ([`exporting_projects.rst`](https://github.com/godotengine/godot-docs/blob/master/tutorials/export/exporting_projects.rst))
- **It cannot reach into a `.gdignore`d directory** — §1.6.

### 2.2 `.gitattributes` has no bearing on export. None.

`*.tmesh binary` and `*.zpop binary` in `.gitattributes` are instructions to **git**
about diffing and end-of-line conversion on checkout. Godot's exporter never reads
`.gitattributes`; nothing in `editor_export_platform.cpp` or `editor_file_system.cpp`
references it. The `binary` attribute is still doing real work — it is what stops a
CRLF conversion from corrupting a `.tmesh` on a Windows checkout, which is exactly what
the two comments in `.gitattributes` claim — but it has zero effect on whether the file
reaches the `.pck`. Stated explicitly here because "it's marked binary" reads like an
export-relevant fact and is not one.

### 2.3 Failure modes if the include filter is missing

**`.zpop`** — `_ensure_loaded()` takes the `file_exists` branch at
`ZombiePopulationData.gd:122`:

```gdscript
if not FileAccess.file_exists(DATA_PATH):
    push_warning("ZombiePopulationData: %s is missing — every hex falls back to the floor. ...")
    return
```

so it is a `push_warning`, **not** the `push_error` at line 127 (that one only fires when
the file exists but cannot be opened — unreachable in this scenario). `_capacity` stays
empty, `is_available()` returns false, `population_floor()` returns `FALLBACK_FLOOR`, and
`capacity_for()` returns 0 for every hex. `HexMapGenerator` then applies the 1,000 floor
map-wide. Per `decisions.md` D3 capacity **is** the difficulty curve, so the effect is
that London and a Highland hex become equally hard: one warning in a log no player reads,
and a flat game. Call it visible-in-principle, silent-in-practice.

**`.tmesh`** — `TerrainMeshChunkData.load_chunk()` returns `null` at line 62-63 with no
output, which is correct and documented behaviour ("A missing chunk is an ordinary 'not
baked here' case … so it prints nothing"). That deliberate silence is exactly what makes
"the whole directory is absent" indistinguishable from "nothing baked here". **Fully
silent.**

---

## 3. Fix options, weighed at the real scale

Measured inputs: 3,876 files × 3 trees + 2 coarse rasters = 11,630 PNGs / 268.2 MB;
10.5 MB of `.import` sidecars; 300 `.tmesh` / 64.2 MB; one 110 KB `.zpop`.
The repo's `.godot/imported/` currently holds 25,741 `.ctex` (952 MB) — more than the
11,630 live imports, i.e. it contains stale output from earlier bakes. Only `.ctex` files
named by a live `.import`'s `remap/path` are exported
(`editor_export_platform.cpp:1663-1666`), so the strays cost disk locally and nothing in
the pack.

| Option | Code change | `.pck` cost | Byte-exact? | Notes |
|---|---|---|---|---|
| **A. `importer="image"` for the two data trees + the two coarse rasters; `ResourceLoader.load()` → `Image`; guard on `ResourceLoader.exists()`** | 3 functions (`RealTerrainSampler._ensure_loaded`, `._fine_tile_for`, `FineElevationTiles._tile_for`) | 121 MB (source bytes + 5/file) | **Yes**, byte-identical (§1.5) | Requires rewriting 7,754 sidecars + a reimport. No import options exist to regress. |
| **B. `ResourceLoader.load()` → `CompressedTexture2D` straight onto `Polygon2D.texture` for `relief/`** | 1 function (`ReliefTileView._load_tile`), and it gets *shorter* | ~119 MB (WebP-lossless; 9,238 B vs 11,436 B measured on one tile) | Lossless, and irrelevant — display only | Also set `detect_3d/compress_to=0` (§1.7). Removes a per-tile CPU decode + upload. |
| **C. `Keep File` on all 11,628** | none | 268 MB, uncompressed | Yes | Leaves the warned-about API in place; breaks Route B for relief. Rejected. |
| **D. `.gdignore`** | n/a | −268 MB | n/a | Ships *nothing*. Does the opposite of the goal (§1.6). Rejected. |
| **E. Include filter for `*.zpop, *.tmesh`** | none | 64.3 MB | Yes | Required regardless of which of A–D is chosen. One line of `export_presets.cfg`. |

**Recommended: A + B + E.** They are independent and can land separately, but the backlog
item is right that the three image readers should move together — leaving one on
`Image.load()` leaves the shared cause in place and the remaining warning looks like
noise. Note A must also cover `RealTerrainSampler._ensure_loaded()` (the coarse
`landcover.png` / `elevation.png`), which the backlog item does not currently list and
which is the highest-impact of the four (§Verdict).

Mechanically, A is a sidecar rewrite: for each of the 7,754 files replace the `[remap]`
`importer`/`type`/`path` with `importer="image"` / `type="Image"`, drop `[deps]` and
`[params]`, and let the editor reimport (it regenerates `path` and `uid` on scan). Doing
it by hand in the Import dock is possible — the dock supports multi-select reimport —
but a script over the `.import` files is the reproducible route, and belongs next to
`tools/geo_bake/` since the bake is what produces the files.

---

## 4. Getting from "nobody has ever exported this" to a gate

### 4.1 A minimal `export_presets.cfg`

`export_presets.cfg` is gitignored (`.gitignore:4`) and absent. `EditorExport::load_presets`
reads these keys with **no default**, so all of them must be present or the load prints
errors: `platform`, `export_filter`, `include_filter`, `exclude_filter`
([`editor/export/editor_export.cpp:303-380`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/export/editor_export.cpp#L296-L381)).
The accepted `export_filter` string values are `all_resources`, `scenes`, `resources`,
`exclude`, `customized` (`editor_export.cpp:345-364`). The Windows platform's name is the
literal string the preset must match:

> `platform->set_name("Windows Desktop");`
> — [`platform/windows/export/export.cpp:55`](https://github.com/godotengine/godot/blob/4.7.1-stable/platform/windows/export/export.cpp#L55)

confirmed by the docs' own CLI example, `godot --export-pack "Windows Desktop" some_name.pck`
([`exporting_projects.rst`, "Exporting from the command line"](https://github.com/godotengine/godot-docs/blob/master/tutorials/export/exporting_projects.rst)).

The minimum this project needs (NOT written by this investigation — `export_presets.cfg`
stays uncreated per the brief):

```ini
[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.zpop, *.tmesh"
exclude_filter=""
export_path=""
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.0.options]
```

`[preset.0.options]` may be empty: every platform option is materialised with its default
by `EditorExportPlatform::create_preset()` (`editor_export_platform.cpp:616-637`) before
the cfg is read. Credentials go to `.godot/export_credentials.cfg`
(`editor_export.cpp:120`) which is already gitignored via `.godot/`.

### 4.2 Detecting this WITHOUT a full export

**Yes, and it needs no export templates.** `--export-pack` exists in 4.7:

> `print_help_option("--export-pack <preset> <path>", "Export the project data only using the given preset and output path. The <path> extension determines whether it will be in PCK or ZIP format.\n", CLI_OPTION_AVAILABILITY_EDITOR);`
> — [`main/main.cpp:705`](https://github.com/godotengine/godot/blob/4.7.1-stable/main/main.cpp#L705)

and the pack-only branch **skips the `can_export()` template check entirely** — that
check only runs in the `else` ("Normal project export") arm:

> ```cpp
> if (export_defer.pack_only) { // Only export .pck or .zip data pack.
>     if (export_path.ends_with(".zip"))      { err = platform->export_zip(export_preset, ...); }
>     else if (export_path.ends_with(".pck")) { err = platform->export_pack(export_preset, ...); }
> } else { // Normal project export.
>     if (!platform->can_export(export_preset, config_error, missing_templates, ...)) { ... }
> ```
> — [`editor/editor_node.cpp:1377-1406`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/editor_node.cpp#L1377-L1406)

Neither `export_pack` nor `export_zip` is overridden by the PC platform
(`editor/export/editor_export_platform_pc.h` declares only `get_name`/`get_os_name`), so
both go to the base `save_pack` / `save_zip`.

**Export to `.zip`, not `.pck`.** The zip writer stores each entry at its `res://` path
with the prefix stripped:

> `const String path = simplify_path(p_path).replace_first("res://", "");`
> — [`editor_export_platform.cpp:548`](https://github.com/godotengine/godot/blob/4.7.1-stable/editor/export/editor_export_platform.cpp#L545-L566)

so the result is a plain deflate zip readable by `python -m zipfile -l` or `zipfile.ZipFile`
— no need to parse the PCK's V3/V4 directory format
(`file_access_pack.cpp:287-371`), which is versioned and would be a maintenance liability
in a CI script.

Exact invocation (writing **outside** the project tree, per the §1.2 trap):

```
"E:\Program Files\GoDot\Godot_v4.7.1-stable_win64_console.exe" --headless \
  --path "E:\Source\SMOG-SWARM-1890" \
  --export-pack "Windows Desktop" "C:\Temp\smog_export_check.zip"
```

Then assert, in a new `tools/ci/check_export_pack.py`:

| Must be present | Why |
|---|---|
| `assets/terrain_data/zombie_population.zpop` | §2.1 — proves the include filter is live |
| `assets/terrain_data/mesh/chunk_*.tmesh` (300) | same |
| `assets/terrain_data/relief/0_0.png.import` (or any) **and** a matching `.godot/imported/*.ctex` | proves the tiles are reachable as *resources* |
| after the fix: `.godot/imported/*.image` for `fine/` and `elevation_fine/` | proves Route A landed |

| Must be ABSENT (today) | Why |
|---|---|
| `assets/terrain_data/relief/*.png` (the source) | this is the whole bug; a green assertion here is the regression test |

The first run of this on the current tree is the experiment `backlog.md` asks for, and it
is cheap enough to sit in `tools/ci/` beside `check_gdscript.py` and
`run_verifications.py`. Note it depends on `export_presets.cfg`, which is gitignored — so
either un-ignore it (the docs say it "can be safely committed to version control. There
is nothing in here that you would normally have to keep secret" —
[`exporting_projects.rst`, "Configuration files"](https://github.com/godotengine/godot-docs/blob/master/tutorials/export/exporting_projects.rst))
or have the CI script write a throwaway one. Un-ignoring is the better call; the current
`.gitignore` line is Godot's stock template, not a decision this project made.

**A cheaper, zero-export tripwire** that catches regressions between full checks: a rule
in `check_gdscript.py` that fails on `Image.load(` / `Image.load_from_file(` /
`.load(` on an `Image` where the argument literal starts with `res://`. The one
legitimate exception in the repo is `SaveLoadManager.get_slot_thumbnail()`, whose path is
`user://` — so the rule can be "res:// literal only" with no allowlist.

---

## Unresolved

Everything above is settled from source. These are not, and each names its experiment.

1. **Whether `--export-pack` actually completes on this project with no export templates
   installed.** The code path bypasses `can_export()` (§4.2) and I could find no other
   template dependency in `save_zip`/`export_project_files`, but I could not run it.
   *Experiment:* the §4.2 command. If it fails, the message will name what it wanted.

2. **First-import cost on a clean clone.** Export reads bytes out of `.godot/imported/`
   (`editor_export_platform.cpp:1665`), and `EditorNode` waits for the first scan before
   exporting (`editor_node.cpp:1337`, *"It's important to wait for the first scan to
   finish; otherwise, scripts or resources might not be imported"*). On a machine without
   a warm `.godot/`, that is 11,630 texture imports before the export starts. This repo's
   cache is 952 MB, so the number is not small. *Experiment:* time
   `--headless --import` on a fresh clone. Relevant to whether §4.2 can be a per-PR gate
   or must be nightly.

3. **Reimport cost and correctness of flipping 7,754 sidecars to `importer="image"`.**
   The importer's `import()` is a file copy (§1.5), so it should be I/O-bound and fast,
   but "should" is what this document exists to avoid. *Experiment:* rewrite the sidecars
   for one directory, `--headless --import`, then diff `Image.load()` output against
   `ResourceLoader.load()` output pixel-for-pixel in a `verify_*.gd`. That verification is
   itself worth committing — it is the thing that proves Route A is byte-exact on this
   project's actual data rather than in principle.

4. **Whether a `CompressedTexture2D` on `Polygon2D` renders identically to the current
   `ImageTexture`.** Texture filter and repeat are `CanvasItem` properties in Godot 4, not
   texture properties, so there should be no difference — but relief is a `[visual]`
   concern and `CLAUDE.md` §0.1 is explicit that visual work is not gated by reasoning.
   *Experiment:* `smoke_screenshot.tscn` before/after, at the framing that shows relief.

5. **Runtime memory at 3,876 live `CompressedTexture2D`.** `ReliefTileView` caps at
   `MAX_TILES_IN_VIEW = 96` and frees the `Polygon2D`, but `ResourceLoader`'s cache and
   the GPU-resident textures are a different accounting than the current
   decode-and-discard `Image`. *Experiment:* `Performance.get_monitor(RENDER_TEXTURE_MEM_USED)`
   across a fast pan, before and after.

6. **Whether Windows falls back to ANGLE on the target machines.** Only matters if
   someone later reaches for `Texture2D.get_image()`; the recommendation in §1.5 avoids
   it. Recorded so it is not rediscovered: the two GL read-back paths in
   `texture_storage.cpp:1526` vs `:1569` are not equivalent, and the second one is a
   shader blit.
