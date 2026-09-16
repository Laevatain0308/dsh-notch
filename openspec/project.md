# Project: Notch

## What Notch is

Notch is a **system-wide output port for state and notifications**, not a DSH accessory. Its design reference is the iPhone Dynamic Island: a small persistent surface at the screen edge that grows into a panel when something needs attention or a decision.

**The core of the product is its motion and interaction quality.** Any design decision that trades away the liveliness of the animation or the directness of the interaction has traded away the reason Notch exists. Providers are not the product; the surface is.

## Architecture

Three layers, and the seams between them are the contract:

| Layer | Owns | Must not |
| --- | --- | --- |
| **Notch Core** | Motion library, capability surface, display arbitration, the local bus, provider trust | Know any provider by name |
| **Notch SDK** | The only surface a provider touches: register, entity upsert, hold an interaction, declare actions | Expose rendering, layout, or coordinates |
| **Adapters** | One per information domain (DSH, browser, CI, media) | Know about each other |

A provider and Notch are joined **only** by the information/state protocol. Neither reaches into the other: Notch never carries code that recognises a provider, and a provider never learns how Notch draws.

## Standalone, with DSH as a provider

Notch is being detached from DSH into its own desktop application. The existing DSH Host plugin stops being the owner of the overlay and becomes **the first adapter**: it registers with Notch, declares the actions Notch may invoke, and pushes entity state. Everything DSH-specific that lives in Notch today (session rows, unread markers, focus wishes) must be re-expressed as generic entities, states, and provider-declared actions.

## Where OpenSpec applies

`openspec/` is the memory for this direction. Read it before proposing changes to Notch's protocol, capability surface, or motion behaviour.

- `specs/` — capabilities that are **built**. Empty today; Notch has no standalone implementation yet.
- `changes/` — proposals. Everything about the standalone Notch currently lives under `changes/standalone-notch-ecosystem/`.

This directory currently sits in the `dsh-notch` repository because that repository still contains both halves. When Notch splits into its own application, `specs/notch/**` and `changes/**` move with it, and only the DSH adapter's own capability specs remain here.

## Conventions

Behaviour contracts are written as requirements and scenarios; technology choices, message names, schema shapes, and code structure live in `design.md` and `tasks.md`. See [AGENTS.md](AGENTS.md).
