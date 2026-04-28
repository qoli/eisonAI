# MLX Download Probe

Standalone Swift CLI for testing Hugging Face / MLX model download progress before wiring behavior back into the app.

It uses the same local `swift-transformers` package as the app, so dependency changes such as the `swift-huggingface` fork can be tested without launching the UI.

## Commands

```bash
swift run mlx-download-probe --metadata-only --model mlx-community/Qwen3.5-0.8B-4bit
swift run mlx-download-probe --clear --model mlx-community/Qwen3.5-0.8B-4bit --download-base /tmp/eisonAI-mlx-download-probe-qwen08
```

Useful options:

- `--pattern <glob>` repeats to narrow downloaded files.
- `--all` downloads every file in the snapshot.
- `--poll <seconds>` controls local byte polling.
- `--throttle <seconds>` controls callback log frequency.
- `--clear` removes the target snapshot directory before starting.

## Current Observation

With `iSapozhnik/swift-huggingface@bugfix/progress-observation`, callback progress reports continuous updates while a large file is downloading. Local snapshot bytes may remain low until the large file is committed to the snapshot/cache, then jump forward. App integration should therefore treat callback progress as the live transport signal and local byte polling as confirmation of materialized assets.
