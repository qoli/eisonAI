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
copilot_max_autopilot_continues="${COPILOT_MAX_AUTOPILOT_CONTINUES:-10}"

usage() {
    echo "使用方式: ./new_version.sh <version> [platform] [method]"
    echo "例如: ./new_version.sh 1.1"
    echo "例如: ./new_version.sh 1.1 ios tf"
    echo "platform: ios | macos | all"
    echo "method: tf | release"
    echo "預設: platform=all, method=release"
}

fail() {
    echo "錯誤: $*" >&2
    exit 1
}

ensure_clean_worktree() {
    cd "$project_path"

    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        fail "目前目錄不是 git repository：$project_path"
    fi

    if [ -n "$(git status --porcelain=v1)" ]; then
        echo "工作區不是空的，請先 commit/stash/清理後再發佈：" >&2
        git status --short >&2
        exit 1
    fi
}

ensure_release_tag_available() {
    local tag_name="v$1"

    if git rev-parse -q --verify "refs/tags/$tag_name" >/dev/null; then
        fail "tag 已存在：$tag_name"
    fi
}

commit_and_tag_release() {
    local version="$1"
    local tag_name="v$version"

    cd "$project_path"
    ensure_release_tag_available "$version"

    git add -u -- .

    if git diff --cached --quiet; then
        fail "發佈成功，但沒有可提交的版本變更。"
    fi

    echo "準備提交 release 變更："
    git diff --cached --name-status

    git commit -m "chore(release): $tag_name"
    git tag -a "$tag_name" -m "Release $tag_name"

    echo "已建立 release commit 並標註 tag：$tag_name"
}

require_non_empty_file() {
    local file_path="$1"
    if [ ! -s "$file_path" ]; then
        echo "缺少輸出檔案或內容為空：$file_path" >&2
        return 1
    fi
}

validation_error=""

extract_version_headings() {
    local file_path="$1"
    grep -E '^## [0-9]+(\.[0-9]+)*$' "$file_path" | sed 's/^## //'
}

single_version_for_file() {
    local file_path="$1"
    local label="$2"
    local headings
    local versions
    local total_count
    local unique_count

    headings="$(extract_version_headings "$file_path")"
    versions="$(printf '%s\n' "$headings" | sed '/^$/d' | sort -u)"
    total_count="$(printf '%s\n' "$headings" | sed '/^$/d' | wc -l | tr -d ' ')"
    unique_count="$(printf '%s\n' "$versions" | sed '/^$/d' | wc -l | tr -d ' ')"

    if [ "$total_count" -ne 1 ] || [ "$unique_count" -ne 1 ]; then
        validation_error="$label 必須剛好包含一個純版本 heading，目前找到 $total_count 個 heading、$unique_count 個版本。"
        return 1
    fi

    printf '%s\n' "$versions"
}

validate_changelog_outputs() {
    local english_changelog="$project_path/fastlane/changelog.txt"
    local telegram_changelog="$project_path/telegram/changelog.md"
    local english_version
    local telegram_version

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

    if grep -q '[[:alpha:]]*[一-龥ぁ-んァ-ヶ가-힣]' "$english_changelog"; then
        validation_error="fastlane/changelog.txt 仍然殘留非英文東亞文字。"
        echo "$validation_error" >&2
        return 1
    fi

    if ! english_version="$(single_version_for_file "$english_changelog" "fastlane/changelog.txt")"; then
        echo "$validation_error" >&2
        return 1
    fi

    if ! telegram_version="$(single_version_for_file "$telegram_changelog" "telegram/changelog.md")"; then
        echo "$validation_error" >&2
        return 1
    fi

    if [ "$english_version" != "$telegram_version" ]; then
        validation_error="兩個 changelog 的版本 heading 不一致：fastlane=$english_version, telegram=$telegram_version。"
        echo "$validation_error" >&2
        return 1
    fi

    if ! grep -q '[一-龥]' "$telegram_changelog"; then
        validation_error="telegram/changelog.md 必須保留中文內容，不能是純英文翻譯版。"
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
        printf '    --max-autopilot-continues %q \\\n' "$copilot_max_autopilot_continues"
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
兩個檔案都必須剛好包含一行完全符合 ## x.y 的版本 heading，例如 ## 1.4。
telegram/changelog.md 必須保留中文，不可改寫成英文版。
不要使用 ## 未發佈 - 日期、不要省略版本 heading、不要只輸出條列內容。
仍需使用 translation-validator agent 做唯讀驗證；不要呼叫其他 agent/subtask。
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
platform="${2:-all}"
method="${3:-release}"

ensure_clean_worktree

case "$platform" in
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
        echo "未知平台: $platform"
        usage
        exit 1
        ;;
esac

case "$method" in
    tf)
        lane_suffix="tf"
        ;;
    release)
        lane_suffix="release"
        ensure_release_tag_available "$new_version"
        ;;
    *)
        echo "未知發佈方法: $method"
        usage
        exit 1
        ;;
esac

lane="${lane_prefix}_${lane_suffix}"

if [ ! -x "$copilot_wrapper" ]; then
    echo "找不到可執行的 callCopilot.sh：$copilot_wrapper"
    exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
    echo "找不到 tmux，請先安裝 tmux。" >&2
    exit 1
fi

copilot_prompt=$(cat <<EOF
直接呼叫 Notion MCP 讀取 page 2e2c1b36c40180849002d41f8892a5c7，不要先檢查工具列表。只從主頁正文找純版本 heading：## x.y。
選數值最大的版本，只取該 heading 到下一個純版本 heading 前的內容；不要混入頁首子頁、說明文字或舊版本。

覆寫這兩個文件：
- ${project_path}/fastlane/changelog.txt：英文 plain text，保留同一行 ## x.y 版本 heading，不要 HTML 或中文。
- ${project_path}/telegram/changelog.md：中文 Telegram markdown，保留同一行 ## x.y 版本 heading，不要翻成英文。

父目錄已存在，直接寫入上述完整路徑；不要用 shell input 或 bash 建目錄/寫檔。
寫完後只呼叫 translation-validator agent 做唯讀驗證；validator 只讀兩個輸出檔，不讀 Notion/web/curl。
驗證：兩檔非空、各只有一個 ## x.y、版本一致、英文檔無 HTML/中文、Telegram 檔有中文、無舊版本 heading。
呼叫 validator 時帶 name=translation-validator 並同步等待；不要用 background/read_agent。validator FAIL 時由 main agent 修檔後再驗證；validator PASS 後才 task_complete。不要使用 web/browser/HTML，也不要呼叫其他 agent/subtask。
最後只輸出：SUCCESS/FAIL、version: x.y、validator: PASS/FAIL、files: written。
EOF
)

generate_changelog_with_retry

# 修改 MARKETING_VERSION
sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = $new_version;/g" "$project_xcode/project.pbxproj"

echo "已修改 MARKETING_VERSION 為：$new_version"

cd "$project_path"
fastlane ios "$lane"

if [ "$method" = "release" ]; then
    commit_and_tag_release "$new_version"
fi
