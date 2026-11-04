#!/bin/bash
# Usage: ./build.sh [debug|release] [--run]
#
#   debug    Debug build for arm64 (default). Bundle ID com.bobo52310.BandwidthECG.debug
#   release  Universal Release build. Uses the REAL bundle ID, so it is never launched.
#   --run    Launch the app after building. Debug only.

set -euo pipefail

cd "$(dirname "$0")"

CONFIG_ARG="Debug"
RUN=0

for arg in "$@"; do
    case "$arg" in
        --run)
            RUN=1
            ;;
        *)
            CONFIG_ARG="$arg"
            ;;
    esac
done

# Normalize the configuration name (case-insensitive).
CONFIG_LOWER=$(printf '%s' "$CONFIG_ARG" | tr '[:upper:]' '[:lower:]')
case "$CONFIG_LOWER" in
    debug)
        CONFIG="Debug"
        DESTINATION="platform=macOS,arch=arm64"
        ;;
    release)
        CONFIG="Release"
        DESTINATION="generic/platform=macOS"
        ;;
    *)
        echo "Unknown configuration: $CONFIG_ARG (expected debug or release)" >&2
        echo "Usage: ./build.sh [debug|release] [--run]" >&2
        exit 2
        ;;
esac

# Release uses the real bundle ID and the real sandbox container. Refuse before building.
if [ "$RUN" -eq 1 ] && [ "$CONFIG" = "Release" ]; then
    echo "Release uses the real bundle ID; use the QA copy" >&2
    exit 2
fi

echo "Building BandwidthECG ($CONFIG)..."

xcodebuild -workspace BandwidthECG.xcworkspace \
           -scheme BandwidthECG \
           -configuration "$CONFIG" \
           -destination "$DESTINATION" \
           -derivedDataPath .build/DerivedData \
           build

APP_PATH=".build/DerivedData/Build/Products/$CONFIG/BandwidthECG.app"

echo "Build successful!"
echo "$APP_PATH"

if [ "$RUN" -eq 1 ]; then
    echo "Launching $APP_PATH"
    open "$APP_PATH"
fi
