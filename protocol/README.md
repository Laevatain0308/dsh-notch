# The Notch provider protocol

The only thing a provider and Notch share. Nothing here names a provider: Core must serve a source it has never heard of, so the vocabulary is grouped by **behaviour pattern** rather than by domain, and that grouping is the permission model — a provider is granted classes, and a class is what the user consents to.

`v1/` is the current version. Behaviour is specified in [`openspec/changes/standalone-notch-ecosystem`](../openspec/changes/standalone-notch-ecosystem); this directory is that specification made executable, and a disagreement between the two is a bug in one of them.

| File | Holds |
| --- | --- |
| `v1/index.ts` | The five behaviour classes, their states, the lifetimes, every numeric bound, and the message types |
| `v1/session.ts` | One provider's connection and the rules its messages must satisfy |

## Why the classes are not named after domains

`harness`, `browser`, `media` cannot be reasoned about: two providers in one domain need different authority, and one provider may span domains. A behaviour class is legible without knowing the provider — "this program may show progress" — and it is enforceable, because a state outside the granted classes is refused outright.

| Tier | Class | Meaning | May require a decision |
| --- | --- | --- | --- |
| informational | `ambient` | a read-only state with no lifecycle | no |
| informational | `progress` | quantified advance, determinate or not | no |
| informational | `activity` | present or absent; concurrency is the entity count | no |
| terminal | `result` | one outcome, with unread semantics | no |
| adjudicative | `awaiting` | work is blocked until the user decides | **yes** |

Failure is a state of `result`, not a class: a failure and a success share a lifecycle and unread semantics and differ only in how Notch draws them.

## Shape of the exchange

A provider connects to an endpoint Notch owns, registers, sends a **snapshot**, then deltas. Notch grants a subset of the requested classes and states the bounds it will enforce. Everything Notch sends back is either a request (`action.invoke`) the provider interprets itself, or the settlement of an interaction.

Two rules that carry most of the design:

- **Identity is observed, not claimed.** Notch takes the provider's identity from the transport, never from the registration. `displayName` in a registration is a display hint and carries no authority.
- **A delta needs the snapshot that opens a subscription.** Applying one without it would let a reconnecting provider's partial view overwrite what Core holds.

## Status

The contract layer is implemented and tested (40 tests). It is **not yet wired to anything**: Core does not exist, and the DSH plugin is still a host plugin rather than a provider adapter. This module is the shape that both are being rewritten against.

It needs no build step today because only the tests import it. It joins the build when Core or the SDK consumes it at runtime.
