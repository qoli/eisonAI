# Long-Document Reading Pipeline

## Purpose

Apple Intelligence has a bounded context window. For long app inputs, eisonAI splits the source into token-aware chunks, generates a reading anchor for each chunk, and then summarizes those anchors.

## Routing

- The pipeline runs only when the resolved execution type is local, which now means Apple Intelligence.
- BYOK remains a direct streaming request.
- Auto selects BYOK for inputs above its strategy threshold, so those inputs do not enter the local pipeline.

## Flow

1. Estimate the source token count.
2. Split text using the configured chunk size and maximum chunk count.
3. Generate one reading anchor per chunk.
4. Combine anchors into the final summary prompt.
5. Persist anchors, token estimates, selected chunk size, and final output in the Library record.

If Foundation Models reports an exceeded context window, the app retries with the next smaller allowed chunk size. Other errors are propagated without an unrelated fallback.

## Settings

`Settings → AI Models → Long Document` exposes chunk size and maximum chunks. The strategy threshold remains code-owned.

## Evidence

Unit tests cover chunk-size fallback selection, error recognition, and UTF-16 slicing. End-to-end Apple Intelligence behavior requires an eligible physical device.
