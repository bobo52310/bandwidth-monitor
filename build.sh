#!/bin/bash

# 建置類型參數 (debug/release)
CONFIG=${1:-Debug}

echo "Building NetworkPeakMonitor ($CONFIG)..."

# 建置
xcodebuild -workspace NetworkPeakMonitor.xcworkspace \
           -scheme NetworkPeakMonitor \
           -configuration $CONFIG \
           build

if [ $? -eq 0 ]; then
    echo "Build successful!"

    # 找到 app 路徑
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData \
                    -name "NetworkPeakMonitor.app" \
                    -path "*/$CONFIG/*" \
                    -maxdepth 6 \
                    2>/dev/null | head -1)

    if [ -n "$APP_PATH" ]; then
        echo "Launching app: $APP_PATH"
        open "$APP_PATH"
    else
        echo "Could not find built app"
        # 備用路徑
        echo "Trying alternative path..."
        open ~/Library/Developer/Xcode/DerivedData/NetworkPeakMonitor-*/Build/Products/$CONFIG/NetworkPeakMonitor.app
    fi
else
    echo "Build failed!"
    exit 1
fi