#!/usr/bin/env python3
"""Generate Android launcher icons (legacy mipmaps, adaptive icons, and drawable/love.png).

Uses --source if provided (e.g. assets/dxr/instrum/sprites/c_10.png), automatically
handling transparent sprites vs. opaque images, or draws a clean-room green-mouse
emblem when no source is provided (for --no-assets builds).
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageOps

LEGACY_DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

ADAPTIVE_DENSITIES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}

BURGUNDY_CENTER = (110, 23, 34)   # #6E1722
BURGUNDY_EDGE = (58, 10, 18)      # #3A0A12
GOLD_RIM = (224, 176, 70, 255)    # #E0B046

IC_LAUNCHER_BACKGROUND_XML = """<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <gradient
        android:type="radial"
        android:gradientRadius="70%p"
        android:centerX="50%"
        android:centerY="50%"
        android:startColor="#6E1722"
        android:endColor="#3A0A12" />
</shape>
"""

ADAPTIVE_ICON_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""


def _make_burgundy_badge(size: int, is_round: bool) -> Image.Image:
    """Create a supersampled radial-gradient hotel burgundy badge with a warm gold rim."""
    scale = 4
    s = size * scale

    grad_l = Image.radial_gradient("L").resize((s, s), Image.Resampling.BILINEAR)
    grad_rgb = ImageOps.colorize(grad_l, BURGUNDY_CENTER, BURGUNDY_EDGE).convert("RGBA")

    mask = Image.new("L", (s, s), 0)
    mdraw = ImageDraw.Draw(mask)
    pad = max(2, int(round(s * 0.02)))
    radius = int(round(s * 0.21))
    if is_round:
        mdraw.ellipse([pad, pad, s - 1 - pad, s - 1 - pad], fill=255)
    else:
        mdraw.rounded_rectangle([pad, pad, s - 1 - pad, s - 1 - pad], radius=radius, fill=255)

    badge = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    badge.paste(grad_rgb, (0, 0), mask)

    rim_draw = ImageDraw.Draw(badge)
    rim_width = max(4, int(round(s * 0.032)))
    rim_inset = pad + max(1, rim_width // 4)
    if is_round:
        rim_draw.ellipse(
            [rim_inset, rim_inset, s - 1 - rim_inset, s - 1 - rim_inset],
            outline=GOLD_RIM,
            width=rim_width,
        )
    else:
        rim_draw.rounded_rectangle(
            [rim_inset, rim_inset, s - 1 - rim_inset, s - 1 - rim_inset],
            radius=max(4, radius - (rim_inset - pad)),
            outline=GOLD_RIM,
            width=rim_width,
        )

    return badge.resize((size, size), Image.Resampling.LANCZOS)


def _place_sprite_with_shadow(
    canvas: Image.Image,
    sprite: Image.Image,
    fit_fraction: float,
) -> Image.Image:
    """Center-fit a transparent sprite inside canvas with a subtle drop shadow."""
    cw, ch = canvas.size
    sw, sh = sprite.size
    max_dim = max(1, int(round(min(cw, ch) * fit_fraction)))
    scale = min(max_dim / sw, max_dim / sh)
    nw = max(1, int(round(sw * scale)))
    nh = max(1, int(round(sh * scale)))
    resized = sprite.resize((nw, nh), Image.Resampling.LANCZOS)

    x = (cw - nw) // 2
    y = (ch - nh) // 2

    # Soft dark drop shadow slightly down-right
    alpha = resized.getchannel("A")
    shadow_alpha = alpha.point(lambda a: int(a * 0.45))
    shadow_layer = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    shadow_tint = Image.new("RGBA", (nw, nh), (16, 4, 8, 255))
    shadow_tint.putalpha(shadow_alpha)
    offset = max(1, min(cw, ch) // 36)
    shadow_layer.paste(shadow_tint, (x + offset, y + offset), shadow_tint)
    blur_radius = max(1.0, min(cw, ch) / 48.0)
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(radius=blur_radius))

    out = Image.alpha_composite(canvas, shadow_layer)
    fg_layer = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    fg_layer.paste(resized, (x, y), resized)
    return Image.alpha_composite(out, fg_layer)


def _make_clean_room_mouse_emblem(size: int) -> Image.Image:
    """Render a crisp vector-like green mouse head emblem on a transparent canvas."""
    scale = 4
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    outline_w = max(2, s // 34)
    # Ears
    ear_l = [int(s * 0.08), int(s * 0.08), int(s * 0.44), int(s * 0.44)]
    ear_r = [int(s * 0.56), int(s * 0.08), int(s * 0.92), int(s * 0.44)]
    draw.ellipse(ear_l, fill=(46, 198, 54, 255), outline=(14, 24, 18, 255), width=outline_w)
    draw.ellipse(ear_r, fill=(46, 198, 54, 255), outline=(14, 24, 18, 255), width=outline_w)

    in_pad = int(s * 0.075)
    draw.ellipse(
        [ear_l[0] + in_pad, ear_l[1] + in_pad, ear_l[2] - in_pad, ear_l[3] - in_pad],
        fill=(232, 228, 152, 255),
    )
    draw.ellipse(
        [ear_r[0] + in_pad, ear_r[1] + in_pad, ear_r[2] - in_pad, ear_r[3] - in_pad],
        fill=(232, 228, 152, 255),
    )

    # Head
    head = [int(s * 0.17), int(s * 0.22), int(s * 0.83), int(s * 0.88)]
    draw.ellipse(head, fill=(40, 194, 48, 255), outline=(14, 24, 18, 255), width=outline_w)

    # Eyes
    eye_w = max(2, s // 56)
    for ex in (0.33, 0.53):
        eye = [int(s * ex), int(s * 0.39), int(s * (ex + 0.14)), int(s * 0.56)]
        draw.ellipse(eye, fill=(252, 250, 228, 255), outline=(14, 24, 18, 255), width=eye_w)
        pupil = [int(s * (ex + 0.04)), int(s * 0.44), int(s * (ex + 0.105)), int(s * 0.525)]
        draw.ellipse(pupil, fill=(18, 20, 22, 255))

    # Nose
    nose = [int(s * 0.415), int(s * 0.62), int(s * 0.585), int(s * 0.75)]
    draw.ellipse(nose, fill=(224, 154, 108, 255), outline=(14, 24, 18, 255), width=eye_w)

    return img.resize((size, size), Image.Resampling.LANCZOS)


def _load_source(src_path: Path | None) -> tuple[Image.Image | None, bool]:
    """Load source image as RGBA and return (image, is_transparent_sprite)."""
    if src_path is None or not src_path.is_file():
        return None, False
    with Image.open(src_path) as raw:
        im = raw.convert("RGBA")
    min_alpha, _ = im.getchannel("A").getextrema()
    if min_alpha < 250:
        bbox = im.getbbox()
        if bbox:
            im = im.crop(bbox)
        return im, True
    return im, False


def _make_opaque_legacy(im: Image.Image, size: int, is_round: bool) -> Image.Image:
    w, h = im.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    cropped = im.crop((left, top, left + side, top + side)).resize(
        (size, size), Image.Resampling.LANCZOS
    )
    mask = Image.new("L", (size, size), 0)
    mdraw = ImageDraw.Draw(mask)
    if is_round:
        mdraw.ellipse([0, 0, size - 1, size - 1], fill=255)
    else:
        mdraw.rounded_rectangle([0, 0, size - 1, size - 1], radius=max(4, size // 5), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(cropped, (0, 0), mask)
    return out


def _make_opaque_foreground(im: Image.Image, fg_size: int) -> Image.Image:
    w, h = im.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    inner = max(1, int(round(fg_size * 0.66)))
    cropped = im.crop((left, top, left + side, top + side)).resize(
        (inner, inner), Image.Resampling.LANCZOS
    )
    mask = Image.new("L", (inner, inner), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, inner - 1, inner - 1], radius=max(4, inner // 6), fill=255
    )
    out = Image.new("RGBA", (fg_size, fg_size), (0, 0, 0, 0))
    pos = (fg_size - inner) // 2
    out.paste(cropped, (pos, pos), mask)
    return out


def _remove_conflicting_webp(directory: Path, stems: tuple[str, ...]) -> None:
    for stem in stems:
        webp = directory / f"{stem}.webp"
        if webp.exists():
            webp.unlink()


def generate_icons(out_res: Path, src_path: Path | None) -> str:
    src_im, is_transparent = _load_source(src_path)
    if src_im is None:
        mode = "clean-room"
    elif is_transparent:
        mode = "transparent-sprite"
    else:
        mode = "opaque-image"

    for density, size in LEGACY_DENSITIES.items():
        mip_dir = out_res / f"mipmap-{density}"
        mip_dir.mkdir(parents=True, exist_ok=True)
        _remove_conflicting_webp(mip_dir, ("ic_launcher", "ic_launcher_round", "ic_launcher_foreground"))

        drw_dir = out_res / f"drawable-{density}"
        drw_dir.mkdir(parents=True, exist_ok=True)
        _remove_conflicting_webp(drw_dir, ("love",))

        fg_size = ADAPTIVE_DENSITIES[density]
        fg_canvas = Image.new("RGBA", (fg_size, fg_size), (0, 0, 0, 0))

        if src_im is None:
            emblem_legacy = _make_clean_room_mouse_emblem(size)
            emblem_fg = _make_clean_room_mouse_emblem(fg_size)
            sq = _place_sprite_with_shadow(_make_burgundy_badge(size, is_round=False), emblem_legacy, 0.74)
            rd = _place_sprite_with_shadow(_make_burgundy_badge(size, is_round=True), emblem_legacy, 0.72)
            fg = _place_sprite_with_shadow(fg_canvas, emblem_fg, 0.58)
        elif is_transparent:
            sq = _place_sprite_with_shadow(_make_burgundy_badge(size, is_round=False), src_im, 0.78)
            rd = _place_sprite_with_shadow(_make_burgundy_badge(size, is_round=True), src_im, 0.74)
            fg = _place_sprite_with_shadow(fg_canvas, src_im, 0.62)
        else:
            sq = _make_opaque_legacy(src_im, size, is_round=False)
            rd = _make_opaque_legacy(src_im, size, is_round=True)
            fg = _make_opaque_foreground(src_im, fg_size)

        sq.save(mip_dir / "ic_launcher.png", "PNG")
        rd.save(mip_dir / "ic_launcher_round.png", "PNG")
        fg.save(mip_dir / "ic_launcher_foreground.png", "PNG")
        sq.save(drw_dir / "love.png", "PNG")

    drawable_dir = out_res / "drawable"
    drawable_dir.mkdir(parents=True, exist_ok=True)
    (drawable_dir / "ic_launcher_background.xml").write_text(
        IC_LAUNCHER_BACKGROUND_XML, encoding="utf-8"
    )

    anydpi_dir = out_res / "mipmap-anydpi-v26"
    anydpi_dir.mkdir(parents=True, exist_ok=True)
    (anydpi_dir / "ic_launcher.xml").write_text(ADAPTIVE_ICON_XML, encoding="utf-8")
    (anydpi_dir / "ic_launcher_round.xml").write_text(ADAPTIVE_ICON_XML, encoding="utf-8")

    return mode


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Android launcher and adaptive icons.")
    parser.add_argument("--output", required=True, help="Target Android res/ directory")
    parser.add_argument("--source", default=None, help="Optional source PNG/BMP image")
    args = parser.parse_args()

    out_res = Path(args.output)
    src = Path(args.source) if args.source else None
    mode = generate_icons(out_res, src)
    print(f"Generated Android launcher & adaptive icons in {out_res} (mode={mode})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
