# MLX Download Probe

Standalone Swift CLI for testing Hugging Face / MLX model download progress before wiring behavior back into the app.

It uses the same local `swift-transformers` package as the app, so dependency changes such as the `swift-huggingface` fork can be tested without launching the UI.

## Commands

```bash
swift run mlx-download-probe --metadata-only --model mlx-community/Qwen3.5-0.8B-4bit
swift run mlx-download-probe --clear --model mlx-community/Qwen3.5-0.8B-4bit --download-base /tmp/eisonAI-mlx-download-probe-qwen08
swift run mlx-download-probe --clear --clear-cache --model mlx-community/Qwen3.5-0.8B-4bit --download-base /tmp/eisonAI-mlx-download-probe-qwen08-cold
```

Useful options:

- `--pattern <glob>` repeats to narrow downloaded files.
- `--all` downloads every file in the snapshot.
- `--poll <seconds>` controls local byte polling.
- `--throttle <seconds>` controls callback log frequency.
- `--clear` removes the target snapshot directory before starting.
- `--clear-cache` removes this model from the default Hugging Face cache for a cold download test.

## Current Observation

With `iSapozhnik/swift-huggingface@bugfix/progress-observation`, callback progress reports continuous updates while a large file is downloading. Local snapshot bytes may remain low until the large file is committed to the snapshot/cache, then jump forward.

The probe intentionally reports:

- `liveBytes`: callback-derived progress or observed new bytes, whichever is higher.
- `materializedBytes`: bytes currently present in the target snapshot directory.
- `materializedDelta`: bytes added to the target snapshot during this run.
- `cacheNewBytes`: bytes added to the Hugging Face cache during this run, excluding baseline cache.
- `cacheTotalBytes`: total model bytes currently present in the Hugging Face cache.

Use `--clear --clear-cache` for a cold network test. Use only `--clear` to test materialization from a warm cache.

Latest local cold probe for `mlx-community/Qwen3.5-0.8B-4bit`:

- `remoteExpectedBytes`: 652 MB.
- `elapsed`: 59.52s.
- `averageEffectiveSpeed`: 11 MB/s.
- `finalMaterializedDelta`: 652 MB.
- `finalCacheNewBytes`: 652 MB.
