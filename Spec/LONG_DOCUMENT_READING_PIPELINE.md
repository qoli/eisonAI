# Long-Document Reading Pipeline Specification

## Invariants

1. Only Apple Intelligence uses the chunked reading-anchor pipeline.
2. BYOK uses a direct provider request and does not enter the pipeline.
3. Chunk boundaries come from the configured tokenizer and preserve UTF-16 offsets for source recovery.
4. Empty chunk text is recovered from the original source offsets before generation.
5. Context-window fallback only retries Apple Intelligence and only with a smaller allowed chunk size.
6. Results persist the effective chunk size and reading anchors used for the final summary.

## Inputs

- normalized article/share text;
- estimated token count;
- allowed chunk sizes;
- maximum chunk count;
- reading-anchor and summary prompt templates.

## Output

- final structured summary;
- system and user prompts;
- model identifier (`apple-intelligence`);
- reading-anchor metadata;
- token and routing metadata stored with the Library item.

## Acceptance

- Unit: chunk fallback, error classification, offset slicing, and prompt assembly.
- Compile: simulator app and test targets.
- Runtime: eligible iOS 26+ device with Apple Intelligence enabled.
