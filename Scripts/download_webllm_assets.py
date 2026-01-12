#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.parse
import urllib.error
import urllib.request
from pathlib import Path


MODEL_ID = "Qwen3-0.6B-q4f16_1-MLC"
HF_REPO = f"mlc-ai/{MODEL_ID}"
HF_API_URL = f"https://huggingface.co/api/models/{HF_REPO}"
HF_RESOLVE_BASE = f"https://huggingface.co/{HF_REPO}/resolve/main/"

WEBLLM_MODEL_VERSION = "v0_2_80"
WEBLLM_WASM_FILE = "Qwen3-0.6B-q4f16_1-ctx4k_cs1k-webgpu.wasm"
WEBLLM_WASM_URL = (
    "https://raw.githubusercontent.com/mlc-ai/binary-mlc-llm-libs/main/web-llm-models/"
    f"{WEBLLM_MODEL_VERSION}/{WEBLLM_WASM_FILE}"
)


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def http_get_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "eisonAI-webllm-assets/1.0"})
    with urllib.request.urlopen(req) as resp:
        charset = resp.headers.get_content_charset() or "utf-8"
        return json.loads(resp.read().decode(charset))


def download_file(url: str, dest: Path, *, force: bool) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and not force:
        print(f"[skip] {dest.relative_to(Path.cwd())}")
        return

    tmp = dest.with_suffix(dest.suffix + ".partial")
    if tmp.exists():
        tmp.unlink()

    print(f"[get ] {url}")
    req = urllib.request.Request(url, headers={"User-Agent": "eisonAI-webllm-assets/1.0"})
    with urllib.request.urlopen(req) as resp, open(tmp, "wb") as f:
        while True:
            chunk = resp.read(1024 * 1024)
            if not chunk:
                break
            f.write(chunk)
    os.replace(tmp, dest)
    print(f"[ok  ] {dest.relative_to(Path.cwd())}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Download bundled WebLLM model assets for the Safari extension.")
    parser.add_argument(
        "--dest",
        default=str(Path("Shared (Extension)/Resources/webllm-assets")),
        help="Destination root (default: Shared (Extension)/Resources/webllm-assets)",
    )
    parser.add_argument("--force", action="store_true", help="Re-download even if files exist.")
    args = parser.parse_args()

    dest_root = Path(args.dest).resolve()
    models_root = dest_root / "models" / MODEL_ID / "resolve" / "main"
    wasm_root = dest_root / "wasm"

    print(f"[info] repo: {HF_REPO}")
    print(f"[info] dest: {dest_root}")

    try:
        meta = http_get_json(HF_API_URL)
    except urllib.error.URLError as err:
        eprint(f"[error] HuggingFace API failed: {err}")
        return 1

    siblings = meta.get("siblings") or []
    if not isinstance(siblings, list):
        eprint("[error] Unexpected API response: siblings is not a list")
        return 1

    files: list[str] = []
    for item in siblings:
        if isinstance(item, dict):
            name = item.get("rfilename")
            if isinstance(name, str) and name:
                files.append(name)

    if "mlc-chat-config.json" not in files:
        eprint("[error] Unexpected model repo layout: mlc-chat-config.json not found")
        return 1

    for name in files:
        url = HF_RESOLVE_BASE + urllib.parse.quote(name)
        download_file(url, models_root / name, force=args.force)

    download_file(WEBLLM_WASM_URL, wasm_root / WEBLLM_WASM_FILE, force=args.force)

    print("[done] WebLLM assets downloaded.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
