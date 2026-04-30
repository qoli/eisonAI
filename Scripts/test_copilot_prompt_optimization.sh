#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
copilot_wrapper="/Volumes/Data/Github/macOSAgentBot/callCopilot.sh"
copilot_home_seed="$HOME/.copilot"
run_count="${1:-10}"
timestamp="$(date +%Y%m%d-%H%M%S)"
output_root="${2:-$repo_root/logs/copilot_prompt_optimization/$timestamp}"
max_continues="${COPILOT_MAX_AUTOPILOT_CONTINUES:-10}"
task_complete_grace_period="${COPILOT_TASK_COMPLETE_GRACE_PERIOD:-30}"
wall_timeout_seconds="${COPILOT_WALL_TIMEOUT_SECONDS:-900}"
prompt_mode="${COPILOT_PROMPT_MODE:-i}"
max_attempts="${COPILOT_MAX_TEST_ATTEMPTS:-}"
expected_version="${EXPECTED_VERSION:-}"

case "$output_root" in
    /*) ;;
    *) output_root="$repo_root/$output_root" ;;
esac

fail() {
    echo "錯誤: $*" >&2
    exit 1
}

require_non_empty_file() {
    local file_path="$1"
    [ -s "$file_path" ] || return 1
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

version_headings() {
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

    headings="$(version_headings "$file_path")"
    versions="$(printf '%s\n' "$headings" | sed '/^$/d' | sort -u)"
    total_count="$(printf '%s\n' "$headings" | sed '/^$/d' | wc -l | tr -d ' ')"
    unique_count="$(printf '%s\n' "$versions" | sed '/^$/d' | wc -l | tr -d ' ')"

    if [ "$total_count" -ne 1 ] || [ "$unique_count" -ne 1 ]; then
        echo "$label 必須剛好包含一個純版本 heading，目前找到 $total_count 個 heading、$unique_count 個版本。"
        return 1
    fi

    printf '%s\n' "$versions"
}

validate_outputs() {
    local english_changelog="$1"
    local telegram_changelog="$2"
    local english_version
    local telegram_version

    require_non_empty_file "$english_changelog" || {
        echo "fastlane changelog 缺失或為空。"
        return 1
    }
    require_non_empty_file "$telegram_changelog" || {
        echo "telegram changelog 缺失或為空。"
        return 1
    }

    if grep -Eq '<[^>]+>' "$english_changelog"; then
        echo "fastlane changelog 含 HTML 標籤。"
        return 1
    fi

    if grep -q '[[:alpha:]]*[一-龥ぁ-んァ-ヶ가-힣]' "$english_changelog"; then
        echo "fastlane changelog 殘留東亞文字。"
        return 1
    fi

    if ! grep -q '[一-龥]' "$telegram_changelog"; then
        echo "telegram changelog 不含中文。"
        return 1
    fi

    english_version="$(single_version_for_file "$english_changelog" "fastlane changelog")" || return 1
    telegram_version="$(single_version_for_file "$telegram_changelog" "telegram changelog")" || return 1

    if [ "$english_version" != "$telegram_version" ]; then
        echo "版本不一致：fastlane=$english_version telegram=$telegram_version。"
        return 1
    fi

    if [ -n "$expected_version" ] && [ "$english_version" != "$expected_version" ]; then
        echo "版本錯誤：expected=$expected_version actual=$english_version。"
        return 1
    fi

    printf '%s\n' "$english_version"
}

find_events_file() {
    local copilot_home="$1"

    find "$copilot_home/session-state" -mindepth 2 -maxdepth 2 -name events.jsonl -print -quit 2>/dev/null || true
}

wait_for_events_file() {
    local copilot_home="$1"
    local session_name="$2"
    local events_file=""

    while tmux has-session -t "$session_name" 2>/dev/null; do
        events_file="$(find_events_file "$copilot_home")"
        if [ -n "$events_file" ]; then
            printf '%s\n' "$events_file"
            return 0
        fi
        sleep 1
    done

    return 1
}

validator_passed() {
    local events_file="$1"

    [ -n "$events_file" ] || return 1
    rg -q '"agentName":"translation-validator"' "$events_file" || return 1
    rg -q 'status.*PASS' "$events_file"
}

build_prompt() {
    local english_file="$1"
    local telegram_file="$2"

    cat <<EOF
直接呼叫 Notion MCP 讀取 page 2e2c1b36c40180849002d41f8892a5c7，不要先檢查工具列表。只從主頁正文找純版本 heading：## x.y。
選數值最大的版本，只取該 heading 到下一個純版本 heading 前的內容；不要混入頁首子頁、說明文字或舊版本。

覆寫這兩個文件：
- ${english_file}：英文 plain text，保留同一行 ## x.y 版本 heading，不要 HTML 或中文。
- ${telegram_file}：中文 Telegram markdown，保留同一行 ## x.y 版本 heading，不要翻成英文。

父目錄已存在，直接寫入上述完整路徑；不要用 shell input 或 bash 建目錄/寫檔。
寫完後只呼叫 translation-validator agent 做唯讀驗證；validator 只讀兩個輸出檔，不讀 Notion/web/curl。
驗證：兩檔非空、各只有一個 ## x.y、版本一致、英文檔無 HTML/中文、Telegram 檔有中文、無舊版本 heading。
呼叫 validator 時帶 name=translation-validator 並同步等待；不要用 background/read_agent。validator FAIL 時由 main agent 修檔後再驗證；validator PASS 後才 task_complete。不要使用 web/browser/HTML，也不要呼叫其他 agent/subtask。
最後只輸出：SUCCESS/FAIL、version: x.y、validator: PASS/FAIL、files: written。
EOF
}

run_one() {
    local index="$1"
    local run_dir
    local copilot_home
    local prompt_file
    local english_file
    local telegram_file
    local runner_script
    local tmux_script
    local stdout_file
    local stderr_file
    local exit_code_file
    local session_name
    local events_file=""
    local killed_after_task_complete=0
    local completion="missing_task_complete"
    local validator_status="FAIL"
    local effective_status="FAIL"
    local started_at
    local ended_at
    local exit_code=0
    local validation_output
    local validation_status="FAIL"
    local version=""

    run_dir="$output_root/run.$(printf '%03d' "$index")"
    copilot_home="$run_dir/copilot-home"
    prompt_file="$run_dir/prompt.txt"
    english_file="$run_dir/changelog.txt"
    telegram_file="$run_dir/changelog.md"
    runner_script="$run_dir/run-copilot.sh"
    tmux_script="$run_dir/run-in-tmux.sh"
    stdout_file="$run_dir/stdout.log"
    stderr_file="$run_dir/stderr.log"
    exit_code_file="$run_dir/exit-code.txt"
    session_name="copilot-prompt-test-$$-$index-$RANDOM"

    mkdir -p "$run_dir"
    seed_copilot_home "$copilot_home"
    build_prompt "$english_file" "$telegram_file" > "$prompt_file"

    case "$prompt_mode" in
        i|p) ;;
        *) fail "COPILOT_PROMPT_MODE 只能是 i 或 p，目前是：$prompt_mode" ;;
    esac

    {
        echo '#!/bin/bash'
        echo 'set -euo pipefail'
        printf 'cd %q\n' "$repo_root"
        printf 'PROMPT_FILE=%q\n' "$prompt_file"
        printf 'COPILOT_HOME=%q exec %q \\\n' "$copilot_home" "$copilot_wrapper"
        echo '    --autopilot \'
        echo '    --allow-all \'
        echo '    --no-ask-user \'
        echo '    --no-remote \'
        printf '    --max-autopilot-continues %q \\\n' "$max_continues"
        printf '    -%s "$(cat "$PROMPT_FILE")"\n' "$prompt_mode"
    } > "$runner_script"
    chmod +x "$runner_script"

    {
        echo '#!/bin/bash'
        echo 'set +e'
        printf '%q > %q 2> %q\n' "$runner_script" "$stdout_file" "$stderr_file"
        printf 'printf "%%s\\n" "$?" > %q\n' "$exit_code_file"
    } > "$tmux_script"
    chmod +x "$tmux_script"

    echo "attempt $index, target effective $run_count: $run_dir"
    started_at="$(date +%s)"
    tmux new-session -d -s "$session_name" "$tmux_script"

    events_file="$(wait_for_events_file "$copilot_home" "$session_name" || true)"
    while tmux has-session -t "$session_name" 2>/dev/null; do
        if [ -n "$events_file" ] && rg -q '"type":"session\.task_complete".*"success":true' "$events_file"; then
            completion="task_complete"
            sleep "$task_complete_grace_period"
            if tmux has-session -t "$session_name" 2>/dev/null; then
                tmux kill-session -t "$session_name"
                killed_after_task_complete=1
            fi
            break
        fi

        if [ "$(( $(date +%s) - started_at ))" -ge "$wall_timeout_seconds" ]; then
            completion="wall_timeout"
            tmux kill-session -t "$session_name" 2>/dev/null || true
            break
        fi

        if [ -z "$events_file" ]; then
            events_file="$(find_events_file "$copilot_home")"
        fi
        sleep 1
    done

    while tmux has-session -t "$session_name" 2>/dev/null; do
        sleep 1
    done
    ended_at="$(date +%s)"

    if [ "$completion" = "missing_task_complete" ]; then
        if [ -z "$events_file" ]; then
            events_file="$(find_events_file "$copilot_home")"
        fi
        if [ -n "$events_file" ] && rg -q '"type":"session\.task_complete".*"success":true' "$events_file"; then
            completion="task_complete"
        fi
    fi

    if [ -s "$exit_code_file" ]; then
        exit_code="$(tr -d '[:space:]' < "$exit_code_file")"
    elif [ "$killed_after_task_complete" -eq 1 ]; then
        exit_code=143
    else
        exit_code=124
    fi

    if validation_output="$(validate_outputs "$english_file" "$telegram_file" 2>&1)"; then
        validation_status="PASS"
        version="$validation_output"
    fi

    if [ -z "$events_file" ]; then
        events_file="$(find_events_file "$copilot_home")"
    fi
    if validator_passed "$events_file"; then
        validator_status="PASS"
    fi

    if [ "$validation_status" = "PASS" ] && [ "$completion" = "task_complete" ] && [ "$prompt_mode" = "i" ] && [ "$validator_status" = "PASS" ]; then
        effective_status="PASS"
    fi

    printf '%s\n' "$validation_output" > "$run_dir/validation.txt"
    {
        printf 'exit_code=%s\n' "$exit_code"
        printf 'prompt_mode=%s\n' "$prompt_mode"
        printf 'validation=%s\n' "$validation_status"
        printf 'validator=%s\n' "$validator_status"
        printf 'effective=%s\n' "$effective_status"
        printf 'completion=%s\n' "$completion"
        printf 'killed_after_task_complete=%s\n' "$killed_after_task_complete"
        printf 'version=%s\n' "$version"
        printf 'duration_seconds=%s\n' "$((ended_at - started_at))"
    } > "$run_dir/status.env"

    echo "run $index result: effective=$effective_status validation=$validation_status validator=$validator_status completion=$completion version=${version:-unknown} exit=$exit_code"
}

case "$run_count" in
    ''|*[!0-9]*) fail "run_count 必須是正整數。" ;;
esac

[ "$run_count" -ge 1 ] || fail "run_count 必須大於 0。"
[ -x "$copilot_wrapper" ] || fail "找不到可執行的 callCopilot.sh：$copilot_wrapper"

if [ -z "$max_attempts" ]; then
    max_attempts=$((run_count * 2))
fi

case "$max_attempts" in
    ''|*[!0-9]*) fail "COPILOT_MAX_TEST_ATTEMPTS 必須是正整數。" ;;
esac

[ "$max_attempts" -ge "$run_count" ] || fail "COPILOT_MAX_TEST_ATTEMPTS 必須大於或等於 run_count。"

if [ "$prompt_mode" = "p" ]; then
    echo "警告: COPILOT_PROMPT_MODE=p 只適合重現 --autopilot + -p 的 stdout/task_complete bug，不計入有效提示詞驗收。" >&2
fi

mkdir -p "$output_root"

attempt=1
effective_count=0
while [ "$attempt" -le "$max_attempts" ] && [ "$effective_count" -lt "$run_count" ]; do
    run_one "$attempt"
    effective_count="$(grep -R '^effective=PASS$' "$output_root"/run.*/status.env 2>/dev/null | wc -l | tr -d ' ')"
    attempt=$((attempt + 1))
done

python3 "$script_dir/analyze_copilot_logs.py" "$output_root" --json-out "$output_root/summary.json" | tee "$output_root/summary.txt"

if [ "$(grep -R '^effective=PASS$' "$output_root"/run.*/status.env | wc -l | tr -d ' ')" -lt "$run_count" ]; then
    fail "未達成 $run_count/$run_count 次有效提示詞。詳見 $output_root"
fi

echo "有效提示詞完成 $run_count/$run_count 次：$output_root"
