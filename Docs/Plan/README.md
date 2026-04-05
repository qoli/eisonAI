# Plan Registry

`Docs/Plan/` stores product and architecture plans that are not yet current-state documentation.

## Status Model

- `draft`: proposal only, no meaningful end-to-end implementation yet
- `partially landed`: some implementation exists, but the main plan is still incomplete
- `landed`: the core behavior described by the plan exists in the codebase
- `retired`: kept for historical context, no longer the active direction

## Filing Rules

- Keep one plan focused on one responsibility boundary.
- Put `Current Status` near the top of each plan.
- Separate current behavior from proposed direction.
- Move stable implementation details into `Docs/` when they become current-state documentation.

## Plans

| File | Status | Summary |
| --- | --- | --- |
| `browser-integration-learning-assistant.md` | `draft` | Integrate browser capabilities and reposition eisonAI as a local AI, information organization, and learning assistant. |
| `inference-backend-consolidation-any-language-model.md` | `draft` | Evaluate dropping the MLC/MLC Swift path and consolidating app inference around Apple Intelligence and BYOK with AnyLanguageModel. |
