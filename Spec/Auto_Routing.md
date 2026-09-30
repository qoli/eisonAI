# Auto Strategy Routing

## Types

- `GenerationBackend`: user selection (`auto`, `local`, `byok`).
- `ExecutionBackendType`: resolved class (`local`, `byok`).
- `ExecutionBackend`: concrete backend (`apple`, `byok`).

`local` now means Apple Intelligence only.

## App Rules

1. `BYOK` always resolves to BYOK.
2. `Local` resolves only to Apple Intelligence. If Apple Intelligence is unavailable, generation fails with an availability error and does not send the input to BYOK.
3. `Auto` compares the estimated token count with the fixed strategy threshold:
   - at or below the threshold: Apple Intelligence when available, otherwise BYOK;
   - above the threshold: BYOK.
4. Only the resolved local type can enter the long-document chunk pipeline.
5. BYOK uses direct streaming and does not enter that chunk pipeline.

## Safari Rules

Safari selection is `auto`, `apple`, or `byok`:

- `auto` chooses Apple Intelligence when available, otherwise BYOK;
- `apple` requests Apple Intelligence;
- `byok` requests the configured provider.

The native bridge reports Apple Intelligence availability and the strategy threshold. It no longer reports a downloadable-model preference.

## Upgrade Compatibility

Legacy raw values `mlx` and `local` load as the current `local` selection. They cannot produce a removed execution backend and never silently switch to BYOK; execution requires Apple Intelligence.
