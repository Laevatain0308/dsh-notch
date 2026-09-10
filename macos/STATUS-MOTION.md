# Notch status motion

Request: the existing rotating blue stroke moves continuously up into a green completion count, or down into a red failure count. It returns to the blue running count only if work remains. A fluid crossing curve takes precedence over a literal figure eight. Native SwiftUI helper; same black edge-attached shell, colors and rounded system numerals; no model calls for acceptance.

Motion purpose: continuity between running and outcome. Single local stroke, 1.6 seconds including a brief arrival pause; counts stay readable, clicks remain available. Success above running, failure below. No pop, ripple or separate flying droplet. Initial history must not replay completion. New events are queued/coalesced by outcome; no overlapping flights. Reduced Motion skips travel and displays current counts immediately. Last task finishes at its destination instead of inventing a running task.

| Active reference | Decision | Artifact | Verification |
| --- | --- | --- | --- |
| motion-language | one migrating stroke, directional status semantics; static counts survive | StatusOrbitView | sampled native frames and guided live simulation |
| motion-contract | explicit start/end, queued events, reduced motion | StatusFlight and OrbitMotionFrame | phase/path checks; repeated-event and final-task checks |

Taste: preserve compact black shell, one thin status stroke and rounded numeric type. The memorable element is continuous status transfer, not decoration. Geometry stays inside shell bounds. Native rendering replaces browser motion validation because this is AppKit/SwiftUI.

Acceptance: inspect success and failure separately with the user; animation builds/tests alone do not establish naturalness. Existing hover and screen-height regressions must remain passing.

## Final brush implementation and Apple references

User correction: the moving object is a short painted stroke with a moving head and trailing tail, not a translated ring. Success/failure settle as stationary solid disks. The route begins on the current rotating arc, follows its circle to a tangent exit, draws towards the outcome, traces its boundary, fills it, then rejoins the source arc if the flight started with work remaining. Counts have fixed spatial slots. A single monotonic arc-length timeline avoids velocity resets at path-segment boundaries. RGB interpolation stays continuous. The solid disks and numeral backgrounds occlude a returning trail so it cannot paint through numbers.

The upward-success/downward-failure mapping and brush metaphor are this product's choices, not an Apple-provided animation. They apply Apple's guidance on purposeful, brief, consistent feedback and preserving user control:
- https://developer.apple.com/design/human-interface-guidelines/motion
- https://developer.apple.com/design/human-interface-guidelines/feedback
- https://developer.apple.com/design/human-interface-guidelines/accessibility

Motion never blocks click routing. An animation's return decision is fixed at its start so subsequent results cannot teleport its head; subsequent outcomes are queued. Reduced Motion renders the final disks/counts and a static running arc. No DSH model calls occur in the acceptance harness.

## Return colour and compact layout correction

The visible return trail uses a spatial result-to-blue gradient: the portion nearest the solid disk retains its result colour until it emerges, then blends into blue at the source rim. This prevents a hidden head from recolouring the entire visible tail too early. Compact height uses actual visible lamps: 44/72/100 points for one/two/three lamps, with a 200 ms layout transition. Empty outcome slots are not reserved. Rendered corridor pixels and actual window heights are verified in this revision.

## Idle robot (0.2.0)

Native vector frames sampled from OpenBotMotion plus nine original local pose timelines. Canvas interpolates 30 fps samples at display cadence. No browser process or model invocation. Neutral pose separates actions. Rare dance uses original speed; first/last geometry and colors blend back to neutral.

Task arrival freezes current pose and contracts it into the running ring over 300 ms. Clearing all results expands a central dot into the robot over 400 ms, eyes appearing last. Reversal retains current progress and geometry, and resumes the interrupted idle clip rather than snapping to neutral. Timer generations reject stale callbacks.

Checks: 10 resources present, all vector frames inside native drawing bounds, immediate idle cancellation, reverse continuity, and existing native motion/geometry probes. Native helper installed separately from the unchanged Host.
