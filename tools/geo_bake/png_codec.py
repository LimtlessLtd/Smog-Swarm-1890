"""Minimal stdlib-only PNG decode/encode -- no PIL/Pillow/GDAL available
in this dev environment (confirmed empirically, see MEMORY for the
project this belongs to). Handles exactly the two cases this bake
pipeline needs:

  - decode_png_rgb8(): 8-bit RGB truecolor, non-interlaced (the format
    AWS/Mapzen's public Terrain Tiles ship in). Proven against a real
    fetched tile and cross-checked against two independent reference
    elevation APIs before this module existed (see bake session notes).

  - encode_png_rgb8(): the matching writer for this pipeline's own two
    baked output rasters (landcover.png, elevation.png). Uses filter-
    type-0 (None) for every scanline -- the simplest correct choice.
    This is a one-time offline bake, not a size-critical production
    encoder, and zlib's own LZ77 pass still compresses long uniform
    runs (e.g. ocean) effectively even without adaptive filtering.

Godot needs NONE of this at runtime -- GDScript's Image.load_from_file()
uses Godot's own native, built-in PNG loader. This module is purely a
bake-time (offline Python) concern.
"""

import struct
import zlib

_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def decode_png_rgb8(data: bytes) -> tuple[int, int, bytes]:
    """Returns (width, height, raw RGB8 bytes, row-major, no padding)."""
    assert data[:8] == _PNG_SIGNATURE, "not a PNG"
    pos = 8
    idat = b""
    width = height = None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        ctype = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            width, height, bitdepth, colortype = struct.unpack(">IIBB", chunk[:10])
            assert bitdepth == 8 and colortype == 2, (
                f"only 8-bit RGB truecolor supported, got bitdepth={bitdepth} colortype={colortype}"
            )
        elif ctype == b"IDAT":
            idat += chunk
        elif ctype == b"IEND":
            break
        pos += 8 + length + 4  # length + type + data + crc
    raw = zlib.decompress(idat)
    bpp = 3  # RGB8
    stride = width * bpp
    out = bytearray(height * stride)
    prev_row = bytearray(stride)
    src_pos = 0
    for y in range(height):
        filt = raw[src_pos]
        src_pos += 1
        row = bytearray(raw[src_pos:src_pos + stride])
        src_pos += stride
        cur = bytearray(stride)
        for i in range(stride):
            a = cur[i - bpp] if i >= bpp else 0
            b = prev_row[i]
            c = prev_row[i - bpp] if i >= bpp else 0
            if filt == 0:
                val = row[i]
            elif filt == 1:
                val = (row[i] + a) & 0xFF
            elif filt == 2:
                val = (row[i] + b) & 0xFF
            elif filt == 3:
                val = (row[i] + (a + b) // 2) & 0xFF
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                val = (row[i] + pr) & 0xFF
            else:
                raise ValueError(f"bad filter type {filt}")
            cur[i] = val
        out[y * stride:(y + 1) * stride] = cur
        prev_row = cur
    return width, height, bytes(out)


def _chunk(ctype: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + ctype
        + data
        + struct.pack(">I", zlib.crc32(ctype + data) & 0xFFFFFFFF)
    )


def encode_png_rgb8(width: int, height: int, rgb_bytes: bytes) -> bytes:
    """rgb_bytes must be row-major, 3 bytes/pixel, no padding, len == width*height*3."""
    assert len(rgb_bytes) == width * height * 3, "rgb_bytes size mismatch"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    stride = width * 3
    scanlines = bytearray()
    for y in range(height):
        scanlines.append(0)  # filter type 0 (None) -- see module doc comment
        scanlines += rgb_bytes[y * stride:(y + 1) * stride]
    idat = zlib.compress(bytes(scanlines), level=9)
    return (
        _PNG_SIGNATURE
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", idat)
        + _chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    # Self-test: round-trip a small synthetic image through encode+decode.
    import random

    random.seed(1890)
    w, h = 17, 11  # deliberately non-power-of-2, catches stride bugs
    original = bytes(random.randrange(256) for _ in range(w * h * 3))
    encoded = encode_png_rgb8(w, h, original)
    dw, dh, decoded = decode_png_rgb8(encoded)
    assert (dw, dh) == (w, h), f"size mismatch: {(dw, dh)} != {(w, h)}"
    assert decoded == original, "round-trip byte mismatch"
    print(f"OK: {w}x{h} random RGB8 image round-tripped byte-exact through encode+decode.")
