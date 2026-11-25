#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/dist"
NO_ASSETS=0
BUILD_APK=1
DEBUG_APK=1
PUSH_ASSETS=0
PACKAGE_NAME="org.love2d.android"
LOVE_ANDROID_DIR_FROM_ENV=0
if [[ -n "${LOVE_ANDROID_DIR:-}" ]]; then
    LOVE_ANDROID_DIR_FROM_ENV=1
elif [[ -d "${ROOT_DIR}/love-android" ]]; then
    LOVE_ANDROID_DIR="${ROOT_DIR}/love-android"
elif [[ -d "${ROOT_DIR}/../love-android" ]]; then
    LOVE_ANDROID_DIR="$(cd "${ROOT_DIR}/../love-android" && pwd)"
else
    LOVE_ANDROID_DIR="${ROOT_DIR}/love-android"
fi
ICON_SOURCE=""
APP_NAME="Help! Muizen in 't hotel"

usage() {
    cat <<'EOF'
Usage: scripts/build_android.sh [options]

Packages Help! Muizen in 't hotel as a .love archive and builds an Android APK
using love-android by default (or pushes side-loaded assets via adb).

Options:
  --no-assets        Build without bundling assets/ (for side-loading)
  --output <dir>     Output directory for .apk / .love (default: dist)
  --build-apk        Build APK via love-android (default; uses $LOVE_ANDROID_DIR, ./love-android, or ../love-android)
  --love-only        Only build the .love archive and skip building the APK
  --debug            Build signed debug APK (default; directly installable on Android)
  --release          Build release APK (requires signing config to install on Android)
  --icon <path>      Optional source image for Android launcher icons
  --app-name <title> Android app title (default: "Help! Muizen in 't hotel")
  --push-assets      Push local assets/ to Android external save dir via adb
  --package <id>     Android applicationId for --push-assets (default: org.love2d.android)
  -h, --help         Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-assets)
            NO_ASSETS=1
            shift
            ;;
        --output)
            OUT_DIR="$2"
            shift 2
            ;;
        --build-apk)
            BUILD_APK=1
            shift
            ;;
        --love-only)
            BUILD_APK=0
            shift
            ;;
        --debug)
            DEBUG_APK=1
            shift
            ;;
        --release)
            DEBUG_APK=0
            shift
            ;;
        --icon)
            ICON_SOURCE="$2"
            shift 2
            ;;
        --app-name)
            APP_NAME="$2"
            shift 2
            ;;
        --push-assets)
            PUSH_ASSETS=1
            shift
            ;;
        --package)
            PACKAGE_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "${BUILD_APK}" -eq 1 && ! -d "${LOVE_ANDROID_DIR}" ]]; then
    if [[ "${LOVE_ANDROID_DIR_FROM_ENV}" -eq 1 ]]; then
        echo "Error: love-android directory not found at ${LOVE_ANDROID_DIR}." >&2
    else
        echo "Error: love-android directory not found (checked ${ROOT_DIR}/love-android and ${ROOT_DIR}/../love-android)." >&2
    fi
    echo "Clone love-android, set LOVE_ANDROID_DIR=/path/to/love-android, or pass --love-only." >&2
    exit 1
fi

mkdir -p "${OUT_DIR}"
OUT_DIR="$(cd "${OUT_DIR}" && pwd)"

if [[ "${NO_ASSETS}" -eq 1 ]]; then
    LOVE_NAME="help-muizen-hotel-no-assets.love"
else
    LOVE_NAME="help-muizen-hotel.love"
    if [[ ! -f "${ROOT_DIR}/assets/manifest.lua" ]]; then
        echo "Error: assets/manifest.lua not found. Run tools/convert_assets.py first or pass --no-assets." >&2
        exit 1
    fi
fi

LOVE_PATH="${OUT_DIR}/${LOVE_NAME}"
rm -f "${LOVE_PATH}"

python3 - "${ROOT_DIR}" "${LOVE_PATH}" "${NO_ASSETS}" <<'PY'
import fnmatch
import os
import sys
import zipfile
from pathlib import Path

root_dir = Path(sys.argv[1])
love_path = Path(sys.argv[2])
no_assets = int(sys.argv[3])

roots = ["main.lua", "conf.lua", "src"]
if no_assets == 0:
    roots.append("assets")

store_exts = {".png", ".mp3", ".ogg", ".jpg", ".jpeg", ".webp"}
exclude_roots = {"local_config.lua", "backup", "tools", "scripts", "dist", "build", "love-android", ".git"}

def is_excluded(rel_posix: str) -> bool:
    parts = rel_posix.split("/")
    if parts[0] in exclude_roots:
        return True
    if "__pycache__" in parts:
        return True
    name = parts[-1]
    if name == ".DS_Store" or fnmatch.fnmatch(name, "*.pyc"):
        return True
    return False

with zipfile.ZipFile(love_path, "w") as zf:
    for entry in roots:
        target = root_dir / entry
        if target.is_file():
            rel = target.relative_to(root_dir).as_posix()
            if not is_excluded(rel):
                ctype = zipfile.ZIP_STORED if target.suffix.lower() in store_exts else zipfile.ZIP_DEFLATED
                zinfo = zipfile.ZipInfo.from_file(target, rel)
                zinfo.compress_type = ctype
                with open(target, "rb") as f:
                    zf.writestr(zinfo, f.read(), compress_type=ctype, compresslevel=9 if ctype == zipfile.ZIP_DEFLATED else None)
        elif target.is_dir():
            for dirpath, dirnames, filenames in os.walk(target):
                dirnames[:] = sorted(
                    d for d in dirnames
                    if not is_excluded((Path(dirpath) / d).relative_to(root_dir).as_posix())
                )
                for fn in sorted(filenames):
                    fpath = Path(dirpath) / fn
                    rel = fpath.relative_to(root_dir).as_posix()
                    if is_excluded(rel):
                        continue
                    ctype = zipfile.ZIP_STORED if fpath.suffix.lower() in store_exts else zipfile.ZIP_DEFLATED
                    zinfo = zipfile.ZipInfo.from_file(fpath, rel)
                    zinfo.compress_type = ctype
                    with open(fpath, "rb") as f:
                        zf.writestr(zinfo, f.read(), compress_type=ctype, compresslevel=9 if ctype == zipfile.ZIP_DEFLATED else None)
PY

echo "Built ${LOVE_PATH} ($(du -h "${LOVE_PATH}" | awk '{print $1}'))"

if [[ "${PUSH_ASSETS}" -eq 1 ]]; then
    if [[ ! -d "${ROOT_DIR}/assets" ]]; then
        echo "Error: ${ROOT_DIR}/assets does not exist." >&2
        exit 1
    fi
    if ! command -v adb >/dev/null 2>&1; then
        echo "Error: adb not found on PATH." >&2
        exit 1
    fi
    TARGET_DIR="/sdcard/Android/data/${PACKAGE_NAME}/files/save/help-muizen-hotel/assets"
    echo "Pushing assets/ to ${TARGET_DIR} via adb..."
    adb shell mkdir -p "${TARGET_DIR}"
    adb push "${ROOT_DIR}/assets/." "${TARGET_DIR}/"
    echo "Side-loaded assets pushed successfully."
fi

if [[ "${BUILD_APK}" -eq 1 ]]; then
    EMBED_ASSETS_DIR="${LOVE_ANDROID_DIR}/app/src/embed/assets"
    mkdir -p "${EMBED_ASSETS_DIR}"
    cp "${LOVE_PATH}" "${EMBED_ASSETS_DIR}/game.love"
    echo "Copied ${LOVE_PATH} -> ${EMBED_ASSETS_DIR}/game.love"

    RES_DIR="${LOVE_ANDROID_DIR}/app/src/main/res"
    ICON_ARGS=(--output "${RES_DIR}")
    if [[ -n "${ICON_SOURCE}" ]]; then
        ICON_ARGS+=(--source "${ICON_SOURCE}")
    elif [[ "${NO_ASSETS}" -eq 0 && -f "${ROOT_DIR}/assets/dxr/instrum/sprites/c_10.png" ]]; then
        ICON_ARGS+=(--source "${ROOT_DIR}/assets/dxr/instrum/sprites/c_10.png")
    fi
    python3 "${ROOT_DIR}/scripts/generate_android_icons.py" "${ICON_ARGS[@]}"

    # Update Android app_name string resource (properly escaped for aapt2) and manifest metadata
    python3 - "${LOVE_ANDROID_DIR}" "${APP_NAME}" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

love_dir = Path(sys.argv[1])
app_name = sys.argv[2]


def escape_android_string(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', '\\"')
        .replace("'", "\\'")
    )


escaped_name = escape_android_string(app_name)


def update_strings_file(path: Path, create_if_missing: bool) -> None:
    if not path.is_file():
        if not create_if_missing:
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        content = (
            '<?xml version="1.0" encoding="utf-8"?>\n'
            "<resources>\n"
            f'    <string name="app_name">{escaped_name}</string>\n'
            "</resources>\n"
        )
        path.write_text(content, encoding="utf-8")
        ET.fromstring(content)
        print(f"Created {path} with app_name={app_name!r}")
        return

    txt = path.read_text(encoding="utf-8")
    pattern = re.compile(r'(<string\b[^>]*\bname="app_name"[^>]*>)(.*?)(</string>)', re.DOTALL)
    if pattern.search(txt):
        new_txt = pattern.sub(lambda m: f"{m.group(1)}{escaped_name}{m.group(3)}", txt, count=1)
    elif create_if_missing and "</resources>" in txt:
        new_txt = txt.replace(
            "</resources>",
            f'    <string name="app_name">{escaped_name}</string>\n</resources>',
            1,
        )
    else:
        return

    if new_txt != txt:
        ET.fromstring(new_txt)
        path.write_text(new_txt, encoding="utf-8")
        print(f"Updated app_name={app_name!r} in {path}")


main_strings = love_dir / "app" / "src" / "main" / "res" / "values" / "strings.xml"
update_strings_file(main_strings, create_if_missing=True)

for flavor_strings in sorted((love_dir / "app" / "src").glob("embed*/res/values*/strings.xml")):
    update_strings_file(flavor_strings, create_if_missing=False)


def set_xml_attr(tag_text: str, attr: str, value: str) -> str:
    attr_re = re.compile(rf'(\s+{re.escape(attr)}\s*=\s*")([^"]*)(")')
    if attr_re.search(tag_text):
        return attr_re.sub(rf"\g<1>{value}\g<3>", tag_text, count=1)
    if tag_text.endswith("/>"):
        return f'{tag_text[:-2]} {attr}="{value}"/>'
    return f'{tag_text[:-1]} {attr}="{value}">'


def patch_manifest(manifest_path: Path, is_main: bool) -> None:
    if not manifest_path.is_file():
        return
    txt = manifest_path.read_text(encoding="utf-8")
    new_txt = txt

    app_re = re.compile(r"<application\b[^>]*>", re.DOTALL)
    app_match = app_re.search(new_txt)
    if app_match:
        app_tag = app_match.group(0)
        app_tag = set_xml_attr(app_tag, "android:label", "@string/app_name")
        app_tag = set_xml_attr(app_tag, "android:icon", "@mipmap/ic_launcher")
        app_tag = set_xml_attr(app_tag, "android:roundIcon", "@mipmap/ic_launcher_round")
        new_txt = new_txt[: app_match.start()] + app_tag + new_txt[app_match.end() :]

    if is_main:
        act_re = re.compile(r"<activity\b[^>]*>", re.DOTALL)
        matches = list(act_re.finditer(new_txt))
        target_match = None
        for m in matches:
            if re.search(r'android:name\s*=\s*"[^"]*GameActivity"', m.group(0)):
                target_match = m
                break
        if target_match is None and matches:
            target_match = matches[0]

        if target_match is not None:
            act_tag = target_match.group(0)
            act_tag = set_xml_attr(act_tag, "android:screenOrientation", "sensorLandscape")
            if re.search(r'\bandroid:label\s*=\s*"[^"]*"', act_tag):
                act_tag = set_xml_attr(act_tag, "android:label", "@string/app_name")
            if re.search(r'\bandroid:icon\s*=\s*"[^"]*"', act_tag):
                act_tag = set_xml_attr(act_tag, "android:icon", "@mipmap/ic_launcher")
            new_txt = new_txt[: target_match.start()] + act_tag + new_txt[target_match.end() :]

    if new_txt != txt:
        ET.fromstring(new_txt)
        manifest_path.write_text(new_txt, encoding="utf-8")
        print(f"Updated AndroidManifest metadata in {manifest_path}")


patch_manifest(love_dir / "app" / "src" / "main" / "AndroidManifest.xml", is_main=True)
patch_manifest(love_dir / "app" / "src" / "embed" / "AndroidManifest.xml", is_main=False)
PY

    # Ensure assets/game.love is stored uncompressed (ZIP_STORED) in the APK so Android's
    # AssetManager / PhysFS can seek PNG video frames in O(1) instead of inflating ~50 MB per frame.
    python3 - "${LOVE_ANDROID_DIR}" <<'PY'
import re
import sys
from pathlib import Path

love_dir = Path(sys.argv[1])
gradle_path = None
is_kts = False
for candidate, kts in (
    (love_dir / "app" / "build.gradle", False),
    (love_dir / "app" / "build.gradle.kts", True),
):
    if candidate.is_file():
        gradle_path = candidate
        is_kts = kts
        break

if gradle_path is None:
    print(f"Warning: no app/build.gradle(.kts) found under {love_dir}; skipping noCompress check.", file=sys.stderr)
    sys.exit(0)

txt = gradle_path.read_text(encoding="utf-8")
if re.search(r'noCompress[^\n]*["\']love["\']', txt):
    print(f"Verified noCompress for 'love' already present in {gradle_path}")
    sys.exit(0)

new_txt = None
res_match = re.search(r'^([ \t]*)androidResources\s*\{', txt, re.MULTILINE)
aapt_match = re.search(r'^([ \t]*)aaptOptions\s*\{', txt, re.MULTILINE)
android_match = re.search(r'^([ \t]*)android\s*\{', txt, re.MULTILINE)

if res_match:
    indent = res_match.group(1) + "    "
    insert = f'\n{indent}noCompress.add("love")'
    new_txt = txt[: res_match.end()] + insert + txt[res_match.end() :]
elif aapt_match:
    indent = aapt_match.group(1) + "    "
    line = f'{indent}noCompress("love")' if is_kts else f"{indent}noCompress 'love'"
    new_txt = txt[: aapt_match.end()] + "\n" + line + txt[aapt_match.end() :]
elif android_match:
    indent = android_match.group(1) + "    "
    block = f'\n{indent}androidResources {{\n{indent}    noCompress.add("love")\n{indent}}}'
    new_txt = txt[: android_match.end()] + block + txt[android_match.end() :]
else:
    print(f"Warning: could not locate android {{ }} block in {gradle_path} to add noCompress.", file=sys.stderr)
    sys.exit(0)

gradle_path.write_text(new_txt, encoding="utf-8")
print(f"Added noCompress for 'love' in {gradle_path}")
PY

    GRADLE_TASK="assembleEmbedNoRecordRelease"
    APK_VARIANT_DIR="embedNoRecord/release"
    if [[ "${DEBUG_APK}" -eq 1 ]]; then
        GRADLE_TASK="assembleEmbedNoRecordDebug"
        APK_VARIANT_DIR="embedNoRecord/debug"
    fi
    echo "Running Gradle task ${GRADLE_TASK} in ${LOVE_ANDROID_DIR}..."
    (
        cd "${LOVE_ANDROID_DIR}"
        ./gradlew "${GRADLE_TASK}"
    )

    APK_OUTPUTS_DIR="${LOVE_ANDROID_DIR}/app/build/outputs/apk"
    FOUND_APK="$(python3 - "${APK_OUTPUTS_DIR}" "${APK_VARIANT_DIR}" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
variant_dir = root / sys.argv[2]

def newest_apk(search_dir: Path):
    if not search_dir.is_dir():
        return None
    apks = sorted(search_dir.rglob("*.apk"), key=lambda p: p.stat().st_mtime, reverse=True)
    return str(apks[0]) if apks else None

found = newest_apk(variant_dir) or newest_apk(root)
if found:
    print(found)
PY
)"
    if [[ -n "${FOUND_APK}" ]]; then
        BASE_NAME="help-muizen-hotel"
        if [[ "${NO_ASSETS}" -eq 1 ]]; then
            BASE_NAME="help-muizen-hotel-no-assets"
        fi

        FOUND_BASENAME="$(basename "${FOUND_APK}")"
        if [[ "${DEBUG_APK}" -eq 1 ]]; then
            APK_NAME="${BASE_NAME}-debug.apk"
        elif [[ "${FOUND_BASENAME}" == *-unsigned.apk ]]; then
            APK_NAME="${BASE_NAME}-unsigned.apk"
        else
            APK_NAME="${BASE_NAME}.apk"
        fi

        APK_DEST="${OUT_DIR}/${APK_NAME}"
        cp "${FOUND_APK}" "${APK_DEST}"
        echo "APK ready: ${APK_DEST}"
        python3 - "${APK_DEST}" <<'PY'
import sys
import zipfile

apk_path = sys.argv[1]
with zipfile.ZipFile(apk_path, "r") as zf:
    try:
        info = zf.getinfo("assets/game.love")
    except KeyError:
        print(f"Warning: assets/game.love not found inside {apk_path}", file=sys.stderr)
        sys.exit(0)
    if info.compress_type == zipfile.ZIP_STORED:
        print(f"Verified: assets/game.love is STORED (uncompressed) in {apk_path}")
    else:
        print(
            f"Warning: assets/game.love uses compress_type={info.compress_type} in {apk_path} (expected ZIP_STORED=0)",
            file=sys.stderr,
        )
PY
        if [[ "${APK_NAME}" == *-unsigned.apk ]]; then
            echo "Warning: ${APK_NAME} is unsigned and cannot be installed on Android until signed (or rebuild with --debug)." >&2
        fi
    else
        echo "Warning: Gradle finished, but no APK was found under ${APK_OUTPUTS_DIR}." >&2
    fi
fi
