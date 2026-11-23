#!/usr/bin/env python3
"""Local asset conversion pipeline for Help! Muizen in 't hotel.

Converts original Director 4 (.DXR/.EXE), QuickTime (.MOV), AIFF/WAV audio,
and BMP images into LÖVE-ready assets + assets/manifest.lua.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import os
import re
import shutil
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
        im.convert("RGBA").save(dst, "PNG")


def convert_audio(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg",
        "-y",
        "-v",
        "error",
        "-i",
        str(src),
        "-acodec",
        "pcm_s16le",
        "-ar",
        "22050",
        "-ac",
        "1",
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


def _encode_png(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def convert_video(src: Path, out_dir: Path, rel_dir: str) -> dict:
    """Extract frames as lossless palette PNG *delta patches* plus a frame step index.

    The original QuickTime clips are 8-bit palettized (smc/pal8) cel animations: most
    frames are held or only change a small region. So instead of storing every frame we
    store, per change, only the bounding rectangle of changed pixels (first frame is a
    full patch). Identical patches (loops) are stored once. The player composites patches
    onto a canvas in order. This is lossless and many times smaller than JPEG sequences.
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

    patches: List[Tuple[int, int]] = []
    patch_ids: Dict[Tuple[int, int, str], int] = {}
    steps: List[int] = []
    prev_rgb: Image.Image | None = None
    for raw in sorted(out_dir.glob("raw_*.png")):
        with Image.open(raw) as im:
            im.load()
        raw.unlink()
        rgb = im.convert("RGB")
        if prev_rgb is None:
            bbox = (0, 0, im.width, im.height)
        else:
            bbox = ImageChops.difference(rgb, prev_rgb).getbbox()
        prev_rgb = rgb
        if not bbox:
            steps.append(0)
            continue
        data = _encode_png(im.crop(bbox))
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
                out_rel = f"audio/{group}/{key}.wav"
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
