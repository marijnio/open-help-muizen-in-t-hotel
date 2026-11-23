#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${ROOT_DIR}/dist"
NO_ASSETS=0
BUILD_APK=0
DEBUG_APK=0
PUSH_ASSETS=0
PACKAGE_NAME="org.love2d.android"
LOVE_ANDROID_DIR="${LOVE_ANDROID_DIR:-${ROOT_DIR}/love-android}"
ICON_SOURCE=""

usage() {
    cat <<'EOF'
Usage: scripts/build_android.sh [options]

Packages Help! Muizen in 't hotel as a .love archive and optionally builds an
Android APK using love-android or pushes side-loaded assets via adb.

Options:
  --no-assets        Build a lightweight .love without assets/ (for side-loading)
  --output <dir>     Output directory for .love / .apk (default: dist)
  --build-apk        Build APK via love-android (uses $LOVE_ANDROID_DIR or ./love-android)
  --debug            Build debug APK instead of release when --build-apk is set
  --icon <path>      Optional source image for Android launcher icons
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
        --debug)
            DEBUG_APK=1
            shift
            ;;
        --icon)
            ICON_SOURCE="$2"
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

ZIP_ARGS=(
    -r -9 "${LOVE_PATH}"
    main.lua conf.lua src
)
if [[ "${NO_ASSETS}" -eq 0 ]]; then
    ZIP_ARGS+=(assets)
fi

(
    cd "${ROOT_DIR}"
    zip "${ZIP_ARGS[@]}" -x \
        "*.DS_Store" \
        "*/__pycache__/*" \
        "*.pyc" \
        "local_config.lua" \
        "backup/*" \
        "tools/*" \
        "scripts/*" \
        "dist/*" \
        "build/*" \
        "love-android/*" \
        ".git/*" >/dev/null
)

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
    if [[ ! -d "${LOVE_ANDROID_DIR}" ]]; then
        echo "Error: love-android directory not found at ${LOVE_ANDROID_DIR}." >&2
        echo "Clone love-android or set LOVE_ANDROID_DIR=/path/to/love-android." >&2
        exit 1
    fi

    EMBED_ASSETS_DIR="${LOVE_ANDROID_DIR}/app/src/embed/assets"
    mkdir -p "${EMBED_ASSETS_DIR}"
    cp "${LOVE_PATH}" "${EMBED_ASSETS_DIR}/game.love"
    echo "Copied ${LOVE_PATH} -> ${EMBED_ASSETS_DIR}/game.love"

    RES_DIR="${LOVE_ANDROID_DIR}/app/src/main/res"
    ICON_ARGS=(--output "${RES_DIR}")
    if [[ -n "${ICON_SOURCE}" ]]; then
        ICON_ARGS+=(--source "${ICON_SOURCE}")
    elif [[ "${NO_ASSETS}" -eq 0 && -f "${ROOT_DIR}/assets/images/bmp/muizen.png" ]]; then
        ICON_ARGS+=(--source "${ROOT_DIR}/assets/images/bmp/muizen.png")
    fi
    python3 "${ROOT_DIR}/scripts/generate_android_icons.py" "${ICON_ARGS[@]}"

    MANIFEST_FILE="${LOVE_ANDROID_DIR}/app/src/main/AndroidManifest.xml"
    if [[ -f "${MANIFEST_FILE}" ]]; then
        python3 - "${MANIFEST_FILE}" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8")
if 'android:screenOrientation=' in txt:
    new_txt = re.sub(r'android:screenOrientation="[^"]+"', 'android:screenOrientation="sensorLandscape"', txt, count=1)
else:
    new_txt = txt.replace('<activity ', '<activity android:screenOrientation="sensorLandscape" ', 1)
if new_txt != txt:
    p.write_text(new_txt, encoding="utf-8")
    print(f"Updated screenOrientation=sensorLandscape in {p}")
PY
    fi

    GRADLE_TASK="assembleEmbedNoRecordRelease"
    if [[ "${DEBUG_APK}" -eq 1 ]]; then
        GRADLE_TASK="assembleEmbedNoRecordDebug"
    fi
    echo "Running Gradle task ${GRADLE_TASK} in ${LOVE_ANDROID_DIR}..."
    (
        cd "${LOVE_ANDROID_DIR}"
        ./gradlew "${GRADLE_TASK}"
    )

    FOUND_APK="$(find "${LOVE_ANDROID_DIR}/app/build/outputs/apk" -name "*.apk" | head -n 1 || true)"
    if [[ -n "${FOUND_APK}" ]]; then
        APK_DEST="${OUT_DIR}/$(basename "${FOUND_APK}")"
        cp "${FOUND_APK}" "${APK_DEST}"
        echo "APK ready: ${APK_DEST}"
    else
        echo "Warning: Gradle finished, but no APK was found under app/build/outputs/apk." >&2
    fi
fi
