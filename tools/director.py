"""Pure-Python Macromedia Director 4 (RIFX/XFIR MV93) asset decoder."""

from __future__ import annotations

import os
import struct
import wave
from collections import deque
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

from PIL import Image

# Standard Macintosh 8-bit System Palette (index 0 = white, index 255 = black)
def _build_mac_system_palette() -> List[Tuple[int, int, int]]:
    pal: List[Tuple[int, int, int]] = []
    # 6x6x6 color cube (indices 0..215, descending from 255 to 0)
    steps = [255, 204, 153, 102, 51, 0]
    for r in steps:
        for g in steps:
            for b in steps:
                pal.append((r, g, b))
    # Remove duplicate black at 215 and fill ramps (approx Mac 256 CLUT)
    pal = pal[:215]
    ramp_vals = [238, 221, 187, 170, 136, 119, 85, 68, 34, 17]
    for v in ramp_vals:
        pal.append((v, 0, 0))
    for v in ramp_vals:
        pal.append((0, v, 0))
    for v in ramp_vals:
        pal.append((0, 0, v))
    for v in ramp_vals:
        pal.append((v, v, v))
    pal.append((0, 0, 0))
    assert len(pal) == 256
    return pal


MAC_SYSTEM_PALETTE = _build_mac_system_palette()

CAST_TYPE_NAMES = {
    1: "bitmap",
    2: "filmloop",
    3: "text",
    4: "palette",
    5: "picture",
    6: "sound",
    7: "button",
    8: "shape",
    9: "movie",
    10: "digital_video",
    11: "script",
}


def decode_packbits(src: bytes, expected_len: int) -> bytes:
    """Decode Mac PackBits RLE used by Director 4 BITD chunks."""
    if len(src) == expected_len:
        return src
    out = bytearray()
    i = 0
    n = len(src)
    while i < n and len(out) < expected_len:
        b = src[i]
        i += 1
        if b <= 127:
            cnt = b + 1
            out.extend(src[i : i + cnt])
            i += cnt
        elif b >= 129:
            cnt = 257 - b
            if i < n:
                out.extend(bytes([src[i]]) * cnt)
                i += 1
        # b == 128 is a no-op
    if len(out) < expected_len:
        out.extend(b"\x00" * (expected_len - len(out)))
    return bytes(out[:expected_len])


def parse_clut(raw: bytes) -> List[Tuple[int, int, int]]:
    """Parse a Director 4 CLUT chunk (256 x 6-byte big-endian RGB16)."""
    pal: List[Tuple[int, int, int]] = []
    count = min(256, len(raw) // 6)
    for i in range(count):
        r16, g16, b16 = struct.unpack(">HHH", raw[i * 6 : i * 6 + 6])
        pal.append((r16 >> 8, g16 >> 8, b16 >> 8))
    while len(pal) < 256:
        pal.append((0, 0, 0))
    return pal


def parse_mac_snd(raw: bytes) -> Optional[Tuple[int, bytes]]:
    """Decode a Macintosh 'snd ' resource into (sample_rate, pcm_s16le_bytes)."""
    if len(raw) < 20:
        return None
    fmt = struct.unpack(">H", raw[0:2])[0]
    pos = 2
    if fmt == 1:
        num_mods = struct.unpack(">H", raw[pos : pos + 2])[0]
        pos += 2 + num_mods * 6
    elif fmt == 2:
        pos += 2  # refCount
    else:
        return None

    if pos + 2 > len(raw):
        return None
    num_cmds = struct.unpack(">H", raw[pos : pos + 2])[0]
    pos += 2

    hdr_off = None
    for _ in range(num_cmds):
        if pos + 8 > len(raw):
            break
        cmd, p1, p2 = struct.unpack(">HHI", raw[pos : pos + 8])
        pos += 8
        if (cmd & 0x7FFF) in (80, 81):  # soundCmd / bufferCmd
            hdr_off = p2
            break

    if hdr_off is None or hdr_off + 22 > len(raw):
        return None

    rate_fixed = struct.unpack(">I", raw[hdr_off + 8 : hdr_off + 12])[0]
    sample_rate = max(8000, int(round(rate_fixed / 65536.0)))
    encode = raw[hdr_off + 20]

    if encode == 0x00:
        # Standard SoundHeader (8-bit unsigned mono)
        length = struct.unpack(">I", raw[hdr_off + 4 : hdr_off + 8])[0]
        pcm_start = hdr_off + 22
        pcm_u8 = raw[pcm_start : pcm_start + length]
        samples = bytearray(len(pcm_u8) * 2)
        for idx, val in enumerate(pcm_u8):
            s16 = (val - 128) * 256
            struct.pack_into("<h", samples, idx * 2, s16)
        return sample_rate, bytes(samples)

    if encode == 0xFF and hdr_off + 64 <= len(raw):
        # Extended SoundHeader
        channels = struct.unpack(">I", raw[hdr_off + 4 : hdr_off + 8])[0]
        num_frames = struct.unpack(">I", raw[hdr_off + 22 : hdr_off + 26])[0]
        sample_size = struct.unpack(">H", raw[hdr_off + 48 : hdr_off + 50])[0]
        pcm_start = hdr_off + 64
        if sample_size == 8:
            pcm_u8 = raw[pcm_start : pcm_start + num_frames * channels]
            samples = bytearray(len(pcm_u8) * 2)
            for idx, val in enumerate(pcm_u8):
                struct.pack_into("<h", samples, idx * 2, (val - 128) * 256)
            return sample_rate, bytes(samples)
        if sample_size == 16:
            pcm_be = raw[pcm_start : pcm_start + num_frames * channels * 2]
            samples = bytearray(len(pcm_be))
            for idx in range(0, len(pcm_be) - 1, 2):
                samples[idx] = pcm_be[idx + 1]
                samples[idx + 1] = pcm_be[idx]
            return sample_rate, bytes(samples)

    return None


def _lua_quote(s: str) -> str:
    escaped = (
        s.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "")
        .replace("\t", "\\t")
    )
    return f'"{escaped}"'


@dataclass
class ChunkEntry:
    idx: int
    tag: bytes
    offset: int
    size: int


class DirectorMovie:
    """In-memory reader for a Director 4 RIFX/XFIR MV93 movie."""

    def __init__(self, data: bytes, base_delta: int = 0, name: str = "") -> None:
        self.data = data
        self.name = name
        sig = data[:4]
        if sig not in (b"RIFX", b"XFIR"):
            raise ValueError(f"{name}: invalid Director signature {sig!r}")
        self.endian = ">" if sig == b"RIFX" else "<"
        e = self.endian

        imap_mmap = struct.unpack(e + "I", data[24:28])[0]
        mmap_off = imap_mmap + base_delta
        if data[mmap_off : mmap_off + 4] not in (b"mmap", b"pamm"):
            tag = b"mmap" if e == ">" else b"pamm"
            found = data.find(tag)
            if found == -1:
                raise ValueError(f"{name}: mmap chunk not found")
            mmap_off = found
            base_delta = mmap_off - imap_mmap

        hdr_sz, entry_sz, _max_cnt, used_cnt = struct.unpack(
            e + "HHII", data[mmap_off + 8 : mmap_off + 20]
        )

        self.entries: List[ChunkEntry] = []
        self.by_tag: Dict[bytes, List[ChunkEntry]] = {}
        cp = mmap_off + 8 + hdr_sz
        for i in range(used_cnt):
            rec = data[cp : cp + entry_sz]
            ctag = rec[:4] if e == ">" else rec[:4][::-1]
            csz, coff = struct.unpack(e + "II", rec[4:12])
            real_off = coff + (base_delta if i > 1 else 0)
            ce = ChunkEntry(i, ctag, real_off, csz)
            self.entries.append(ce)
            self.by_tag.setdefault(ctag, []).append(ce)
            cp += entry_sz

        # Parse KEY* child chunk relationships
        self.keymap: Dict[Tuple[int, bytes], int] = {}
        if b"KEY*" in self.by_tag:
            kd = self.chunk(self.by_tag[b"KEY*"][0].idx)
            k_hdr, k_ent, _k_max, k_used = struct.unpack(e + "HHII", kd[:12])
            for i in range(k_used):
                off = k_hdr + i * k_ent
                child_id, owner_id = struct.unpack(e + "II", kd[off : off + 8])
                ktag = kd[off + 8 : off + 12] if e == ">" else kd[off + 8 : off + 12][::-1]
                self.keymap[(owner_id, ktag)] = child_id

        # Stage config (VWCF / DRCF) - big-endian internally
        self.stage_w = 640
        self.stage_h = 480
        self.fps = 12
        self.min_cast = 1
        self.max_cast = 0
        cfg_entries = self.by_tag.get(b"DRCF") or self.by_tag.get(b"VWCF")
        if cfg_entries:
            cd = self.chunk(cfg_entries[0].idx)
            top, left, bottom, right = struct.unpack(">hhhh", cd[4:12])
            self.stage_w = right - left
            self.stage_h = bottom - top
            self.min_cast, self.max_cast = struct.unpack(">HH", cd[12:16])
            self.fps = max(1, cd[16])

        # Parse CAS* cast slot table -> chunk idx
        self.cast_slots: Dict[int, int] = {}
        if b"CAS*" in self.by_tag:
            casd = self.chunk(self.by_tag[b"CAS*"][0].idx)
            cnt = len(casd) // 4
            ids = struct.unpack(f">{cnt}I", casd[: cnt * 4])
            for i, cidx in enumerate(ids):
                if cidx != 0:
                    self.cast_slots[self.min_cast + i] = cidx

        # Parse all CLUT palettes by cast slot ID
        self.palettes: Dict[int, List[Tuple[int, int, int]]] = {}
        self.first_palette: Optional[List[Tuple[int, int, int]]] = None
        for cast_id, cidx in sorted(self.cast_slots.items()):
            clut_idx = self.keymap.get((cidx, b"CLUT"))
            if clut_idx is not None:
                pal = parse_clut(self.chunk(clut_idx))
                self.palettes[cast_id] = pal
                if self.first_palette is None:
                    self.first_palette = pal

    def chunk(self, idx: int) -> bytes:
        ce = self.entries[idx]
        return self.data[ce.offset + 8 : ce.offset + 8 + ce.size]

    def parse_labels(self) -> Dict[int, str]:
        labels: Dict[int, str] = {}
        if b"VWLB" not in self.by_tag:
            return labels
        ld = self.chunk(self.by_tag[b"VWLB"][0].idx)
        if len(ld) < 2:
            return labels
        cnt = struct.unpack(">H", ld[:2])[0]
        if len(ld) < 2 + (cnt + 1) * 4:
            return labels
        offs = [struct.unpack(">HH", ld[2 + j * 4 : 6 + j * 4]) for j in range(cnt + 1)]
        str_base = 2 + (cnt + 1) * 4
        for j in range(cnt):
            fr = offs[j][0]
            s_start = str_base + offs[j][1]
            s_end = str_base + offs[j + 1][1]
            lbl = ld[s_start:s_end].decode("mac_roman", "replace").strip()
            if lbl and fr != 65533:
                labels[fr] = lbl
        return labels

    def parse_frames(self) -> List[List[dict]]:
        frames: List[List[dict]] = []
        if b"VWSC" not in self.by_tag:
            return frames
        sc = self.chunk(self.by_tag[b"VWSC"][0].idx)
        if len(sc) < 20:
            return frames
        total_sz = struct.unpack(">I", sc[0:4])[0]
        if total_sz > len(sc) or total_sz < 20:
            total_sz = len(sc)
        fpos = 20
        buf = bytearray(50 * 20)
        while fpos + 2 <= total_sz:
            flen = struct.unpack(">H", sc[fpos : fpos + 2])[0]
            if flen < 2 or fpos + flen > total_sz:
                break
            fend = fpos + flen
            p = fpos + 2
            while p + 4 <= fend:
                clen, coff = struct.unpack(">HH", sc[p : p + 4])
                p += 4
                if coff + clen <= len(buf) and p + clen <= fend:
                    buf[coff : coff + clen] = sc[p : p + clen]
                p += clen
            sprites: List[dict] = []
            for ch in range(48):
                s = buf[(ch + 2) * 20 : (ch + 3) * 20]
                script_id = s[0]
                ink = s[5] & 0x3F
                cast_id, y, x, h, w = struct.unpack(">HhhHH", s[6:16])
                if cast_id != 0:
                    sprites.append(
                        {
                            "ch": ch + 1,
                            "cast": cast_id,
                            "x": x,
                            "y": y,
                            "w": w,
                            "h": h,
                            "ink": ink,
                            "script": script_id,
                        }
                    )
            frames.append(sprites)
            fpos = fend
        return frames

    def resolve_palette(
        self, clut_id: int, shared: Optional["DirectorMovie"] = None
    ) -> List[Tuple[int, int, int]]:
        if clut_id > 0:
            if clut_id in self.palettes:
                return self.palettes[clut_id]
            if shared is not None and clut_id in shared.palettes:
                return shared.palettes[clut_id]
        if self.first_palette is not None:
            return self.first_palette
        if shared is not None and shared.first_palette is not None:
            return shared.first_palette
        return MAC_SYSTEM_PALETTE

    def _decode_bitmap_image(
        self,
        cd: bytes,
        cidx: int,
        ink_mode: str,
        shared: Optional["DirectorMovie"] = None,
    ) -> Optional[Tuple[Image.Image, int, int, int, int]]:
        spec_len = struct.unpack(">H", cd[0:2])[0]
        if len(cd) < 18 or spec_len < 12:
            return None
        pitch = struct.unpack(">H", cd[8:10])[0] & 0x7FFF
        top, left, bottom, right = struct.unpack(">hhhh", cd[10:18])
        w = right - left
        h = bottom - top
        if w <= 0 or h <= 0 or pitch <= 0:
            return None

        if spec_len >= 24 and len(cd) >= 30:
            ry, rx = struct.unpack(">hh", cd[26:30])
            reg_x, reg_y = rx - left, ry - top
        else:
            reg_x, reg_y = 0, 0
        depth = struct.unpack(">H", cd[30:32])[0] if spec_len >= 26 and len(cd) >= 32 else 1
        clut_id = struct.unpack(">h", cd[32:34])[0] if spec_len >= 28 and len(cd) >= 34 else 0

        bitd_idx = self.keymap.get((cidx, b"BITD"))
        if bitd_idx is None:
            return None
        raw_bitd = self.chunk(bitd_idx)
        decoded = decode_packbits(raw_bitd, pitch * h)

        pal = self.resolve_palette(clut_id, shared)
        rgba = bytearray(w * h * 4)

        if depth == 8:
            indices = bytearray(w * h)
            for row in range(h):
                rstart = row * pitch
                row_bytes = decoded[rstart : rstart + w]
                off = row * w
                indices[off : off + len(row_bytes)] = row_bytes
        elif depth == 4:
            indices = bytearray(w * h)
            for row in range(h):
                rstart = row * pitch
                for col in range(w):
                    b = decoded[rstart + (col >> 1)]
                    indices[row * w + col] = (b >> 4) if (col & 1) == 0 else (b & 0x0F)
        elif depth == 2:
            indices = bytearray(w * h)
            for row in range(h):
                rstart = row * pitch
                for col in range(w):
                    b = decoded[rstart + (col >> 2)]
                    shift = 6 - 2 * (col & 3)
                    indices[row * w + col] = (b >> shift) & 0x03
        else:  # 1-bit monochrome (0=white/index 0, 1=black/index 255)
            indices = bytearray(w * h)
            for row in range(h):
                rstart = row * pitch
                for col in range(w):
                    b = decoded[rstart + (col >> 3)]
                    bit = (b >> (7 - (col & 7))) & 1
                    indices[row * w + col] = 255 if bit else 0

        # Compute transparency mask according to Director ink mode
        transparent = bytearray(w * h)
        if ink_mode == "bg_transparent":
            for i, idx in enumerate(indices):
                if idx == 0:
                    transparent[i] = 1
        elif ink_mode == "matte":
            q: deque[int] = deque()
            for x in range(w):
                for p in (x, (h - 1) * w + x):
                    if indices[p] == 0 and not transparent[p]:
                        transparent[p] = 1
                        q.append(p)
            for y in range(h):
                for p in (y * w, y * w + w - 1):
                    if indices[p] == 0 and not transparent[p]:
                        transparent[p] = 1
                        q.append(p)
            while q:
                p = q.popleft()
                py, px = divmod(p, w)
                if px > 0:
                    np = p - 1
                    if indices[np] == 0 and not transparent[np]:
                        transparent[np] = 1
                        q.append(np)
                if px + 1 < w:
                    np = p + 1
                    if indices[np] == 0 and not transparent[np]:
                        transparent[np] = 1
                        q.append(np)
                if py > 0:
                    np = p - w
                    if indices[np] == 0 and not transparent[np]:
                        transparent[np] = 1
                        q.append(np)
                if py + 1 < h:
                    np = p + w
                    if indices[np] == 0 and not transparent[np]:
                        transparent[np] = 1
                        q.append(np)

        if depth == 1:
            for i, idx in enumerate(indices):
                o = i * 4
                v = 0 if idx == 255 else 255
                rgba[o] = v
                rgba[o + 1] = v
                rgba[o + 2] = v
                rgba[o + 3] = 0 if transparent[i] else 255
        else:
            for i, idx in enumerate(indices):
                r, g, b = pal[idx]
                o = i * 4
                rgba[o] = r
                rgba[o + 1] = g
                rgba[o + 2] = b
                rgba[o + 3] = 0 if transparent[i] else 255

        img = Image.frombytes("RGBA", (w, h), bytes(rgba))
        return img, w, h, reg_x, reg_y

    def export(
        self,
        out_dir: str,
        assets_rel_prefix: str,
        shared: Optional["DirectorMovie"] = None,
    ) -> dict:
        """Extract sprites, sounds, text, labels, and score.lua into out_dir."""
        os.makedirs(out_dir, exist_ok=True)
        sprites_dir = os.path.join(out_dir, "sprites")
        sounds_dir = os.path.join(out_dir, "sounds")

        labels = self.parse_labels()
        frames = self.parse_frames()

        # Infer dominant ink per cast member from VWSC
        cast_inks: Dict[int, set] = {}
        for fr in frames:
            for sp in fr:
                cast_inks.setdefault(sp["cast"], set()).add(sp["ink"])

        casts_out: Dict[int, dict] = {}
        sprite_count = 0
        sound_count = 0

        for cast_id, cidx in sorted(self.cast_slots.items()):
            cd = self.chunk(cidx)
            if len(cd) < 7:
                continue
            spec_len = struct.unpack(">H", cd[0:2])[0]
            info_len = struct.unpack(">I", cd[2:6])[0]
            ctype = cd[6]
            cname = ""
            if info_len > 0:
                info = cd[6 + spec_len : 6 + spec_len + info_len]
                if len(info) >= 22:
                    lcnt = struct.unpack(">H", info[20:22])[0]
                    if 22 + (lcnt + 1) * 4 <= len(info):
                        loffs = struct.unpack(f">{lcnt + 1}I", info[22 : 22 + (lcnt + 1) * 4])
                        base = 22 + (lcnt + 1) * 4
                        if lcnt >= 2 and loffs[2] > loffs[1]:
                            rn = info[base + loffs[1] : base + loffs[2]]
                            if rn:
                                cname = rn[1 : 1 + rn[0]].decode("mac_roman", "replace")

            entry: dict = {
                "type": CAST_TYPE_NAMES.get(ctype, f"type_{ctype}"),
                "name": cname,
            }

            if ctype == 1:  # Bitmap
                inks = cast_inks.get(cast_id, set())
                if 36 in inks:
                    ink_mode = "bg_transparent"
                elif 8 in inks:
                    ink_mode = "matte"
                elif 0 in inks:
                    ink_mode = "copy"
                else:
                    # Unreferenced in this movie's VWSC (e.g. SHARED.DXR or swapped cast):
                    # use matte for sprites narrower than full-stage width
                    t, l, b, r = struct.unpack(">hhhh", cd[10:18]) if len(cd) >= 18 else (0, 0, 0, 0)
                    ink_mode = "matte" if (r - l) < 600 else "copy"

                decoded = self._decode_bitmap_image(cd, cidx, ink_mode, shared)
                if decoded is not None:
                    img, w, h, reg_x, reg_y = decoded
                    os.makedirs(sprites_dir, exist_ok=True)
                    fname = f"c_{cast_id}.png"
                    img.save(os.path.join(sprites_dir, fname), optimize=False)
                    entry["image"] = f"{assets_rel_prefix}/sprites/{fname}"
                    entry["w"] = w
                    entry["h"] = h
                    entry["reg_x"] = reg_x
                    entry["reg_y"] = reg_y
                    sprite_count += 1

            elif ctype == 6:  # Sound
                snd_idx = self.keymap.get((cidx, b"snd "))
                if snd_idx is not None:
                    pcm = parse_mac_snd(self.chunk(snd_idx))
                    if pcm is not None:
                        sr, samples = pcm
                        os.makedirs(sounds_dir, exist_ok=True)
                        fname = f"s_{cast_id}.wav"
                        with wave.open(os.path.join(sounds_dir, fname), "wb") as wf:
                            wf.setnchannels(1)
                            wf.setsampwidth(2)
                            wf.setframerate(sr)
                            wf.writeframes(samples)
                        entry["sound"] = f"{assets_rel_prefix}/sounds/{fname}"
                        sound_count += 1

            elif ctype == 3:  # Text
                stxt_idx = self.keymap.get((cidx, b"STXT"))
                if stxt_idx is not None:
                    sd = self.chunk(stxt_idx)
                    if len(sd) >= 12:
                        off_t, txt_len = struct.unpack(">II", sd[0:8])
                        txt = sd[off_t : off_t + txt_len].decode("mac_roman", "replace")
                        entry["text"] = txt.replace("\r", "\n")

            casts_out[cast_id] = entry

        self._write_score_lua(
            os.path.join(out_dir, "score.lua"),
            labels,
            casts_out,
            frames,
        )
        return {
            "sprites": sprite_count,
            "sounds": sound_count,
            "frames": len(frames),
            "labels": len(labels),
        }

    def _write_score_lua(
        self,
        path: str,
        labels: Dict[int, str],
        casts: Dict[int, dict],
        frames: List[List[dict]],
    ) -> None:
        lines: List[str] = [
            "return {",
            f"  stage_w = {self.stage_w},",
            f"  stage_h = {self.stage_h},",
            f"  fps = {self.fps},",
            "  labels = {",
        ]
        for fr, lbl in sorted(labels.items()):
            lines.append(f"    [{fr}] = {_lua_quote(lbl)},")
        lines.append("  },")
        lines.append("  label_frames = {")
        seen_lbls = set()
        for fr, lbl in sorted(labels.items()):
            key = lbl.lower()
            if key not in seen_lbls:
                seen_lbls.add(key)
                lines.append(f"    [{_lua_quote(key)}] = {fr},")
        lines.append("  },")
        lines.append("  casts = {")
        for cid, info in sorted(casts.items()):
            parts = [f"type = {_lua_quote(info['type'])}"]
            if info.get("name"):
                parts.append(f"name = {_lua_quote(info['name'])}")
            if "image" in info:
                parts.append(f"image = {_lua_quote(info['image'])}")
                parts.append(f"w = {info['w']}")
                parts.append(f"h = {info['h']}")
                parts.append(f"reg_x = {info['reg_x']}")
                parts.append(f"reg_y = {info['reg_y']}")
            if "sound" in info:
                parts.append(f"sound = {_lua_quote(info['sound'])}")
            if "text" in info:
                parts.append(f"text = {_lua_quote(info['text'])}")
            lines.append(f"    [{cid}] = {{ {', '.join(parts)} }},")
        lines.append("  },")
        lines.append("  frames = {")
        for fidx, fr in enumerate(frames, start=1):
            sp_strs = []
            for sp in fr:
                sp_strs.append(
                    f"{{ch={sp['ch']},cast={sp['cast']},x={sp['x']},y={sp['y']},w={sp['w']},h={sp['h']},ink={sp['ink']}}}"
                )
            lines.append(f"    [{fidx}] = {{{','.join(sp_strs)}}},")
        lines.append("  },")
        lines.append("}")
        with open(path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")


def load_dxr(path: str) -> DirectorMovie:
    with open(path, "rb") as f:
        data = f.read()
    return DirectorMovie(data, base_delta=0, name=os.path.basename(path))


def load_projector_movies(exe_path: str) -> List[DirectorMovie]:
    with open(exe_path, "rb") as f:
        data = f.read()
    movies: List[DirectorMovie] = []
    pos = 0
    while True:
        idx = data.find(b"XFIR", pos)
        if idx == -1:
            break
        if data[idx + 8 : idx + 12] == b"39VM":
            msz = struct.unpack("<I", data[idx + 4 : idx + 8])[0]
            slice_data = data[idx : idx + 8 + msz]
            pamm = slice_data.find(b"pamm")
            if pamm != -1:
                imap_mmap = struct.unpack("<I", slice_data[24:28])[0]
                movies.append(
                    DirectorMovie(
                        slice_data,
                        base_delta=pamm - imap_mmap,
                        name=f"{os.path.basename(exe_path)}@{idx}",
                    )
                )
        pos = idx + 4
    return movies
