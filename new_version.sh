#!/bin/bash
set -euo pipefail

# 請確保你已經先安裝了 Xcode Command Line Tools 和 fastlane

# 取得腳本運行的目錄作為專案路徑
project_path="$(cd "$(dirname "$0")" && pwd)"
project_xcode="$project_path/eisonAI.xcodeproj"
copilot_wrapper="/Volumes/Data/Github/macOSAgentBot/callCopilot.sh"

usage() {
    echo "使用方式: ./new_version.sh <version> <platform> <method>"
    echo "例如: ./new_version.sh 1.1 ios tf"
    echo "platform: ios | macos | all"
    echo "method: tf | release"
}

require_non_empty_file() {
    local file_path="$1"
    if [ ! -s "$file_path" ]; then
        echo "缺少輸出檔案或內容為空：$file_path"
        exit 1
    fi
}

validate_changelog_outputs() {
    local english_changelog="$project_path/fastlane/changelog.txt"
    local telegram_changelog="$project_path/telegram/changelog.md"

    require_non_empty_file "$english_changelog"
    require_non_empty_file "$telegram_changelog"

    if grep -Eq '<[^>]+>' "$english_changelog"; then
        echo "fastlane/changelog.txt 仍然包含 HTML 標籤。"
        exit 1
    fi

    if ! grep -Eq '^## [0-9]+(\.[0-9]+)*$' "$english_changelog"; then
        echo "fastlane/changelog.txt 缺少版本 heading。"
        exit 1
    fi

    if ! grep -Eq '^## [0-9]+(\.[0-9]+)*$' "$telegram_changelog"; then
        echo "telegram/changelog.md 缺少版本 heading。"
        exit 1
    fi
}

# 檢查參數是否提供新版本號
if [ -z "${1:-}" ]; then
    MARKETING_VERSION=$(xcodebuild -showBuildSettings -project "$project_xcode" 2>/dev/null | awk -F" = " '/MARKETING_VERSION/{print $2}')
    echo "MARKETING_VERSION: $MARKETING_VERSION"
    echo "請提供新版本號作為腳本參數。"
    usage
    exit 1
fi

# 設定新版本號
new_version="$1"

if [ ! -x "$copilot_wrapper" ]; then
    echo "找不到可執行的 callCopilot.sh：$copilot_wrapper"
    exit 1
fi

copilot_prompt=$(cat <<EOF
1. 先檢查當前可用工具中是否存在 notion MCP / notion 相關工具；如果不存在，只能報錯一次並停止，不要重複道歉或重複輸出相同內容。
2. 如果 notion 工具存在，必須使用該 notion MCP 工具讀取 page `2e2c1b36c40180849002d41f8892a5c7`，不要使用 web fetch、瀏覽器抓取、或 HTML 解析。
3. 只從主頁正文中尋找版本 heading，版本 heading 的格式是 `## x.y`。不要把頁首子頁、頁面說明文字、封面摘要、或其他非 `## x.y` heading 內容當成版本內容。
4. 抽取所有 `## x.y` 版本 heading，按版本號大小比較，選出數值最大的版本。只提取該版本區塊直到下一個版本 heading 之前的內容，不要附帶其他版本。
5. 如果你最終抽取到的區塊混入了更舊版本內容，直接報錯並停止，不要寫出錯誤文件。
6. 必須真的寫入兩個文件，而不是只在終端回覆。
7. 英文 changelog 也必須明確保留你選中的最新版本號，不能只輸出條列內容。請用 plain-text 形式寫入 $project_path/fastlane/changelog.txt。
8. 把最新版本內容翻譯成自然英語，移除所有 HTML 標籤、HTML 實體、以及多餘的 Notion 標記，寫入 $project_path/fastlane/changelog.txt。
9. 把最新版本內容保留版本號，整理成適合 Telegram 的 markdown，寫入 $project_path/telegram/changelog.md。
10. 如果任一輸出缺少你選中的最新版本號，直接視為失敗。
11. 完成後，最後只回報這兩個文件是否成功寫入，以及你提取到的版本號。
EOF
)

"$copilot_wrapper" \
    --autopilot \
    --allow-all \
    --no-ask-user \
    --no-remote \
    --max-autopilot-continues 12 \
    -p "$copilot_prompt"

validate_changelog_outputs

# 修改 MARKETING_VERSION
sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = $new_version;/g" "$project_xcode/project.pbxproj"

echo "已修改 MARKETING_VERSION 為：$new_version"

# 發佈平台
if [ -z "${2:-}" ]; then
    echo "請提供發佈平台。"
    usage
    exit 1
fi

if [ -z "${3:-}" ]; then
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
