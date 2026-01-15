#!/bin/bash

# 請確保你已經先安裝了 Xcode Command Line Tools 和 fastlane

# 取得腳本運行的目錄作為專案路徑
project_path="$(cd "$(dirname "$0")" && pwd)"
project_xcode="$project_path/eisonAI.xcodeproj"

# 會導致無法 Build
rm "/Volumes/Data/Github/eisonAI/Shared (Extension)/Resources/webllm-assets/models/Qwen3-0.6B-q4f16_1-MLC/resolve/main/README.md"

# 檢查參數是否提供新版本號
if [ -z "$1" ]; then
    MARKETING_VERSION=$(xcodebuild -showBuildSettings -project $project_xcode 2>/dev/null | awk -F" = " '/MARKETING_VERSION/{print $2}')
    echo "MARKETING_VERSION: $MARKETING_VERSION"
    echo "請提供新版本號作為腳本參數。"
    echo "使用方式: ./new_version.sh 1.1 ios|macos|all"
    exit 1
fi

# 設定新版本號
new_version="$1"

gemini --yolo "1. 讀取 notion page「eisonAI 更新日誌」；只需要回報「最新版本」的更新內容，不附帶其他版本；2. 把「最新版本」內容，翻譯到自然的英語，然後寫入 /Volumes/Data/Github/eisonAI/fastlane/changelog.txt；"

gemini --yolo "1. 讀取 notion page「eisonAI 更新日誌」；只需要回報「最新版本」的更新內容，不附帶其他版本；2. 把「最新版本」內容，然後寫入 /Volumes/Data/Github/eisonAI/telegram/changelog.md；"

# 修改 MARKETING_VERSION
sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = $new_version;/g" "$project_xcode/project.pbxproj"

echo "已修改 MARKETING_VERSION 為：$new_version"

# 發佈平台
if [ -z "$2" ]; then
    echo "請提供發佈平台：ios | macos | all"
    echo "使用方式: ./new_version.sh 1.1 ios"
    exit 1
fi

case "$2" in
    ios)
        lane="ios"
        ;;
    macos|mac)
        lane="mac"
        ;;
    all)
        lane="all"
        ;;
    *)
        echo "未知平台: $2"
        echo "請使用 ios | macos | all"
        exit 1
        ;;
esac

cd "$project_path"
fastlane ios "$lane"
