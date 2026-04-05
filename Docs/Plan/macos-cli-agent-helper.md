# macOS CLI Helper For Agent Runtime Access

## Current Status

- `draft`
- eisonAI already has a macOS-facing surface through Safari extension support, My Mac (Designed for iPad), and Mac Catalyst-related build targets.
- The app already stores user data in Raw Library JSON files, which current docs describe as the source of truth.
- There is no stable CLI surface today for external tools, agent runtimes, or terminal workflows to read or operate on eisonAI data.
- Agent access today would require direct file inspection or ad hoc app-specific integration, which is brittle and poorly scoped.

## Problem / Background

If eisonAI is moving toward "local AI / information organization / learning assistant," then the product becomes more valuable when its data is reachable from automation contexts, not only from UI surfaces.

On macOS in particular, users may want:

- terminal access to their library
- agent-driven reading and organization workflows
- automation that can query, summarize, export, or update items
- a stable local interface instead of reverse-engineering app storage

Without a supported CLI helper, agent runtimes have to treat eisonAI as an opaque app. That limits interoperability and makes the data harder to integrate into broader personal workflows.

## Scope / Positioning

This plan covers:

- defining a macOS-only CLI helper surface for eisonAI
- defining how agent runtimes can access eisonAI data through supported commands
- clarifying the boundary between raw storage, derived views, and writable actions
- framing this as a product capability, not just a developer convenience

This plan does not yet cover:

- exact binary name, packaging, or installation path
- whether the CLI is bundled inside the app, shipped as a companion tool, or both
- final auth, permission, or sandbox policy details
- a full MCP server design

## Main Model

### Product Direction

The proposed direction is:

> On macOS, eisonAI should expose a CLI-level helper so users and agent runtimes can interact with library data through a stable local contract.

This should make eisonAI usable as both:

- a GUI app for capture, reading, and review
- a local knowledge service for automation and agents

### Why macOS First

macOS is the most natural place to introduce this capability because:

- terminal-based workflows already exist there
- agent runtimes commonly run there
- file access, scripting, and companion tools are more realistic than on iOS
- this can expand the value of existing Raw Library data without requiring immediate UI changes

### Expected Helper Role

The CLI helper should act as a supported access layer above app storage.

Its expected v1 role:

- list library items
- inspect an item by identifier or path
- export structured data in machine-readable form
- trigger narrow read-only or low-risk actions for agents

Its non-role for v1:

- exposing every internal implementation detail
- becoming a full general-purpose SDK
- letting third-party tools mutate all app state without clear boundaries

### Data Access Model

The safest initial model is:

- Raw Library remains the source of truth
- CLI exposes stable read models over that data
- write operations, if any, are narrow and explicit

Likely read surfaces:

- `items list`
- `items get`
- `favorites list`
- `search`
- `export --json`

Possible later actions:

- save a new captured item
- tag or annotate an item
- queue an AI action against an item

### Agent Runtime Positioning

This helper is useful because agent runtimes need a stable contract.

That contract should avoid:

- forcing agents to parse undocumented file layouts
- coupling agents to current UI or view-model structure
- requiring private implementation knowledge

Over time, this helper could become:

- a CLI with JSON output
- a local automation bridge
- or the basis for a future MCP-style interface

### Relationship To Existing System

This plan builds on existing foundations:

- Raw Library already exists as persisted structured data
- the app already has a library concept and stored summaries
- macOS is already in scope for the product

The likely model is:

`eisonAI app data -> stable CLI helper -> agent runtime / terminal workflows`

## Relationship To Other Docs

This plan intersects with:

- `Docs/database.md`
- `Docs/key-point.md`
- `Docs/Plan/browser-integration-learning-assistant.md`
- `Spec/CloudKit_Sync.md`
- `Spec/SPEC.md`

If adopted, this plan should later produce follow-up docs for:

- CLI command surface and JSON schemas
- read/write permission boundaries
- data model guarantees and versioning
- macOS packaging and distribution strategy

## Open Questions

- Should the helper be strictly read-only in v1, or allow narrow write actions?
- Should the helper talk directly to Raw Library files, or through an app-owned service layer?
- How should identifiers be exposed: file path, stable item id, URL hash, or multiple forms?
- Should this stay as a CLI only, or be designed from day one to evolve into MCP or another agent protocol?
- What macOS-only capabilities are acceptable without creating feature divergence from iOS?

## Suggested Next Steps

1. Define the smallest useful read-only command set for agent workflows.
2. Decide whether the helper reads files directly or goes through an app-managed abstraction.
3. Define a stable JSON output schema for library items and search results.
4. Audit which current Raw Library fields are safe to expose as a public local contract.
