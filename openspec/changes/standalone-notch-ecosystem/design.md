# Design: standalone Notch with a provider ecosystem

This is the reasoning record for the change. Behaviour contracts live in `specs/`; this file holds the technology choices, the alternatives rejected, and the open questions. It is written so a later reader can tell *why* the shape is what it is, including the parts that were argued about.

## 1. Entities and identity, not messages

**Decision.** The unit of exchange is an **entity with a stable identity** that a provider owns and updates. Notch animates transitions between successive states of one entity.

**Why.** The motion worth preserving is transition-shaped, not message-shaped. In the current implementation:

| Motion | The transition it expresses |
| --- | --- |
| The result arc departs → draws → arrives → returns to blue | a finished result merging into a still-running count |
| The robot departs on work, resumes blinking when it ends | idle → busy → idle, with identity held across it |
| Capsule morphs into panel, content swapped mid-flight | collapsed → expanded |
| The amber decision pen spins and hands back to blue | awaiting → running |

Each is `f(previous state → next state)` for one entity. A fire-and-forget notification API can express none of them, which is why this is the first decision rather than a detail.

**Consequence.** Identity must survive updates, so providers address entities by a provider-scoped key rather than by sending new records. An update that cannot be matched to an existing entity is an *appearance*, and Notch picks the appearance motion — the provider does not get to claim continuity it does not have.

## 2. The capability surface is classified by behaviour pattern

**Decision.** Capabilities are grouped by **behaviour pattern**, not by domain. A provider asks for behaviour classes; it is granted a subset. `awaiting` is its own tier.

**Why.** Domain-named capabilities (`harness`, `browser`, `media`) cannot be reasoned about: two providers in the same domain need different authority, and one provider may span domains. Behaviour classes make the grant legible to the user ("this program may show progress") and make the constraint enforceable, which is the point — the classification *is* the permission model, not merely documentation.

**Proposed classes** (final naming is an open question):

| Tier | Class | Meaning | May it require a decision? |
| --- | --- | --- | --- |
| Informational | `ambient` | a持续 read-only state (now playing, current video) | no |
| Informational | `progress` | quantified advance, determinate or not | no |
| Informational | `activity` | present/absent, with a concurrency count | no |
| Terminal | `result` | one outcome — succeeded, failed, interrupted — with unread semantics | no |
| Adjudicative | `awaiting` | work is blocked until the user decides; the answer returns | **yes** |

**Rejected.** A free-form schema where a provider supplies its own state names and Notch maps them. That is the "Notch adapts to providers" failure: every new provider would require a Core change, and the mapping would be a place for providers to smuggle semantics past the permission model.

**Rejected.** Letting a provider supply markup or arbitrary option text for `awaiting`. That makes Notch a renderer and makes the interaction surface spoofable.

## 3. The protocol is bidirectional, and providers declare their own callbacks

**Decision.** Registration declares, alongside the requested classes, the **actions** Notch may invoke on that provider. Notch routes an invocation back over the same connection; the provider interprets it. Notch knows only the action's name and its declared argument/return types.

**Why.** The current design needed this and got it wrong. "Jump back to this session" is DSH semantics, but Notch has to be the one that notices the click. Today it is a `/dsh-notch/focus` wish that a browser page is supposed to poll — and that page does not exist, so the feature is inert. Making it a provider-declared action both fixes it and removes the concept from Core.

**Shape.** Two message families over one connection:

- provider → Notch: `register`, entity upsert, entity remove, interaction request, interaction cancel, acknowledgement
- Notch → provider: `snapshot.required`, action invoke, interaction answered / timed out / cancelled, granted capabilities

**Rejected.** Notch calling back over a *separate* provider-hosted endpoint (the current shape, inverted). It would reintroduce discovery, a second credential, and a second failure mode for no gain, since the provider already holds a connection.

## 4. Authorization: consent that cannot itself be abused

The requirement is that a provider becomes valid only after the user allows it, and that the consent interaction must not become the intrusion. The design:

**a. Identity comes from the transport, never from the provider.** On connect, Notch derives the peer's identity from the operating system — the connecting process's pid via the socket, then its executable path and code signature — and pins consent to that. A provider cannot claim a name; it can only be *observed* to be a program. Consent is invalidated when the binary changes, so replacing an authorized program does not inherit its authority.

**b. The consent surface is reserved and non-composable.** It is drawn by Core in a region providers cannot occupy, above all provider content, and it is **not an entity** — it cannot be produced, styled, queued alongside, or dismissed by any provider. If consent were rendered through the normal entity path, a provider could plausibly spoof it.

**c. The consent surface accepts no provider content.** It shows: the observed program identity, the requested behaviour classes rendered as plain sentences from Core's own catalogue, and allow/deny. No provider-supplied text, icon, image, link, or option list. No "learn more". Nothing that scrolls. This is the specific answer to "control the intrusion surface": the dialog is a fixed form with one variable — which classes.

**d. `awaiting` is a separate grant and a separate prompt.** It is the only class that can ask the user to decide something, so it is the phishing vector. Granting informational classes must not imply it. A provider that holds it must be identifiable *at the moment it asks*: the expanded panel names the source. Cap the number and rate of outstanding interactions a provider may hold.

**e. Consent can only be requested, never forced.** A prompt is triggered by a connection attempt, is dismissible, is rate-limited per identity, and is never shown while the user is answering another interaction — it queues. Silence is a denial. Nothing renders before consent; an unconsented provider's entities are dropped rather than queued.

**f. Revocation belongs to Notch.** The user revokes from Notch's own surface, never from the provider, and revocation removes the provider's entities immediately. A local record of what was granted, to whom, and when is retained for review.

**Open question.** Whether a provider may re-request after denial, and after how long. Re-prompting is how nagging starts; never re-prompting means a mis-click is permanent. Current lean: allow re-request only from a fresh connection after an explicit user action, with a floor on the interval.

## 5. Display arbitration is Core's, and is decided up front

**Decision.** Providers never influence placement, order, size, or which entity is expanded. Core owns a deterministic policy.

**Policy sketch** (values are open questions):

- Priority order follows trust tier and recency: an `awaiting` entity outranks a fresh `result`, which outranks `activity`, then `progress`, then `ambient`.
- The capsule is bounded: at most N entities are individually represented; the remainder aggregate into a count rather than shrinking everything.
- **At most one entity is expanded.** Competing `awaiting` entities queue, with a stated order and a stated maximum; beyond it, new requests are refused rather than silently queued forever.
- Aggregation is per *class*, not per provider, so three providers' downloads present as one progress affordance rather than three.

**Why decided now.** This is the part that cannot be retrofitted. Once two providers both believe they own a slot, every later arbitration change is a compatibility break.

## 6. Leases and recovery

**Decision.** Registration establishes a lease. Providers renew it; expiry removes their entities. State arrives as a **snapshot on subscribe** followed by deltas.

**Why both.** Events alone are not enough for a long-lived ecosystem, and the failure modes are different:

- A provider that dies without unregistering leaves phantom entities. Only a lease with expiry clears them; goodbye messages cannot be relied on.
- A Core that restarts, or a provider that reconnects, has lost the delta stream. Without a required full snapshot, the two ends disagree and cannot detect it.

**Consequence.** A delta that arrives without a preceding snapshot in the same subscription is rejected — silently applying it would let a reconnecting provider's partial view overwrite Core's. Both ends must treat reconnect as "start over", which is also what makes the design tolerant of either side restarting in any order.

**Open questions.** Lease interval and expiry bound; whether Core or the provider drives the timer; what Core shows while an `awaiting` interaction's provider has gone silent (the interaction must not strand the user — the current implementation learned this and settles such waits, and that behaviour must survive).

## 7. The motion library is a first-class, enumerated asset

**Decision.** Every motion Notch owns is catalogued under an identifier keyed to the transition it serves. A transition resolves through the library; if no entry fits, Notch plays a **recorded fallback** and records the miss as a gap to be filled later. New motions are additions to the library, never provider-specific branches.

**Why.** The explicit requirement is that motion be reusable and extensible rather than re-derived per case, and that an unmatched need degrade predictably. Making the fallback and the gap log part of the contract is what keeps "we'll add a motion later" from becoming an invisible quality regression.

**Development form.** The existing demo application — thirty-odd scenes rendered from the real views, built by `tools/recording` — is the natural home: it becomes the library browser, one scene per catalogue entry, plus one for the fallback. It already runs the production views, so a catalogue entry that does not render there does not exist.

**Rejected.** Accepting provider-supplied animation parameters. Motion authored outside the library cannot be reviewed for quality, cannot be kept consistent, and makes the fallback meaningless.

## 8. Version negotiation

**Decision.** Registration carries the protocol version and the requested classes. Core answers with its version, the granted classes, and its entity/interaction limits. An incompatible major version is refused with a stated reason rather than partially understood.

**Why.** The capability surface will change. Without negotiation, a Notch update breaks every adapter, and an adapter update breaks against an older Notch. This is the same principle already established for the DSH plugin — the overlay must not be invalidated by an update on the other side — applied in both directions. Providers must degrade when a class is not granted rather than failing to start.

## 9. Polling: what stays

"Event-driven" is a rule about *provider state*, not a blanket ban. Three things are not that, and are expected to remain:

- **Pointer tracking** for hover. There is no event source for "is the cursor over the island" that behaves better than sampling; the current implementation samples at 20 Hz precisely because an `onHover`-based source flapped during the window's own resize animation.
- **Lease renewal**, which is a heartbeat, not state polling.
- **Fallback transport**, if a push channel is unavailable on some platform. Push is the default; polling is a degradation, and the protocol must be expressible either way.

One correction the change carries: the current overlay polls `/status` every 0.8 s while an SSE endpoint sits unused. Push becomes the default path, not an unused alternative.

## 10. What the existing implementation already contributes

Worth stating, because this change is mostly rearrangement, not a rewrite of the hard parts:

| Existing asset | Role after the change |
| --- | --- |
| The island's view-frame animation, pointer-owned hover, pause-when-still render loop | Core's motion substrate — already provider-agnostic in behaviour |
| The hold-and-race interaction flow (a request held for the overlay while the original answerer waits, with abort and settlement handled) | the `awaiting` machinery; its edge cases are already solved |
| The demo application and its scenes | the motion library browser |
| The DSH plugin's lifecycle work (discover, launch, stop only what was started, watch the host pid) | the adapter's own concern, and the template for how a provider launches its own helper |
| The overlay's black shell, choice panel, markdown body, idle robot and status orbit | Core's rendering vocabulary, to be re-keyed to classes rather than session rows |

## Open questions

1. Final class names and whether `result` and `alert` are one class or two.
2. Whether the transport is a Unix domain socket, a named pipe, or loopback HTTP, and whether that is per-platform. Loopback HTTP is the current code's shape and is easiest to debug; a socket gives peer identity directly.
3. Arbitration constants: capsule capacity, queue depth, aggregation thresholds.
4. Lease interval, expiry bound, and who owns the timer.
5. Whether a provider may hold more than one `awaiting` interaction concurrently.
6. Where the motion gap log surfaces — developer-facing only, or user-visible.
7. Whether the consent record is a plain file or uses the platform's credential store.
