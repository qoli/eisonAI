#!/usr/bin/env python3
import argparse
import json
import re
from datetime import datetime
from pathlib import Path


TIMESTAMP_RE = re.compile(r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z)")


def parse_ts(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def read_text(path):
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return ""


def count_lines(text, needle):
    return sum(1 for line in text.splitlines() if needle in line)


def process_log_metrics(run_dir):
    metrics = {
        "process_log": None,
        "process_seconds": None,
        "model_request_markers": 0,
        "task_validation_failures": 0,
        "tool_validation_failures": 0,
        "task_invocations": 0,
        "custom_agent_invocations": 0,
        "notion_tool_errors": 0,
    }

    logs = sorted((run_dir / "copilot-home" / "logs").glob("*.log"))
    if not logs:
        return metrics

    log_path = logs[-1]
    text = read_text(log_path)
    metrics["process_log"] = str(log_path)
    metrics["model_request_markers"] = count_lines(text, "Sending request to the AI model")
    metrics["task_validation_failures"] = count_lines(text, "Task tool validation failed")
    metrics["tool_validation_failures"] = count_lines(text, "Multiple validation errors")
    metrics["task_invocations"] = count_lines(text, "Task tool invoked")
    metrics["custom_agent_invocations"] = count_lines(text, "Custom agent")
    metrics["notion_tool_errors"] = (
        count_lines(text, "Error in tool call")
        + count_lines(text, "status: 400")
        + count_lines(text, "status: 404")
    )

    timestamps = []
    for line in text.splitlines():
        match = TIMESTAMP_RE.match(line)
        if match:
            timestamps.append(parse_ts(match.group(1)))
    if len(timestamps) >= 2:
        metrics["process_seconds"] = round((timestamps[-1] - timestamps[0]).total_seconds(), 3)

    return metrics


def events_metrics(run_dir):
    metrics = {
        "events_file": None,
        "task_complete_success": None,
        "task_complete_at": None,
        "shutdown_seen": False,
        "shutdown_at": None,
        "task_complete_to_shutdown_seconds": None,
        "shutdown_api_duration_ms": None,
        "shutdown_request_count": None,
        "shutdown_input_tokens": None,
        "shutdown_output_tokens": None,
        "events_tool_calls": 0,
        "events_failed_tool_calls": 0,
        "events_failed_task_tools": 0,
        "translation_validator_invocations": 0,
        "translation_validator_passes": 0,
        "translation_validator_failures": 0,
    }

    events_files = sorted((run_dir / "copilot-home" / "session-state").glob("*/events.jsonl"))
    if not events_files:
        return metrics

    events_path = events_files[-1]
    metrics["events_file"] = str(events_path)
    validator_tool_ids = set()

    for raw in read_text(events_path).splitlines():
        try:
            event = json.loads(raw)
        except json.JSONDecodeError:
            continue

        event_type = event.get("type")
        data = event.get("data") or {}

        if event_type == "assistant.message":
            metrics["events_tool_calls"] += len(data.get("toolRequests") or [])
            content = str(data.get("content") or "")
            if event.get("agentId") in validator_tool_ids:
                if '"status":"PASS"' in content or '"status": "PASS"' in content:
                    metrics["translation_validator_passes"] += 1
                elif '"status":"FAIL"' in content or '"status": "FAIL"' in content:
                    metrics["translation_validator_failures"] += 1
        elif event_type == "tool.execution_complete":
            if data.get("success") is False:
                metrics["events_failed_tool_calls"] += 1
            if data.get("toolName") == "task" and data.get("success") is False:
                metrics["events_failed_task_tools"] += 1
            result = data.get("result") or {}
            content = str(result.get("content") or "")
            if data.get("toolCallId") in validator_tool_ids:
                if '"status":"PASS"' in content or '"status": "PASS"' in content:
                    metrics["translation_validator_passes"] += 1
                elif '"status":"FAIL"' in content or '"status": "FAIL"' in content:
                    metrics["translation_validator_failures"] += 1
            elif "agent_type: translation-validator" in content:
                if '"status":"PASS"' in content or '"status": "PASS"' in content:
                    metrics["translation_validator_passes"] += 1
                elif '"status":"FAIL"' in content or '"status": "FAIL"' in content:
                    metrics["translation_validator_failures"] += 1
        elif event_type == "session.task_complete":
            metrics["task_complete_success"] = data.get("success")
            metrics["task_complete_at"] = event.get("timestamp")
        elif event_type == "session.shutdown":
            metrics["shutdown_seen"] = True
            metrics["shutdown_at"] = event.get("timestamp")
            metrics["shutdown_api_duration_ms"] = data.get("totalApiDurationMs")
            model_metrics = data.get("modelMetrics") or {}
            request_count = 0
            input_tokens = 0
            output_tokens = 0
            for model in model_metrics.values():
                request_count += ((model.get("requests") or {}).get("count") or 0)
                usage = model.get("usage") or {}
                input_tokens += usage.get("inputTokens") or 0
                output_tokens += usage.get("outputTokens") or 0
            metrics["shutdown_request_count"] = request_count
            metrics["shutdown_input_tokens"] = input_tokens
            metrics["shutdown_output_tokens"] = output_tokens
        elif event_type == "subagent.started":
            if data.get("agentName") == "translation-validator":
                metrics["translation_validator_invocations"] += 1
                if data.get("toolCallId"):
                    validator_tool_ids.add(data["toolCallId"])

    if metrics["task_complete_at"] and metrics["shutdown_at"]:
        metrics["task_complete_to_shutdown_seconds"] = round(
            (
                parse_ts(metrics["shutdown_at"])
                - parse_ts(metrics["task_complete_at"])
            ).total_seconds(),
            3,
        )

    return metrics


def run_status(run_dir):
    status_file = run_dir / "status.env"
    status = {}
    for line in read_text(status_file).splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            status[key] = value
    return status


def collect_run(run_dir):
    prompt = read_text(run_dir / "prompt.txt")
    status = run_status(run_dir)
    result = {
        "run": run_dir.name,
        "path": str(run_dir),
        "prompt_chars": len(prompt),
        "prompt_lines": prompt.count("\n") + (1 if prompt else 0),
        "prompt_mode": status.get("prompt_mode"),
        "exit_code": int(status["exit_code"]) if status.get("exit_code", "").isdigit() else None,
        "validation": status.get("validation"),
        "runner_effective": status.get("effective"),
        "effective": status.get("effective"),
        "completion": status.get("completion"),
        "killed_after_task_complete": status.get("killed_after_task_complete"),
        "version": status.get("version"),
        "duration_seconds": float(status["duration_seconds"]) if status.get("duration_seconds") else None,
    }
    result.update(process_log_metrics(run_dir))
    result.update(events_metrics(run_dir))
    result["effective"] = (
        "PASS"
        if result.get("validation") == "PASS"
        and result.get("task_complete_success") is True
        and result.get("prompt_mode") == "i"
        and (result.get("translation_validator_passes") or 0) >= 1
        else "FAIL"
    )
    return result


def print_table(rows):
    columns = [
        ("run", "run", 12),
        ("validation", "valid", 8),
        ("effective", "effective", 9),
        ("prompt_mode", "mode", 5),
        ("version", "version", 8),
        ("duration_seconds", "seconds", 8),
        ("shutdown_request_count", "requests", 8),
        ("shutdown_api_duration_ms", "api_ms", 10),
        ("task_complete_to_shutdown_seconds", "tc_shutdown", 11),
        ("shutdown_input_tokens", "input_tokens", 12),
        ("task_validation_failures", "task_err", 8),
        ("tool_validation_failures", "tool_err", 8),
        ("translation_validator_invocations", "tv", 4),
        ("translation_validator_passes", "tv_ok", 5),
        ("task_invocations", "task", 6),
    ]
    header = " ".join(label[:width].ljust(width) for _name, label, width in columns)
    print(header)
    print("-" * len(header))
    for row in rows:
        parts = []
        for name, _label, width in columns:
            value = row.get(name)
            parts.append(("" if value is None else str(value))[:width].ljust(width))
        print(" ".join(parts))


def main():
    parser = argparse.ArgumentParser(description="Summarize Copilot CLI prompt test cost from run logs.")
    parser.add_argument("root", nargs="?", default="logs/new_version_copilot")
    parser.add_argument("--json-out")
    args = parser.parse_args()

    root = Path(args.root)
    if (root / "prompt.txt").exists():
        run_dirs = [root]
    else:
        run_dirs = sorted(path for path in root.glob("run.*") if path.is_dir())

    rows = [collect_run(run_dir) for run_dir in run_dirs]
    print_table(rows)

    if args.json_out:
        Path(args.json_out).write_text(
            json.dumps({"root": str(root), "runs": rows}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )


if __name__ == "__main__":
    main()
