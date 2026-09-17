# Tasks: standalone Notch with a provider ecosystem

Ordered so that each step produces something testable, and so the protocol is exercised by a real adapter before it is called stable.

**Status.** `protocol/v1/` holds the protocol's rules as an executable module, in two halves: `session.ts` judges one provider against the rules its messages must satisfy — registration, the entity model and its bounds, snapshot-then-delta, the lease, and the decision lifecycle — and `core.ts` owns what spans providers: who is registered, who holds the adjudicative queue, and what the user is being asked. `tests/protocol.test.mjs` and `tests/core.test.mjs` cover them. `protocol/v1/conformance.json` states the same contract as data — message sequences and the outcomes they must produce — and both implementations replay it: `npm test` for the TypeScript, `npm run test:conformance` for `macos/Sources/NotchCore.swift`, which is the one that ships. `tests/protocol.test.mjs` and `tests/core.test.mjs` are where a rule is read and changed; the corpus is where the two are held equal. Nothing is wired to a transport yet, so no box below is checked: a task is done when the running application does it, not when the rule for it exists. Authorization is built in Swift as `macos/Sources/Consent.swift`, gating every message before Core sees it, with the decisions recorded against the observed program and its code hash; `npm run test:consent` covers the gate, the class expansion, the rate limit and the record. The consent *surface* is built on the island (`macos/Sources/ConsentView.swift`, presented in the region an expanded decision uses, from the observed program and Notch's own wording), the application starts the endpoint itself, and `npm run test:surface` covers the rule that the region is never shared with a provider entity. What remains before anything renders is the DSH adapter and the migration of the island's content from the board model to a composed surface.

Core now also exists in Swift (`macos/Sources/NotchCore.swift`) and passes that corpus (`npm run test:conformance`), and the endpoint exists (`macos/Sources/Endpoint.swift`, `npm run test:endpoint`): a local stream socket carrying newline-delimited JSON, with the peer's identity read from the socket rather than from anything the provider says. Boxes 4.1 to 4.5 and 4.9 to 4.10 are therefore done in substance but are left unchecked, because the endpoint is not yet started by the application and no provider has ever connected to it — and the next unit of work is exactly that wiring, since until a provider can connect no adapter can be written and nothing below can be exercised.

## 1. Extract Core from the DSH-shaped implementation

- [ ] 1.1 Split the native overlay's `BoardModel` into a provider-agnostic entity store and a DSH adapter that feeds it
- [ ] 1.2 Re-key rendering from session rows (`busy` / `unread` / `failed` / `needsAction` / `child`) to behaviour classes
- [ ] 1.3 Express "child session" as a generic related-entity concept, or drop it from Core
- [ ] 1.4 Move the host-pid watchdog and process spawning out of Core into the provider that owns that process
- [ ] 1.5 Delete the `runtime.json` handshake from Core; keep whatever the DSH adapter still needs on its own side

## 2. Entity model

- [ ] 2.1 Define entity identity, state, lifetime semantics, and update/remove operations
- [ ] 2.2 Implement appearance, transition, and removal as distinct operations with distinct motion
- [ ] 2.3 Implement acknowledgement as a provider-visible event with no Core interpretation
- [ ] 2.4 Enforce per-provider entity bounds; report refusals to the provider

## 3. Capability surface

- [ ] 3.1 Fix the class names and semantics (`ambient`, `progress`, `activity`, `result`, `awaiting`; split `result`/`alert` or not)
- [ ] 3.2 Write the provider-facing reference: each class, what it permits, its consent wording, its limits
- [ ] 3.3 Bind every class to the presentation it may produce, and reject states outside a grant
- [ ] 3.4 Decide how a new class is added, and write it down as the extension path

## 4. Transport and protocol

- [ ] 4.1 Implement the local stream socket transport: AF_UNIX on macOS/Linux, named pipe on Windows
- [ ] 4.2 Use a short fixed address, and refuse to start with a clear error when it does not fit the platform's limit
- [ ] 4.3 Clean up a stale socket file at startup without treating `EADDRINUSE` as fatal before checking liveness
- [ ] 4.4 Implement newline-delimited JSON framing
- [ ] 4.5 Document how to attach to the socket and dump the protocol
- [ ] 4.6 Implement registration with protocol version, requested classes, declared actions, and limits in the reply
- [ ] 4.7 Implement entity operations and the interaction request/cancel/settle flow
- [ ] 4.8 Implement action invocation from Notch to the provider
- [ ] 4.9 Implement snapshot-on-subscribe and reject deltas before a snapshot
- [ ] 4.10 Implement the lease: renewal, expiry, and entity removal on expiry
- [ ] 4.11 Implement reconnect on both sides, including Core restart
- [ ] 4.12 Refuse incompatible protocol versions with a stated reason
- [ ] 4.13 Enforce that a provider never starts Notch and never asks the OS to open it

## 5. Authorization

- [ ] 5.1 Derive provider identity from the OS: peer pid, executable path, code signature
- [ ] 5.2 Persist grants pinned to identity; revoke automatically when the binary changes
- [ ] 5.3 Build the consent surface as a reserved, non-composable, non-entity region accepting no provider content
- [ ] 5.4 Implement allow/deny, dismissal, rate limiting per identity, and deferral while another interaction is pending
- [ ] 5.5 Make `awaiting` a separate grant, and name the provider on any interaction it raises
- [ ] 5.6 Build revocation from Notch's own surface, and the grant record
- [ ] 5.7 Record denials against the observed identity; never prompt on the provider's initiative
- [ ] 5.8 Implement re-request: a new connection, an explicit user action, and the interval floor
- [ ] 5.9 Implement clearing a denial from Notch's surface, after which the next request is a first request
- [ ] 5.10 Implement the revocation/denial review list from task 5.6 alongside these records

## 6. Presentation and arbitration

- [ ] 6.1 Implement the priority policy and record the constants
- [ ] 6.2 Implement capsule capacity and aggregation by class across providers
- [ ] 6.3 Implement single-expansion, the competing-adjudicative queue, and the refusal path beyond queue depth
- [ ] 6.4 Verify no provider input can influence placement, order, or size

## 7. Motion library

- [ ] 7.1 Catalogue the motions that exist today, each keyed to the transition it serves
- [ ] 7.2 Define and implement the recorded fallback
- [ ] 7.3 Implement the gap log for unmatched transitions
- [ ] 7.4 Extend the demo application into the library browser: one scene per catalogue entry, plus the fallback
- [ ] 7.5 Write down the procedure for adding a new motion (catalogue entry, scene, key)

## 8. First and second adapters

- [ ] 8.1 Rewrite the DSH Host plugin as an adapter against the SDK
- [ ] 8.2 Verify the behaviour the current implementation already has survives: unread marker, dismissal, re-run switching, held question with timeout and cancellation
- [ ] 8.3 Write a second, unrelated adapter (browser download progress or media state) to test that the surface generalises
- [ ] 8.4 Record what the second adapter could not express, and decide per case: new class, new motion, or genuinely out of scope

## 8b. Notch's own lifecycle

The requirement is that the user starts Notch, or a login item the user enabled
does (`provider-protocol`). The plugin no longer launches it and the overlay no
longer exits when a Host does, so what is left is the other half of the same
sentence — the login item, which needs something to be a login item *of*:

- [x] 8b.1 Package the overlay as a `.app` bundle, which is what a login item, a Dock icon and a code signature all require
- [x] 8b.2 Sign it, so the identity consent is pinned to is a signature the user can be shown rather than an ad-hoc hash
- [ ] 8b.3 Offer "start at login" from the management window, using the login item API rather than a launch agent file the user cannot see
- [ ] 8b.5 Give it an icon, which a bundle without one shows as a blank page in Finder and in any list of login items
- [ ] 8b.4 Report, in the management window, whether the overlay is running and at what address providers may reach it — the two facts a user needs when a program says it cannot find Notch

## 8a. Where this stands

Built: the overlay no longer depends on a Host for its lifetime — it is started by
the user and stays until the user stops it, and the plugin no longer launches it.
The contract in both languages with the corpus holding them together; the
endpoint, with the peer's identity read from the operating system; consent as a
decision on the island, recorded against the executable and its code hash; the
surface that decides what is shown; the DSH adapter and the provider SDK; action
invocation; and the island drawing what Core holds.

Not yet: the compact capsule still reads the board rather than the surface, so the
old HTTP path is still carrying what is displayed at rest; the management window
the consent record is reviewed and revoked from; the motion catalogue; a second
adapter to prove the classes generalise beyond DSH.

## 9. Verification

- [ ] 9.1 Test the denial path: an unconsented provider renders nothing
- [ ] 9.2 Test identity change: replacing a granted binary forces re-consent
- [ ] 9.3 Test provider death: entities expire with the lease, and a pending interaction settles
- [ ] 9.4 Test Core restart: a provider re-syncs from a snapshot and the surface converges with no duplicates
- [ ] 9.5 Test the bounds: entity cap, queue depth, aggregation threshold
- [ ] 9.6 Confirm stillness costs nothing — no continuous redraw when no transition is in flight

## 10. Management surface

- [ ] 10.1 Build the settings window as a separate window, not a mode of the island
- [ ] 10.2 Reuse the island's visual language: colours, typography, corner treatment, motion
- [ ] 10.3 List providers with observed identity, granted classes, and grant time
- [ ] 10.4 Provide revocation, clearing a denial, and reconsidering a denied provider
- [ ] 10.5 Provide the developer-facing motion gap log section
- [ ] 10.6 Verify the island offers no configuration affordance for any of it
