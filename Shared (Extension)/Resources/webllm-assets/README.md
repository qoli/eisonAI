# WebLLM Assets (Bundled)

This folder is intentionally meant to be **bundled into the Safari Web Extension** (iOS/macOS), so the popup can load WebLLM model artifacts from extension bundle URLs (e.g. `new URL(..., import.meta.url)`) without runtime downloads.

## Expected layout

- `webllm-assets/models/Qwen3-0.6B-q4f16_1-MLC/resolve/main/*`
- `webllm-assets/wasm/Qwen3-0.6B-q4f16_1-ctx4k_cs1k-webgpu.wasm`

## Fetch (dev)

Run:

```bash
python3 Scripts/download_webllm_assets.py
```

It will download the required files into this folder.
