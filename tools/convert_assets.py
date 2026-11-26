#!/usr/bin/env python3
"""Local asset conversion pipeline for Help! Muizen in 't hotel.

Converts original Director 4 (.DXR/.EXE), QuickTime (.MOV), AIFF/WAV audio,
and BMP images into LÖVE-ready assets + assets/manifest.lua.
"""

from __future__ import annotations

import argparse
import bisect
import hashlib
import io
import os
import re
import shutil
import struct
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Dict, List, Tuple

from PIL import Image, ImageChops

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from director import DirectorMovie, load_dxr, load_projector_movies


def normalize_key(name: str) -> str:
    stem = os.path.splitext(name)[0].lower()
    key = re.sub(r"[^a-z0-9_]+", "_", stem).strip("_")
    return key or "unnamed"


def index_source_files(source_dir: Path) -> Dict[str, Path]:
    """Build a case-insensitive relative-path -> actual Path map."""
    index: Dict[str, Path] = {}
    for root, _, files in os.walk(source_dir):
        for fn in files:
            p = Path(root) / fn
            rel = p.relative_to(source_dir).as_posix().lower()
            index[rel] = p
    return index


def convert_bmp(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(src) as im:
        if im.mode in ("P", "L", "RGB", "RGBA"):
            im.save(dst, "PNG", optimize=True)
        else:
            im.convert("RGB").save(dst, "PNG", optimize=True)


def convert_audio(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg",
        "-y",
        "-v",
        "error",
        "-i",
        str(src),
        "-ac",
        "1",
        "-ar",
        "22050",
        "-c:a",
        "libmp3lame",
        "-q:a",
        "5",
        str(dst),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"ffmpeg audio failed for {src}: {res.stderr}")


def probe_mov(src: Path) -> dict:
    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-show_entries",
        "stream=codec_type,width,height,r_frame_rate,duration",
        "-of",
        "default=noprint_wrappers=1",
        str(src),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    info = {"width": 640, "height": 480, "fps": 12.0, "duration": 0.0, "has_audio": False}
    cur_type = None
    for line in res.stdout.splitlines():
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        if k == "codec_type":
            cur_type = v
            if v == "audio":
                info["has_audio"] = True
        elif cur_type == "video":
            if k == "width":
                info["width"] = int(v)
            elif k == "height":
                info["height"] = int(v)
            elif k == "r_frame_rate" and "/" in v:
                num, den = v.split("/", 1)
                if int(den) > 0:
                    info["fps"] = round(int(num) / int(den), 3)
            elif k == "duration" and v != "N/A":
                info["duration"] = float(v)
    return info


def _encode_opaque_png(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def _iter_qt_boxes(buf: bytes, start: int, end: int):
    pos = start
    while pos + 8 <= end:
        sz, tag = struct.unpack(">I4s", buf[pos : pos + 8])
        hdr = 8
        if sz == 0:
            sz = end - pos
        elif sz == 1:
            if pos + 16 > end:
                break
            sz = struct.unpack(">Q", buf[pos + 8 : pos + 16])[0]
            hdr = 16
        if sz < hdr or pos + sz > end:
            break
        yield tag, pos + hdr, pos + sz
        pos += sz


def extract_mov_palettes(src: Path):
    """Parse QuickTime stsd/stsc/stts tables when a pal8 .MOV switches palettes mid-video."""
    data = src.read_bytes()
    video_mdia = None
    for tag, s, e in _iter_qt_boxes(data, 0, len(data)):
        if tag != b"moov":
            continue
        for t2, s2, e2 in _iter_qt_boxes(data, s, e):
            if t2 != b"trak":
                continue
            for t3, s3, e3 in _iter_qt_boxes(data, s2, e2):
                if t3 != b"mdia":
                    continue
                for t4, s4, e4 in _iter_qt_boxes(data, s3, e3):
                    if t4 == b"minf":
                        for t5, _, _ in _iter_qt_boxes(data, s4, e4):
                            if t5 == b"vmhd":
                                video_mdia = (s3, e3)
                                break
                if video_mdia:
                    break
            if video_mdia:
                break
        if video_mdia:
            break

    if not video_mdia:
        return None

    timescale = 600
    stbl_range = None
    for tag, s, e in _iter_qt_boxes(data, video_mdia[0], video_mdia[1]):
        if tag == b"mdhd" and s + 16 <= e:
            ver = data[s]
            if ver == 0 and s + 16 <= e:
                timescale = struct.unpack(">I", data[s + 12 : s + 16])[0] or 600
            elif ver == 1 and s + 24 <= e:
                timescale = struct.unpack(">I", data[s + 20 : s + 24])[0] or 600
        elif tag == b"minf":
            for t2, s2, e2 in _iter_qt_boxes(data, s, e):
                if t2 == b"stbl":
                    stbl_range = (s2, e2)
                    break

    if not stbl_range:
        return None

    palettes: Dict[int, List[int]] = {}
    stsc_entries: List[Tuple[int, int, int]] = []
    stts_entries: List[Tuple[int, int]] = []
    chunk_count = 0

    for tag, s, e in _iter_qt_boxes(data, stbl_range[0], stbl_range[1]):
        if tag == b"stsd" and s + 8 <= e:
            count = struct.unpack(">I", data[s + 4 : s + 8])[0]
            ep = s + 8
            for idx_entry in range(1, count + 1):
                if ep + 8 > e:
                    break
                esize = struct.unpack(">I", data[ep : ep + 4])[0]
                if esize < 8 or ep + esize > e:
                    break
                if esize >= 94:
                    _depth, ctab_id = struct.unpack(">Hh", data[ep + 82 : ep + 86])
                    if ctab_id == 0:
                        _seed, flags, csize = struct.unpack(">IHH", data[ep + 86 : ep + 94])
                        pal = [0] * 768
                        for ci in range(csize + 1):
                            off = ep + 94 + ci * 8
                            if off + 8 > ep + esize:
                                break
                            val, r, g, b = struct.unpack(">HHHH", data[off : off + 8])
                            pal_idx = val if (flags & 0x8000) == 0 else ci
                            if 0 <= pal_idx < 256:
                                pal[pal_idx * 3 : pal_idx * 3 + 3] = [r >> 8, g >> 8, b >> 8]
                        palettes[idx_entry] = pal
                ep += esize
        elif tag == b"stsc" and s + 8 <= e:
            n = struct.unpack(">I", data[s + 4 : s + 8])[0]
            for i in range(n):
                off = s + 8 + i * 12
                if off + 12 <= e:
                    stsc_entries.append(struct.unpack(">III", data[off : off + 12]))
        elif tag == b"stts" and s + 8 <= e:
            n = struct.unpack(">I", data[s + 4 : s + 8])[0]
            for i in range(n):
                off = s + 8 + i * 8
                if off + 8 <= e:
                    stts_entries.append(struct.unpack(">II", data[off : off + 8]))
        elif tag in (b"stco", b"co64") and s + 8 <= e:
            chunk_count = struct.unpack(">I", data[s + 4 : s + 8])[0]

    if len(palettes) <= 1 or not stsc_entries or chunk_count <= 0:
        return None

    sample_sdi: List[int] = []
    for i, (first_chunk, spc, sdi) in enumerate(stsc_entries):
        end_chunk = (stsc_entries[i + 1][0] - 1) if (i + 1 < len(stsc_entries)) else chunk_count
        end_chunk = min(end_chunk, chunk_count)
        for _ in range(max(0, end_chunk - first_chunk + 1)):
            sample_sdi.extend([sdi] * spc)

    if not sample_sdi:
        return None

    sample_times: List[float] = []
    t_ticks = 0
    for cnt, delta in stts_entries:
        for _ in range(cnt):
            sample_times.append(t_ticks / timescale)
            t_ticks += delta

    return palettes, sample_sdi, sample_times


def _encode_delta_patch(
    im_p: Image.Image,
    prev_rgb: Image.Image,
    cur_rgb: Image.Image,
    bbox: Tuple[int, int, int, int],
) -> bytes:
    crop_p = im_p.crop(bbox)
    crop_p.info.pop("transparency", None)
    opaque_data = _encode_opaque_png(crop_p)

    diff_crop = ImageChops.difference(cur_rgb.crop(bbox), prev_rgb.crop(bbox))
    r, g, b = diff_crop.split()
    mask = ImageChops.lighter(ImageChops.lighter(r, g), b).point(lambda v: 255 if v else 0)

    hist = crop_p.histogram()
    used = [i for i, c in enumerate(hist) if c > 0]
    pal = im_p.getpalette()
    if len(used) > 255 or not pal:
        return opaque_data

    lut = [0] * 256
    out_pal = [0, 0, 0]
    for new_idx, old_idx in enumerate(used, start=1):
        lut[old_idx] = new_idx
        out_pal.extend(pal[old_idx * 3 : old_idx * 3 + 3])

    remapped = crop_p.point(lut)
    zeros = Image.new("P", crop_p.size, 0)
    masked = Image.composite(remapped, zeros, mask)
    masked.putpalette(out_pal)

    buf = io.BytesIO()
    masked.save(buf, "PNG", transparency=0, optimize=True)
    masked_data = buf.getvalue()
    return masked_data if len(masked_data) < len(opaque_data) else opaque_data


def convert_video(src: Path, out_dir: Path, rel_dir: str) -> dict:
    """Extract frames as lossless palette PNG *delta patches* plus a frame step index.

    The original QuickTime clips are 8-bit palettized (smc/pal8) cel animations: most
    frames are held or only change a small region. We store, per change, only the bounding
    rectangle of changed pixels with unchanged pixels masked transparent (first frame is
    a full opaque patch). Identical patches are stored once and composited onto a canvas.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    meta = probe_mov(src)
    fps = meta["fps"] or 12.0

    for old in list(out_dir.glob("f_*.*")) + list(out_dir.glob("p_*.*")) + list(out_dir.glob("raw_*.*")):
        old.unlink()

    cmd_frames = [
        "ffmpeg", "-y", "-v", "error", "-i", str(src),
        "-vf", f"fps={fps}", "-pix_fmt", "pal8", "-compression_level", "1",
        str(out_dir / "raw_%05d.png"),
    ]
    res = subprocess.run(cmd_frames, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"ffmpeg video frames failed for {src}: {res.stderr}")

    mov_pals = extract_mov_palettes(src)
    raw_files = sorted(out_dir.glob("raw_*.png"))
    patches: List[Tuple[int, int]] = []
    patch_ids: Dict[Tuple[int, int, str], int] = {}
    steps: List[int] = []
    prev_rgb: Image.Image | None = None
    for frame_idx, raw in enumerate(raw_files):
        with Image.open(raw) as im:
            im.load()
        raw.unlink()
        im.info.pop("transparency", None)
        if mov_pals is not None and im.mode == "P":
            palettes, sample_sdi, sample_times = mov_pals
            if len(raw_files) == len(sample_sdi):
                sample_idx = frame_idx
            elif sample_times:
                sample_idx = max(
                    0,
                    min(len(sample_sdi) - 1, bisect.bisect_right(sample_times, (frame_idx / fps) + 1e-6) - 1),
                )
            else:
                sample_idx = min(frame_idx, len(sample_sdi) - 1)
            pal = palettes.get(sample_sdi[sample_idx])
            if pal is not None:
                im.putpalette(pal)
        rgb = im.convert("RGB")
        if prev_rgb is None:
            bbox = (0, 0, im.width, im.height)
            data = _encode_opaque_png(im)
        else:
            bbox = ImageChops.difference(rgb, prev_rgb).getbbox()
            if not bbox:
                prev_rgb = rgb
                steps.append(0)
                continue
            data = _encode_delta_patch(im, prev_rgb, rgb, bbox)
        prev_rgb = rgb
        key = (bbox[0], bbox[1], hashlib.sha1(data).hexdigest())
        pid = patch_ids.get(key)
        if pid is None:
            pid = len(patches) + 1
            patch_ids[key] = pid
            patches.append((bbox[0], bbox[1]))
            (out_dir / f"p_{pid:04d}.png").write_bytes(data)
        steps.append(pid)

    frame_count = len(steps)
    index_rel = f"{rel_dir}/frames.lua"
    (out_dir / "frames.lua").write_text(
        "return {\n  version = 2,\n"
        + "  patches = {" + ",".join(f"{{{x},{y}}}" for x, y in patches) + "},\n"
        + "  steps = {" + ",".join(str(s) for s in steps) + "},\n}\n",
        encoding="utf-8",
    )
    audio_rel = None
    if meta["has_audio"]:
        audio_path = out_dir / "audio.mp3"
        cmd_audio = [
            "ffmpeg",
            "-y",
            "-v",
            "error",
            "-i",
            str(src),
            "-vn",
            "-c:a",
            "libmp3lame",
            "-q:a",
            "4",
            str(audio_path),
        ]
        res_a = subprocess.run(cmd_audio, capture_output=True, text=True)
        if res_a.returncode != 0:
            raise RuntimeError(f"ffmpeg video audio failed for {src}: {res_a.stderr}")
        audio_rel = f"{rel_dir}/audio.mp3"

    return {
        "dir": rel_dir,
        "pattern": f"{rel_dir}/p_%04d.png",
        "audio": audio_rel,
        "fps": fps,
        "frames": frame_count,
        "width": meta["width"],
        "height": meta["height"],
        "duration": meta["duration"] if meta["duration"] > 0 else round(frame_count / fps, 3),
        "unique": len(patches),
        "index": index_rel,
    }


def parse_build_txt(path: Path) -> List[str]:
    text = path.read_text(encoding="latin1")
    items: List[str] = []
    for raw in re.split(r"[\r\n]+", text):
        raw = raw.strip()
        if raw:
            items.append(re.sub(r"^\d+", "", raw).lower())
    return items


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_manifest(out_dir: Path, manifest: dict) -> None:
    lines: List[str] = ["return {"]

    lines.append("  images = {")
    for k, v in sorted(manifest["images"].items()):
        lines.append(f"    [{lua_str(k)}] = {lua_str(v)},")
    lines.append("  },")

    lines.append("  audio = {")
    for group, items in sorted(manifest["audio"].items()):
        lines.append(f"    [{lua_str(group)}] = {{")
        for k, v in sorted(items.items()):
            lines.append(f"      [{lua_str(k)}] = {lua_str(v)},")
        lines.append("    },")
    lines.append("  },")

    lines.append("  videos = {")
    for k, v in sorted(manifest["videos"].items()):
        aud = lua_str(v["audio"]) if v["audio"] else "nil"
        extra = ""
        if v.get("index"):
            extra = f", unique={v['unique']}, index={lua_str(v['index'])}"
        lines.append(
            f"    [{lua_str(k)}] = {{ dir={lua_str(v['dir'])}, pattern={lua_str(v['pattern'])}, "
            f"audio={aud}, fps={v['fps']}, frames={v['frames']}, "
            f"width={v['width']}, height={v['height']}, duration={v['duration']}{extra} }},"
        )
    lines.append("  },")

    lines.append("  dxr = {")
    for k, v in sorted(manifest["dxr"].items()):
        lines.append(f"    [{lua_str(k)}] = {lua_str(v)},")
    lines.append("  },")

    lines.append("  music_builds = {")
    for k, arr in sorted(manifest["music_builds"].items()):
        items = ", ".join(lua_str(x) for x in arr)
        lines.append(f"    [{lua_str(k)}] = {{ {items} }},")
    lines.append("  },")

    lines.append("}")
    (out_dir / "manifest.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert Help! Muizen in 't hotel assets for LÖVE.")
    parser.add_argument("--source", default="backup/extracted", help="Path to extracted original game files")
    parser.add_argument("--output", default="assets", help="Output assets directory")
    parser.add_argument("--workers", type=int, default=os.cpu_count() or 4, help="Parallel worker threads")
    parser.add_argument("--skip-videos", action="store_true", help="Skip .MOV frame extraction")
    parser.add_argument("--only-dxr", action="store_true", help="Only re-export DXR/EXE scores & sprites")
    args = parser.parse_args()

    src_root = Path(args.source)
    out_root = Path(args.output)
    if not src_root.is_dir():
        print(f"Error: source directory not found: {src_root}", file=sys.stderr)
        return 1

    t0 = time.time()
    files = index_source_files(src_root)
    print(f"Indexed {len(files)} files from {src_root}")

    if out_root.exists():
        clean_subs = ("dxr",) if args.only_dxr else (("images", "audio", "dxr") if args.skip_videos else ("images", "audio", "videos", "dxr"))
        for sub in clean_subs:
            sp = out_root / sub
            if sp.exists():
                shutil.rmtree(sp)
    out_root.mkdir(parents=True, exist_ok=True)

    manifest: dict = {
        "images": {},
        "audio": {},
        "videos": {},
        "dxr": {},
        "music_builds": {},
    }

    # If preserving existing videos or non-dxr sections, recover their manifest metadata from disk
    manifest_path = out_root / "manifest.lua"
    if (args.only_dxr or args.skip_videos) and manifest_path.is_file():
        prev_txt = manifest_path.read_text(encoding="utf-8")
        if args.only_dxr:
            for k, v in re.findall(r'\["([^"]+)"\] = "([^"]+)"', prev_txt.split("  images = {")[1].split("  },")[0]):
                manifest["images"][k] = v
            aud_sec = prev_txt.split("  audio = {")[1].split("  },\n  videos = {")[0]
            cur_g = None
            for line in aud_sec.splitlines():
                gm = re.match(r'\s*\["([^"]+)"\] = \{', line)
                if gm:
                    cur_g = gm.group(1)
                    manifest["audio"][cur_g] = {}
                elif cur_g:
                    am = re.match(r'\s*\["([^"]+)"\] = "([^"]+)"', line)
                    if am:
                        manifest["audio"][cur_g][am.group(1)] = am.group(2)
        vid_sec = prev_txt.split("  videos = {")[1].split("  },\n  dxr = {")[0]
        for line in vid_sec.splitlines():
            vm = re.match(
                r'\s*\["([^"]+)"\] = \{ dir="([^"]+)", pattern="([^"]+)", audio=("([^"]+)"|nil), '
                r'fps=([0-9.]+), frames=(\d+), width=(\d+), height=(\d+), duration=([0-9.]+)'
                r'(?:, unique=(\d+), index="([^"]+)")? \},',
                line,
            )
            if vm:
                manifest["videos"][vm.group(1)] = {
                    "unique": int(vm.group(11)) if vm.group(11) else None,
                    "index": vm.group(12),
                    "dir": vm.group(2),
                    "pattern": vm.group(3),
                    "audio": vm.group(5) if vm.group(4) != "nil" else None,
                    "fps": float(vm.group(6)),
                    "frames": int(vm.group(7)),
                    "width": int(vm.group(8)),
                    "height": int(vm.group(9)),
                    "duration": float(vm.group(10)),
                }

    # Parse music build orders
    for b in ("build1", "build2", "build3"):
        rel = f"music/{b}.txt"
        if rel in files:
            manifest["music_builds"][b] = parse_build_txt(files[rel])

    # Load shared DXRs first for palette/cast fallback resolution
    root_shared: DirectorMovie | None = None
    super_shared: DirectorMovie | None = None
    if "shared.dxr" in files:
        root_shared = load_dxr(str(files["shared.dxr"]))
    if "super/shared.dxr" in files:
        super_shared = load_dxr(str(files["super/shared.dxr"]))

    tasks = []
    seen_keys: Dict[str, Dict[str, Path]] = {}

    def register_key(category: str, key: str, src_path: Path) -> str:
        bucket = seen_keys.setdefault(category, {})
        if key in bucket and bucket[key] != src_path:
            raise RuntimeError(f"Key collision in {category}: '{key}' ({bucket[key]} vs {src_path})")
        bucket[key] = src_path
        return key

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        # 1. BMPs
        if not args.only_dxr:
            for rel, path in sorted(files.items()):
                if rel.endswith(".bmp"):
                    prefix = "pic_" if rel.startswith("pictures/") else ""
                    key = register_key("images", prefix + normalize_key(path.name), path)
                    out_rel = f"images/bmp/{key}.png"
                    manifest["images"][key] = out_rel
                    tasks.append(pool.submit(convert_bmp, path, out_root / out_rel))

        # 2. Audio (.aif & .wav, skipping redundant 8-bit music8/solos8)
        audio_groups = {
            "music/build1/": "music_build1",
            "music/build2/": "music_build2",
            "music/build3/": "music_build3",
            "solos/": "solos",
            "sounds/": "sounds",
            "startsnd/": "startsnd",
            "endsound/": "endsound",
            "super/sounds/": "super_sounds",
        }
        if not args.only_dxr:
            audio_hashes: Dict[str, str] = {}
            for rel, path in sorted(files.items()):
                if rel.startswith(("music8/", "solos8/")):
                    continue
                if not (rel.endswith(".aif") or rel.endswith(".wav")):
                    continue
                group = None
                for prefix, gname in audio_groups.items():
                    if rel.startswith(prefix):
                        group = gname
                        break
                if group is None and "/" not in rel:
                    group = "root"
                if group is None:
                    continue
                key = register_key(f"audio.{group}", normalize_key(path.name), path)
                digest = hashlib.sha1(path.read_bytes()).hexdigest()
                if digest in audio_hashes:
                    manifest["audio"].setdefault(group, {})[key] = audio_hashes[digest]
                else:
                    out_rel = f"audio/{group}/{key}.mp3"
                    audio_hashes[digest] = out_rel
                    manifest["audio"].setdefault(group, {})[key] = out_rel
                    tasks.append(pool.submit(convert_audio, path, out_root / out_rel))

        # 3. Videos (.mov)
        video_futures = {}
        if not args.skip_videos and not args.only_dxr:
            for rel, path in sorted(files.items()):
                if rel.endswith(".mov"):
                    key = register_key("videos", normalize_key(path.name), path)
                    rel_dir = f"videos/{key}"
                    fut = pool.submit(convert_video, path, out_root / rel_dir, rel_dir)
                    video_futures[fut] = key

        # 4. Director 4 .DXR movies
        dxr_futures = {}

        def export_dxr_task(src_path: Path, key: str, shared: DirectorMovie | None) -> Tuple[str, dict]:
            mov = load_dxr(str(src_path))
            rel_dir = f"dxr/{key}"
            stats = mov.export(str(out_root / rel_dir), rel_dir, shared=shared)
            return f"{rel_dir}/score.lua", stats

        for rel, path in sorted(files.items()):
            if not rel.endswith(".dxr"):
                continue
            if rel.startswith("super/"):
                key = register_key("dxr", "super_" + normalize_key(path.name), path)
                shared = None if rel == "super/shared.dxr" else super_shared
            elif "/" not in rel:
                key = register_key("dxr", normalize_key(path.name), path)
                shared = None if rel == "shared.dxr" else root_shared
            else:
                continue
            fut = pool.submit(export_dxr_task, path, key, shared)
            dxr_futures[fut] = key

        # 5. Embedded movies inside Windows EXE projectors
        def export_exe_task(exe_path: Path, key: str, shared: DirectorMovie | None) -> Tuple[str, dict]:
            movies = load_projector_movies(str(exe_path))
            if not movies:
                raise RuntimeError(f"No embedded Director movie found in {exe_path}")
            # Largest embedded movie is the main projector movie
            mov = max(movies, key=lambda m: len(m.entries))
            rel_dir = f"dxr/{key}"
            stats = mov.export(str(out_root / rel_dir), rel_dir, shared=shared)
            return f"{rel_dir}/score.lua", stats

        for rel, key, shared in (
            ("muizen.exe", "muizen_exe", root_shared),
            ("doolhof/doolhof.exe", "doolhof", None),
        ):
            if rel in files:
                k = register_key("dxr", key, files[rel])
                fut = pool.submit(export_exe_task, files[rel], k, shared)
                dxr_futures[fut] = k

        # Collect results
        for fut in tasks:
            fut.result()
        for fut in as_completed(video_futures):
            k = video_futures[fut]
            manifest["videos"][k] = fut.result()
        total_sprites = 0
        total_sounds = 0
        for fut in as_completed(dxr_futures):
            k = dxr_futures[fut]
            score_rel, stats = fut.result()
            manifest["dxr"][k] = score_rel
            total_sprites += stats["sprites"]
            total_sounds += stats["sounds"]

    write_manifest(out_root, manifest)
    elapsed = time.time() - t0
    audio_count = sum(len(g) for g in manifest["audio"].values())
    print(
        f"Done in {elapsed:.1f}s! "
        f"BMPs={len(manifest['images'])}, Audio={audio_count}, "
        f"Videos={len(manifest['videos'])}, DXRs={len(manifest['dxr'])} "
        f"(sprites={total_sprites}, embedded_snd={total_sounds})"
    )
    print(f"Manifest written to {out_root / 'manifest.lua'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
