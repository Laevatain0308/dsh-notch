# Standalone Notch with a provider ecosystem

## Why

Notch today is a DSH accessory: a DSH Host plugin owns an HTTP server, and the native overlay is its client. The overlay's states, its entity shape (`busy` / `unread` / `failed` / `needsAction` / `child`), and its one interaction flow are all DSH concepts. Nothing else can use it.

The reinterpretation is that Notch is a **system-wide output port for state and notifications** — a Dynamic Island for the desktop — whose value is the quality of its motion and interaction. Reaching that means the surface must be general, and generality must not be bought by flattening the motion into toasts.

Two concrete consequences drive this change:

- **A message-shaped protocol destroys the product.** The overlay's best motion is a function of *a transition between two states of the same entity*: a result arc that departs, arrives, and returns to running; a robot that leaves when work starts and resumes when it ends. A `show(title, body)` API cannot express either. The protocol must carry entities and their transitions.
- **The DSH-shaped surface cannot host a second provider.** With browser downloads, media, and CI added, there is no way to compose them, no way to bound them, and no way to keep one provider from spoofing another. Composition and authority have to be owned by Notch before the second provider exists.

## What changes

**Ownership of the surface**
- From: the DSH plugin spawns the overlay, serves its state, and defines its states.
- To: Notch is a standalone application owning the surface, the states, and the motion library. Providers are clients.
- Reason: an ecosystem cannot be built on a surface whose vocabulary belongs to one participant.
- Impact: breaking. The DSH plugin is rewritten as the first adapter.

**Connection direction**
- From: the plugin runs inside the DSH host and opens an HTTP server; the overlay connects to it and polls.
- To: Notch owns the endpoint; providers connect to it and push state as events.
- Reason: a provider that must be discovered and polled cannot be one of many, and polling is the wrong shape for state that changes rarely and matters immediately.
- Impact: breaking. The runtime handshake file (`origin` + token) disappears; provider identity replaces the bearer token.

**The unit of information**
- From: a snapshot of session rows, replaced wholesale on each poll.
- To: entities with stable identity, updated by transition; the surface animates the transition rather than re-rendering a list.
- Reason: identity is what makes motion possible, and what lets an entity be dismissed, re-run, or superseded without flicker.
- Impact: breaking. Every consumer of the row model is rewritten.

**Authority**
- From: everything on the local machine may connect, gated only by a token in a 0600 file.
- To: a provider is unknown until the user consents to a named set of behaviour classes, and consent is bound to the requesting program's verified identity.
- Reason: a system-wide output port that any process may write to is a phishing surface, and an `awaiting` interaction is a prompt the user is expected to answer.
- Impact: new. Registration gains a consent step; nothing renders before it.

**Detachment from DSH**
- From: `macos/` inside the `dsh-notch` repository, built and launched by the DSH plugin.
- To: a Notch application that DSH happens to be a provider of.
- Reason: the surface must outlive its first provider.
- Impact: the repository split is deferred, but every DSH-specific concept inside Core is removed now.

## Impact

- **Affected**: the DSH Host plugin (becomes an adapter), the native overlay (its row model becomes the entity model, its motion is catalogued), the provider-facing interface (new, and the primary deliverable).
- **Unaffected**: the motion and interaction work already done — the view-frame island animation, the pause-when-still render loop, the pointer-owned hover state, the choice panel. That work is the asset this change is built to preserve, and it is already provider-agnostic in behaviour.
- **Risk**: the capability surface will be wrong on first attempt. The concrete failure mode is a surface general enough for DSH and browser downloads but not for the third provider, discovered only after the SDK is public. Mitigation is that the DSH adapter is rewritten first and a second, unrelated adapter is written before the surface is called stable.
- **Security**: this change introduces the first consent boundary in Notch, and the first place a provider can ask the user a question. Both are specified before implementation.
