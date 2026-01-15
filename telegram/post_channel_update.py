#!/usr/bin/env python3
"""Post a photo + combined markdown text to a Telegram channel.

Usage example:
  TELEGRAM_BOT_TOKEN=xxx \
  python3 post_channel_update.py \
    --chat-id @RonnieAppsChannel \
    --image /path/VersionUpdate.png \
    --top /path/top.md \
    --changelog /path/changelog.md
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

CAPTION_LIMIT = 1024
MESSAGE_LIMIT = 4096


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def read_token_from_file(path: str) -> str | None:
    if not path:
        return None
    if not os.path.exists(path):
        return None
    token = read_text(path).strip()
    return token or None


def merge_text(top: str, changelog: str) -> str:
    top_clean = top.rstrip("\n")
    change_clean = changelog.lstrip("\n")
    if top_clean and change_clean:
        return f"{top_clean}\n\n{change_clean}"
    return f"{top_clean}{change_clean}"


def _is_list_like(line: str) -> bool:
    stripped = line.lstrip()
    if not stripped:
        return False
    if stripped.startswith(("-", "•", "·")):
        return True
    if stripped[0].isdigit():
        # numbered list: "1." or "1)"
        if stripped[1:2] in (".", ")"):
            return True
    if stripped.startswith(("✅", "⚠️", "❌", "☑️", "✔️", "✳️", "⭐")):
        return True
    return False


def _is_version_line(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return False
    parts = stripped.split(".")
    if not all(part.isdigit() for part in parts):
        return False
    return True


def normalize_markdown_for_telegram(text: str) -> str:
    # Telegram Markdown does not support headings like "# Title".
    # Convert headings to bold using legacy Markdown: *bold*
    lines = text.splitlines()
    out: list[str] = []
    for idx, line in enumerate(lines):
        stripped = line.lstrip()
        if stripped.startswith("#"):
            i = 0
            while i < len(stripped) and stripped[i] == "#":
                i += 1
            if i < len(stripped) and stripped[i] == " ":
                content = stripped[i + 1 :].strip()
                if content:
                    out.append(f"*{content}*")
                    continue

        # Heuristic: bold short standalone lines as headings
        if (
            stripped
            and not _is_list_like(stripped)
            and len(stripped) <= 40
            and ("。" not in stripped)
        ):
            next_line = ""
            for j in range(idx + 1, len(lines)):
                if lines[j].strip():
                    next_line = lines[j].lstrip()
                    break
            if _is_version_line(stripped) or _is_list_like(next_line) or next_line == "":
                out.append(f"*{stripped.strip()}*")
                continue

        out.append(line)
    return "\n".join(out)


def build_multipart(fields: dict[str, str], files: dict[str, tuple[str, bytes, str]]) -> tuple[bytes, str]:
    boundary = f"----tg-boundary-{uuid.uuid4().hex}"
    lines: list[bytes] = []

    for name, value in fields.items():
        lines.append(f"--{boundary}".encode())
        lines.append(f"Content-Disposition: form-data; name=\"{name}\"".encode())
        lines.append(b"")
        lines.append(value.encode())

    for name, (filename, data, mime) in files.items():
        lines.append(f"--{boundary}".encode())
        lines.append(
            f"Content-Disposition: form-data; name=\"{name}\"; filename=\"{filename}\"".encode()
        )
        lines.append(f"Content-Type: {mime}".encode())
        lines.append(b"")
        lines.append(data)

    lines.append(f"--{boundary}--".encode())
    lines.append(b"")

    body = b"\r\n".join(lines)
    content_type = f"multipart/form-data; boundary={boundary}"
    return body, content_type


def http_post(url: str, fields: dict[str, str], files: dict[str, tuple[str, bytes, str]] | None = None) -> dict:
    if files:
        body, content_type = build_multipart(fields, files)
        headers = {"Content-Type": content_type}
    else:
        body = urllib.parse.urlencode(fields).encode()
        headers = {"Content-Type": "application/x-www-form-urlencoded"}

    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req) as resp:
            data = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        data = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {e.code} {e.reason}: {data}") from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"Request failed: {e.reason}") from e

    try:
        return json.loads(data)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Invalid JSON response: {data}") from e


def send_photo(api_base: str, chat_id: str, image_path: str, caption: str | None, parse_mode: str | None) -> dict:
    mime, _ = mimetypes.guess_type(image_path)
    if not mime:
        mime = "application/octet-stream"

    with open(image_path, "rb") as f:
        image_bytes = f.read()

    fields: dict[str, str] = {"chat_id": chat_id}
    if caption:
        fields["caption"] = caption
    if parse_mode:
        fields["parse_mode"] = parse_mode

    files = {"photo": (os.path.basename(image_path), image_bytes, mime)}
    return http_post(f"{api_base}/sendPhoto", fields, files)


def send_message(api_base: str, chat_id: str, text: str, parse_mode: str | None) -> dict:
    fields: dict[str, str] = {"chat_id": chat_id, "text": text}
    if parse_mode:
        fields["parse_mode"] = parse_mode
    return http_post(f"{api_base}/sendMessage", fields)


def chunk_text(text: str, limit: int) -> list[str]:
    chunks: list[str] = []
    remaining = text
    while len(remaining) > limit:
        split_at = remaining.rfind("\n", 0, limit)
        if split_at == -1:
            split_at = remaining.rfind(" ", 0, limit)
        if split_at == -1:
            split_at = limit
        chunk = remaining[:split_at].rstrip("\n")
        chunks.append(chunk)
        remaining = remaining[split_at:].lstrip("\n")
    if remaining:
        chunks.append(remaining)
    return chunks


def main() -> int:
    parser = argparse.ArgumentParser(description="Post a photo + combined text to a Telegram channel.")
    parser.add_argument("--token", default=None, help="Bot token (overrides env and .token file)")
    parser.add_argument("--token-file", default="/Volumes/Data/Github/eisonAI/telegram/.token", help="Path to .token file")
    parser.add_argument("--chat-id", default="@RonnieAppsChannel", help="Channel username or chat ID")
    parser.add_argument("--image", default="/Volumes/Data/Github/eisonAI/telegram/VersionUpdate.png")
    parser.add_argument("--top", default="/Volumes/Data/Github/eisonAI/telegram/top.md")
    parser.add_argument("--changelog", default="/Volumes/Data/Github/eisonAI/telegram/changelog.md")
    parser.add_argument("--parse-mode", default="Markdown", help="Markdown, MarkdownV2, or HTML (default: Markdown)")
    parser.add_argument("--no-parse-mode", action="store_true", help="Disable parse mode (send plain text)")
    parser.add_argument(
        "--no-normalize",
        action="store_true",
        help="Do not normalize Markdown headings for Telegram",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print merged text and exit")
    args = parser.parse_args()

    token = args.token or os.getenv("TELEGRAM_BOT_TOKEN") or read_token_from_file(args.token_file)
    if not token:
        print("Missing bot token. Provide --token, set TELEGRAM_BOT_TOKEN, or create a .token file.", file=sys.stderr)
        return 2

    top_text = read_text(args.top)
    changelog_text = read_text(args.changelog)
    merged = merge_text(top_text, changelog_text)
    if args.parse_mode == "Markdown" and not args.no_normalize:
        merged = normalize_markdown_for_telegram(merged)

    if args.dry_run:
        print(merged)
        return 0

    if args.no_parse_mode:
        args.parse_mode = None

    api_base = f"https://api.telegram.org/bot{token}"

    # Telegram caption limit is 1024 chars. If too long, send photo without caption,
    # then send the text as separate message(s).
    if len(merged) <= CAPTION_LIMIT:
        response = send_photo(api_base, args.chat_id, args.image, merged, args.parse_mode)
        if not response.get("ok"):
            raise RuntimeError(f"sendPhoto failed: {response}")
        print("Posted photo with caption.")
        return 0

    response = send_photo(api_base, args.chat_id, args.image, None, None)
    if not response.get("ok"):
        raise RuntimeError(f"sendPhoto failed: {response}")

    for chunk in chunk_text(merged, MESSAGE_LIMIT):
        response = send_message(api_base, args.chat_id, chunk, args.parse_mode)
        if not response.get("ok"):
            raise RuntimeError(f"sendMessage failed: {response}")

    print("Posted photo and text messages.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        raise SystemExit(1)
