# Browser Integration And Product Repositioning

## Current Status

- `draft`
- The current product is centered on Safari Extension summarization, local inference, and Raw Library capture.
- The app does not yet define an in-app browser as a first-class product surface.
- The repositioning toward a broader learning assistant has not been reflected in the app structure, onboarding, or information architecture.

## Problem / Background

The current product story is still close to "article summarizer + reading helper." That is coherent with the existing Safari Extension flow, but it is narrower than the broader workflow the app can support.

If eisonAI is meant to become a stronger local-first assistant, users need a more complete loop:

- discover information
- browse and collect material
- organize it into a reusable library
- use local AI to summarize, structure, and support learning

Without a browser surface, the app depends too heavily on external browsing contexts. That keeps capture fragmented and makes the app feel like a utility instead of a full workspace.

## Scope / Positioning

This plan covers:

- introducing browser capability into the app as a product surface
- repositioning eisonAI toward `local AI / information organization / learning assistant`
- defining how browsing should connect to capture, summarization, and long-term knowledge organization

This plan does not yet cover:

- low-level implementation details for a specific browser engine
- sync or account strategy changes
- a full replacement of Safari or a desktop-class browser feature set

## Main Model

### Product Direction

The new product direction is:

> eisonAI is a local-first AI assistant for browsing, organizing information, and supporting learning.

The browser capability should not exist as a standalone feature. It should serve the broader workflow of:

1. finding content
2. collecting content
3. structuring content
4. revisiting content for learning and reuse

### Capability Pillars

- `Local AI`: on-device summarization, structuring, title generation, and long-document assistance
- `Information Organization`: Raw Library, favorites, tagging, later note systems, and reusable personal knowledge
- `Learning Assistant`: reading anchors, guided summaries, key-point extraction, and future study-oriented flows
- `Browser Surface`: a built-in browsing and capture entry point that reduces context switching

### Proposed Browser Role

The browser should be defined as a workflow surface, not a generic parity browser.

Its expected v1 role:

- open pages inside the app
- let the user capture the current page into the library
- trigger local AI actions from the browsing context
- connect browsing history or reading sessions to later review

Its non-role for v1:

- competing with full browsers on tabs, extensions, accounts, or advanced browsing settings
- becoming a general-purpose sync-heavy browser platform

### Relationship To Existing System

Current product surfaces already provide parts of this direction:

- Safari Extension: fast page summarization and capture
- Raw Library: local storage for source material and summaries
- Long-document pipeline: deeper reading support for constrained local models

The proposed browser capability should reuse these foundations instead of replacing them.

The likely model is:

`Browser -> Content extraction / capture -> Local AI processing -> Raw Library / later learning surfaces`

## Relationship To Other Docs

This plan depends on the current behavior documented in:

- `Docs/key-point.md`
- `Docs/long-document-reading-pipeline.md`
- `Docs/OpenDoc/eisonAI.md`
- `Spec/SPEC.md`

This plan should later lead to follow-up docs for:

- browser v1 scope
- capture flow and library schema impact
- navigation / information architecture changes in the app
- onboarding and positioning copy updates

## Open Questions

- Should the first browser surface be a lightweight in-app reader, or a more persistent browser workspace?
- What is the minimum browsing scope for v1: single page view, tab support, reading queue, or session restore?
- Which actions should be available directly inside the browser: summarize, extract key points, save, tag, annotate?
- How much of the current Safari Extension flow should be mirrored inside the app versus kept as a separate fast-entry surface?
- Does repositioning require changes to app naming, onboarding copy, App Store messaging, and library taxonomy?

## Suggested Next Steps

1. Define a browser v1 scope document with explicit non-goals.
2. Map the user flow from browsing to capture to library review.
3. Decide which existing AI actions become browser-native entry points.
4. Review whether Raw Library schema needs new fields for source session, browser metadata, or learning status.
