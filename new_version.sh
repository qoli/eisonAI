#!/bin/bash

# 請確保你已經先安裝了 Xcode Command Line Tools 和 fastlane

# 取得腳本運行的目錄作為專案路徑
project_path="$(cd "$(dirname "$0")" && pwd)"
project_xcode="$project_path/eisonAI.xcodeproj"

usage() {
    echo "使用方式: ./new_version.sh <version> <platform> <method>"
    echo "例如: ./new_version.sh 1.1 ios tf"
    echo "platform: ios | macos | all"
    echo "method: tf | release"
}

# 檢查參數是否提供新版本號
if [ -z "$1" ]; then
    MARKETING_VERSION=$(xcodebuild -showBuildSettings -project "$project_xcode" 2>/dev/null | awk -F" = " '/MARKETING_VERSION/{print $2}')
    echo "MARKETING_VERSION: $MARKETING_VERSION"
    echo "請提供新版本號作為腳本參數。"
    usage
    exit 1
fi

# 設定新版本號
new_version="$1"

if ! command -v qwen >/dev/null 2>&1; then
    echo "找不到 qwen CLI，請先安裝或加入 PATH。"
    exit 1
fi

qwen -p "$(cat <<EOF
1. 讀取 notion page「eisonAI 更新日誌」；只需要回報「最新版本」的更新內容，不附帶其他版本；
2. 把「最新版本」內容，翻譯到自然的英語(不能含有任何 HTML 標籤)，然後寫入 $project_path/fastlane/changelog.txt；
3. 把「最新版本」內容，保留最新版本號，然後寫入 $project_path/telegram/changelog.md；
EOF
)"

# 修改 MARKETING_VERSION
sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = $new_version;/g" "$project_xcode/project.pbxproj"

echo "已修改 MARKETING_VERSION 為：$new_version"

# 發佈平台
if [ -z "$2" ]; then
    echo "請提供發佈平台。"
    usage
    exit 1
fi

if [ -z "$3" ]; then
    echo "請提供發佈方法。"
    usage
    exit 1
fi

case "$2" in
    ios)
        lane_prefix="ios"
        ;;
    macos|mac)
        lane_prefix="mac"
        ;;
    all)
        lane_prefix="all"
        ;;
    *)
        echo "未知平台: $2"
        usage
        exit 1
        ;;
esac

case "$3" in
    tf)
        lane_suffix="tf"
        ;;
    release)
        lane_suffix="release"
        ;;
    *)
        echo "未知發佈方法: $3"
        usage
        exit 1
        ;;
esac

lane="${lane_prefix}_${lane_suffix}"

cd "$project_path"
fastlane ios "$lane"
