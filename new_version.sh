#!/bin/bash
set -euo pipefail

# 請確保你已經先安裝了 Xcode Command Line Tools 和 fastlane

# 取得腳本運行的目錄作為專案路徑
project_path="$(cd "$(dirname "$0")" && pwd)"
project_xcode="$project_path/eisonAI.xcodeproj"
copilot_wrapper="/Volumes/Data/Github/macOSAgentBot/callCopilot.sh"
copilot_home_seed="$HOME/.copilot"
copilot_run_root="$project_path/logs/new_version_copilot"
copilot_task_complete_grace_period=10

usage() {
    echo "使用方式: ./new_version.sh <version> <platform> <method>"
    echo "例如: ./new_version.sh 1.1 ios tf"
    echo "platform: ios | macos | all"
    echo "method: tf | release"
}

require_non_empty_file() {
    local file_path="$1"
    if [ ! -s "$file_path" ]; then
        echo "缺少輸出檔案或內容為空：$file_path" >&2
        return 1
    fi
}

validation_error=""

validate_changelog_outputs() {
    local english_changelog="$project_path/fastlane/changelog.txt"
    local telegram_changelog="$project_path/telegram/changelog.md"

    validation_error=""

    if ! require_non_empty_file "$english_changelog"; then
        validation_error="缺少輸出檔案或內容為空：$english_changelog"
        return 1
    fi

    if ! require_non_empty_file "$telegram_changelog"; then
        validation_error="缺少輸出檔案或內容為空：$telegram_changelog"
        return 1
    fi

    if grep -Eq '<[^>]+>' "$english_changelog"; then
        validation_error="fastlane/changelog.txt 仍然包含 HTML 標籤。"
        echo "$validation_error" >&2
        return 1
    fi

    if ! grep -Eq '^## [0-9]+(\.[0-9]+)*$' "$english_changelog"; then
        validation_error="fastlane/changelog.txt 缺少版本 heading。"
        echo "$validation_error" >&2
        return 1
    fi

    if ! grep -Eq '^## [0-9]+(\.[0-9]+)*$' "$telegram_changelog"; then
        validation_error="telegram/changelog.md 缺少版本 heading。"
        echo "$validation_error" >&2
        return 1
    fi

    return 0
}

seed_copilot_home() {
    local destination="$1"

    mkdir -p "$destination/session-state"

    if [ -f "$copilot_home_seed/config.json" ]; then
        cp "$copilot_home_seed/config.json" "$destination/config.json"
    fi

    if [ -f "$copilot_home_seed/mcp-config.json" ]; then
        cp "$copilot_home_seed/mcp-config.json" "$destination/mcp-config.json"
    fi

    if [ -d "$copilot_home_seed/mcp-oauth-config" ]; then
        cp -R "$copilot_home_seed/mcp-oauth-config" "$destination/mcp-oauth-config"
    fi
}

monitor_copilot_task_complete() {
    local session_name="$1"
    local copilot_home="$2"
    local events_file=""

    while tmux has-session -t "$session_name" 2>/dev/null; do
        events_file="$(find "$copilot_home/session-state" -mindepth 2 -maxdepth 2 -name events.jsonl -print -quit 2>/dev/null || true)"
        if [ -n "$events_file" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "$events_file" ]; then
        return 0
    fi

    echo "監控 Copilot session 事件：$events_file"

    while tmux has-session -t "$session_name" 2>/dev/null; do
        if rg -q '"type":"session\.task_complete".*"success":true' "$events_file"; then
            echo "偵測到 session.task_complete，${copilot_task_complete_grace_period} 秒後自動關閉 tmux session：$session_name"
            sleep "$copilot_task_complete_grace_period"

            if tmux has-session -t "$session_name" 2>/dev/null; then
                tmux kill-session -t "$session_name"
            fi
            return 0
        fi
        sleep 1
    done

    return 0
}

run_copilot_prompt() {
    local prompt_text="$1"
    local run_dir
    local copilot_home
    local prompt_file
    local runner_script
    local session_name
    local monitor_pid=""
    local attach_status=0

    mkdir -p "$copilot_run_root"
    run_dir="$(mktemp -d "$copilot_run_root/run.XXXXXX")"
    copilot_home="$run_dir/copilot-home"
    prompt_file="$run_dir/prompt.txt"
    runner_script="$run_dir/run-copilot.sh"
    session_name="new-version-$$-$(date +%s)-$RANDOM"

    seed_copilot_home "$copilot_home"
    printf '%s' "$prompt_text" > "$prompt_file"

    {
        echo '#!/bin/bash'
        echo 'set -euo pipefail'
        printf 'cd %q\n' "$project_path"
        printf 'PROMPT_FILE=%q\n' "$prompt_file"
        printf 'COPILOT_HOME=%q exec %q \\\n' "$copilot_home" "$copilot_wrapper"
        echo '    --autopilot \'
        echo '    --allow-all \'
        echo '    --no-ask-user \'
        echo '    --no-remote \'
        echo '    --max-autopilot-continues 12 \'
        echo '    -i "$(cat "$PROMPT_FILE")"'
    } > "$runner_script"
    chmod +x "$runner_script"

    echo "Copilot 執行目錄：$run_dir"
    echo "tmux session：$session_name"

    tmux new-session -d -s "$session_name" "$runner_script"
    monitor_copilot_task_complete "$session_name" "$copilot_home" &
    monitor_pid=$!

    if [ -n "${TMUX:-}" ]; then
        TMUX= tmux attach-session -t "$session_name" || attach_status=$?
    else
        tmux attach-session -t "$session_name" || attach_status=$?
    fi

    if [ -n "$monitor_pid" ] && kill -0 "$monitor_pid" 2>/dev/null; then
        kill "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true
    fi

    if [ "$attach_status" -ne 0 ] && tmux has-session -t "$session_name" 2>/dev/null; then
        return "$attach_status"
    fi
}

generate_changelog_with_retry() {
    local max_attempts=3
    local attempt=1
    local prompt_text="$copilot_prompt"

    while [ "$attempt" -le "$max_attempts" ]; do
        echo "生成 changelog，第 $attempt/$max_attempts 次嘗試..."
        run_copilot_prompt "$prompt_text"

        if validate_changelog_outputs; then
            echo "changelog 驗證通過。"
            return 0
        fi

        if [ "$attempt" -ge "$max_attempts" ]; then
            echo "changelog 驗證失敗，已達最大重試次數：$validation_error" >&2
            return 1
        fi

        prompt_text=$(cat <<EOF
$copilot_prompt

上一次輸出驗證失敗，原因如下：
$validation_error

請直接覆寫 $project_path/fastlane/changelog.txt 與 $project_path/telegram/changelog.md。
兩個檔案都必須包含且至少包含一行完全符合 ## x.y 的版本 heading，例如 ## 1.4。
不要使用 ## 未發佈 - 日期、不要省略版本 heading、不要只輸出條列內容。
EOF
)

        attempt=$((attempt + 1))
    done

    return 1
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

if ! command -v tmux >/dev/null 2>&1; then
    echo "找不到 tmux，請先安裝 tmux。" >&2
    exit 1
fi

copilot_prompt=$(cat <<EOF
1. 先檢查當前可用工具中是否存在 notion MCP / notion 相關工具；如果不存在，只能報錯一次並停止，不要重複道歉或重複輸出相同內容。
2. 如果 notion 工具存在，必須使用該 notion MCP 工具讀取 page 2e2c1b36c40180849002d41f8892a5c7，不要使用 web fetch、瀏覽器抓取、或 HTML 解析。
3. 只從主頁正文中尋找版本 heading，版本 heading 的格式是 ## x.y。不要把頁首子頁、頁面說明文字、封面摘要、或其他非 ## x.y heading 內容當成版本內容。
4. 抽取所有 ## x.y 版本 heading，按版本號大小比較，選出數值最大的版本。只提取該版本區塊直到下一個版本 heading 之前的內容，不要附帶其他版本。
5. 如果你最終抽取到的區塊混入了更舊版本內容，直接報錯並停止，不要寫出錯誤文件。
6. 必須真的寫入兩個文件，而不是只在終端回覆。
7. 英文 changelog 也必須明確保留你選中的最新版本號，不能只輸出條列內容。請用 plain-text 形式寫入 $project_path/fastlane/changelog.txt。
8. 把最新版本內容翻譯成自然英語，移除所有 HTML 標籤、HTML 實體、以及多餘的 Notion 標記，寫入 $project_path/fastlane/changelog.txt。
9. 把最新版本內容保留版本號，整理成適合 Telegram 的 markdown，寫入 $project_path/telegram/changelog.md。
10. fastlane/changelog.txt 與 telegram/changelog.md 都必須至少包含一行完全符合 ## x.y 的版本 heading，例如 ## 1.4。不要使用 ## 未發佈 - 日期 或其他非純版本號 heading。
11. 如果任一輸出缺少你選中的最新版本號，直接視為失敗。
12. 完成後，最後只回報這兩個文件是否成功寫入，以及你提取到的版本號。
EOF
)

generate_changelog_with_retry

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
