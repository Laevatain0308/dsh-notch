# Tasks: standalone Notch with a provider ecosystem

Ordered so that each step produces something testable, and so the protocol is exercised by a real adapter before it is called stable.

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

- [ ] 4.1 Choose the transport (Unix domain socket / named pipe / loopback HTTP) and record why; note per-platform differences
- [ ] 4.2 Implement registration with protocol version, requested classes, declared actions, and limits in the reply
- [ ] 4.3 Implement entity operations and the interaction request/cancel/settle flow
- [ ] 4.4 Implement action invocation from Notch to the provider
- [ ] 4.5 Implement snapshot-on-subscribe and reject deltas before a snapshot
- [ ] 4.6 Implement the lease: renewal, expiry, and entity removal on expiry
- [ ] 4.7 Implement reconnect on both sides, including Core restart
- [ ] 4.8 Refuse incompatible protocol versions with a stated reason

## 5. Authorization

- [ ] 5.1 Derive provider identity from the OS: peer pid, executable path, code signature
- [ ] 5.2 Persist grants pinned to identity; revoke automatically when the binary changes
- [ ] 5.3 Build the consent surface as a reserved, non-composable, non-entity region accepting no provider content
- [ ] 5.4 Implement allow/deny, dismissal, rate limiting per identity, and deferral while another interaction is pending
- [ ] 5.5 Make `awaiting` a separate grant, and name the provider on any interaction it raises
- [ ] 5.6 Build revocation from Notch's own surface, and the grant record
- [ ] 5.7 Decide the re-request policy after denial and encode it

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

## 9. Verification

- [ ] 9.1 Test the denial path: an unconsented provider renders nothing
- [ ] 9.2 Test identity change: replacing a granted binary forces re-consent
- [ ] 9.3 Test provider death: entities expire with the lease, and a pending interaction settles
- [ ] 9.4 Test Core restart: a provider re-syncs from a snapshot and the surface converges with no duplicates
- [ ] 9.5 Test the bounds: entity cap, queue depth, aggregation threshold
- [ ] 9.6 Confirm stillness costs nothing — no continuous redraw when no transition is in flight
