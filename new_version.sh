#!/bin/bash

# 請確保你已經先安裝了 Xcode Command Line Tools 和 fastlane

# 取得腳本運行的目錄作為專案路徑
project_path=$(dirname "$0")
project_xcode="$project_path/eisonAI.xcodeproj"

# 檢查參數是否提供新版本號
if [ -z "$1" ]; then
    MARKETING_VERSION=$(xcodebuild -showBuildSettings -project $project_xcode 2>/dev/null | awk -F" = " '/MARKETING_VERSION/{print $2}')
    echo "MARKETING_VERSION: $MARKETING_VERSION"
    echo "請提供新版本號作為腳本參數。"
    echo "使用方式: ./new_version.sh 1.1"
    exit 1
fi

# 設定新版本號
new_version="$1"

# 修改 MARKETING_VERSION
sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = $new_version;/g" "$project_xcode/project.pbxproj"

echo "已修改 MARKETING_VERSION 為：$new_version"

fastlane all