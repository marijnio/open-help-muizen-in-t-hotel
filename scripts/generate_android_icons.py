#!/usr/bin/env python3
"""Generate Android launcher mipmap icons (ic_launcher.png & ic_launcher_round.png).

Uses --source if provided (e.g. a locally converted BMP/PNG), otherwise draws a
clean-room green-mouse emblem so --no-assets builds never depend on external files.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def make_clean_room_icon(size: int) -> Image.Image:
    """Render a crisp vector-like green mouse emblem on a dark hotel green badge."""
    scale = 4
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    pad = int(s * 0.04)
    radius = int(s * 0.20)
    draw.rounded_rectangle(
        [pad, pad, s - pad, s - pad],
        radius=radius,
        fill=(22, 42, 34, 255),
        outline=(110, 210, 105, 255),
        width=max(2, int(s * 0.035)),
    )

    # Ears
    ear_l = [int(s * 0.16), int(s * 0.16), int(s * 0.44), int(s * 0.44)]
    ear_r = [int(s * 0.56), int(s * 0.16), int(s * 0.84), int(s * 0.44)]
    draw.ellipse(ear_l, fill=(72, 200, 72, 255), outline=(14, 24, 18, 255), width=max(2, s // 40))
    draw.ellipse(ear_r, fill=(72, 200, 72, 255), outline=(14, 24, 18, 255), width=max(2, s // 40))

    in_pad = int(s * 0.06)
    draw.ellipse(
        [ear_l[0] + in_pad, ear_l[1] + in_pad, ear_l[2] - in_pad, ear_l[3] - in_pad],
        fill=(228, 224, 155, 255),
    )
    draw.ellipse(
        [ear_r[0] + in_pad, ear_r[1] + in_pad, ear_r[2] - in_pad, ear_r[3] - in_pad],
        fill=(228, 224, 155, 255),
    )

    # Head
    head = [int(s * 0.24), int(s * 0.28), int(s * 0.76), int(s * 0.80)]
    draw.ellipse(head, fill=(64, 196, 68, 255), outline=(14, 24, 18, 255), width=max(2, s // 40))

    # Eyes
    for ex in (0.37, 0.53):
        eye = [int(s * ex), int(s * 0.42), int(s * (ex + 0.10)), int(s * 0.55)]
        draw.ellipse(eye, fill=(250, 248, 225, 255), outline=(14, 24, 18, 255), width=max(1, s // 64))
        pupil = [int(s * (ex + 0.03)), int(s * 0.46), int(s * (ex + 0.075)), int(s * 0.52)]
        draw.ellipse(pupil, fill=(18, 20, 22, 255))

    # Nose
    nose = [int(s * 0.44), int(s * 0.60), int(s * 0.56), int(s * 0.70)]
    draw.ellipse(nose, fill=(224, 154, 108, 255), outline=(14, 24, 18, 255), width=max(1, s // 64))

    return img.resize((size, size), Image.Resampling.LANCZOS)


def make_source_icon(src_path: Path, size: int) -> Image.Image:
    with Image.open(src_path) as raw:
        im = raw.convert("RGBA")
    w, h = im.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    cropped = im.crop((left, top, left + side, top + side)).resize((size, size), Image.Resampling.LANCZOS)

    mask = Image.new("L", (size, size), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.rounded_rectangle([0, 0, size - 1, size - 1], radius=max(4, size // 5), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(cropped, (0, 0), mask)
    return out


def make_round_icon(square_icon: Image.Image) -> Image.Image:
    size = square_icon.size[0]
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(square_icon, (0, 0), mask)
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Android mipmap launcher icons.")
    parser.add_argument("--output", required=True, help="Target Android res/ directory")
    parser.add_argument("--source", default=None, help="Optional source PNG/BMP image")
    args = parser.parse_args()

    out_res = Path(args.output)
    src = Path(args.source) if args.source else None
    use_source = src is not None and src.is_file()

    for folder, size in DENSITIES.items():
        mip_dir = out_res / folder
        mip_dir.mkdir(parents=True, exist_ok=True)
        sq = make_source_icon(src, size) if use_source else make_clean_room_icon(size)
        rd = make_round_icon(sq)
        sq.save(mip_dir / "ic_launcher.png", "PNG")
        rd.save(mip_dir / "ic_launcher_round.png", "PNG")

    print(f"Generated Android launcher icons in {out_res} (source={'custom' if use_source else 'clean-room'})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
