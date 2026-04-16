#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
copilot_wrapper="/Volumes/Data/Github/macOSAgentBot/callCopilot.sh"
mcp_config_source="$HOME/.copilot/mcp-config.json"
page_id="2e2c1b36c40180849002d41f8892a5c7"
expected_version="2.7"
default_output_dir="$repo_root/logs/test_callcopilot_notion_changelog"

usage() {
    echo "Usage: Scripts/test_callcopilot_notion_changelog.sh [output-dir]"
    echo "If output-dir is omitted, the repo-local test directory will be used:"
    echo "  $default_output_dir"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if [ ! -x "$copilot_wrapper" ]; then
    echo "Missing executable callCopilot.sh: $copilot_wrapper" >&2
    exit 1
fi

if [ -n "${1:-}" ]; then
    output_dir="$1"
else
    output_dir="$default_output_dir"
fi

rm -rf "$output_dir"
mkdir -p "$output_dir/copilot-home"

prompt_file="$output_dir/prompt.txt"
stdout_file="$output_dir/stdout.log"
stderr_file="$output_dir/stderr.log"
english_file="$output_dir/changelog.txt"
telegram_file="$output_dir/changelog.md"

if [ -f "$mcp_config_source" ]; then
    cp "$mcp_config_source" "$output_dir/copilot-home/mcp-config.json"
fi

cat > "$prompt_file" <<EOF
1. 先檢查當前可用工具中是否存在 notion MCP / notion 相關工具；如果不存在，只能報錯一次並停止，不要重複道歉或重複輸出相同內容。
2. 如果 notion 工具存在，必須使用該 notion MCP 工具讀取 page \`${page_id}\`，不要使用 web fetch、瀏覽器抓取、或 HTML 解析。
3. 只從主頁正文中尋找版本 heading，版本 heading 的格式是 \`## x.y\`。不要把頁首子頁、頁面說明文字、封面摘要、或其他非 \`## x.y\` heading 內容當成版本內容。
4. 抽取所有 \`## x.y\` 版本 heading，按版本號大小比較，選出數值最大的版本。這一頁的最新版本應該是 \`${expected_version}\`。
5. 只提取 \`## ${expected_version}\` 之下、直到下一個版本 heading 之前的內容。不要附帶更舊版本的任何內容。
6. 如果你最終抽取到的版本不是 \`${expected_version}\`，或者內容中包含舊版本的開發衝刺報告，直接報錯並停止，不要寫出錯誤文件。
7. 必須真的寫入兩個文件，而不是只在終端回覆。
8. 英文 changelog 也必須明確保留版本號 \`${expected_version}\`，不要只輸出條列內容。請用 plain-text 形式寫入 ${english_file}。
9. 將 \`${expected_version}\` 的內容翻譯成自然英文，移除所有 HTML 標籤、HTML 實體、以及多餘的 Notion 標記，寫入 ${english_file}。
10. 將 \`${expected_version}\` 的內容保留版本號，整理成適合 Telegram 的 markdown，寫入 ${telegram_file}。
11. 如果任一輸出缺少版本號 \`${expected_version}\`，直接視為失敗。
12. 完成後，最後只回報這兩個文件是否成功寫入，以及你提取到的版本號。
EOF

COPILOT_HOME="$output_dir/copilot-home" \
"$copilot_wrapper" \
    --autopilot \
    --allow-all \
    --no-ask-user \
    --no-remote \
    --max-autopilot-continues 12 \
    -p "$(cat "$prompt_file")" \
    > "$stdout_file" \
    2> "$stderr_file"

echo "output_dir=$output_dir"
ls -la "$output_dir"
printf '\n--- stdout ---\n'
sed -n '1,200p' "$stdout_file"
printf '\n--- stderr ---\n'
sed -n '1,120p' "$stderr_file"
