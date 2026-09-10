# Native contour and transition repair

The SVG projector may change its hull start vertex between frames. The former 64-point arclength export inherited this changing origin. Index-wise interpolation then connected unrelated contour locations: the stretch midpoint fell to 41.3% of the smaller endpoint area.

The exporter now intersects 192 fixed angular rays with a dense sampling of the original outline. Native sampling uses shape-preserving cubic Hermite interpolation; action handoffs carry the incoming geometry velocity and dissipate it over 60 ms before blending to the next clip. Authored clip durations remain unchanged.

The macOS 15+ panel uses NSAnimationContext with the same SwiftUI spring as the standalone preview (duration 0.4, bounce 0.08). macOS 14 retains a 400 ms smooth timer fallback. Top-right anchoring remains the target-frame invariant.

Validation: every adjacent clip midpoint retains at least 98% of the smaller endpoint area; 100 action handoffs preserve position and their incoming velocity; interruption/reversal and native Canvas render probes pass. Native screenshots around previously defective tilt, stretch and dance frames were inspected. The central preview was rebuilt and opened with matching resources. Production helper activation and live acceptance of the revised spring remain separate from these checks.

References: Apple WWDC23 Animate with springs, https://developer.apple.com/videos/play/wwdc2023/10158/ ; SwiftUI spring documentation, https://developer.apple.com/documentation/swiftui/animation/spring . Parameters above are project choices, not Apple-prescribed values.

## Shared status geometry and satellite handoff

Status disk positions and compact panel height now consume the same `OrbitLayout` sample. When the last running task finishes into an existing result, the red disk displacement equals the shell height change on every frame. Non-returning brush travel uses a monotone cubic schedule that reserves time for transport instead of rushing through the short connecting path. New result slots are drawn before the source slot is released. All-read snapshots cancel pending visual flights.

Natural blinking is independent of the nine full-body gestures, with 3.2–5.3 second intervals and a 90 ms close / 190 ms reopen. Sleep, explicit blinking and sneezing retain their authored eyelid timing. `satellite-out` and `satellite-in` resources derive from the original #7 timeline at 2.00–2.80 and 7.04–7.86 seconds. They preserve the fixed angular contour correspondence. Return coloration starts at the previous result color and becomes the light robot color during expansion.

Validation: native idle/continuity/layout probes and existing motion/queue/color/reduced-motion probes report zero failures. RootView frame strips cover the last-task three-to-two-light transition. Native satellite strips cover anticipation, shrink, expansion and settle. The independent native loop was rebuilt and opened with all 12 resource files verified. Production helper installation remains pending visual review of this preview.

## Review revision: faster transport, cube arrival, decision states

Result flights now take 0.95 seconds (previously 1.6); path phases and shared layout remain coupled. The outgoing robot contracts to the smaller handoff rim; the blue rim and number reveal while expanding to normal working size. Idle arrival samples original #5 cube from 2.22–3.27 seconds, including the rear-facing phase. Exports keep two invisible eye slots while the eyes are occluded.

Decision yellow is now part of OrbitLayout rather than an independently inserted VStack row. A sole running/decision exchange remains centered without changing shell height. Busy rows waiting for input are excluded from the running count. The independent review driver covers 13 named cases and clears mixed results one at a time before green/red cube arrival. It includes direct idle-to-decision, work-to-decision, resume, cancel, mixed lights and approval.

Run `sh tools/review/build.sh` for the native local-only review window. It never starts BoardModel polling and disables task interaction. The picker, replay, next and continuous-play controls were exercised through native CUA. Idle/shape/layout and existing motion/queue/color/reduced-motion probes pass. The central app bundle was replaced with 13 verified resources; production helper activation remains pending visual review.

## Tiny-point departure and reversible decision flap

Departure now has separate size and reveal channels over 900 ms: contraction reaches 6% scale at 68% of the timeline, colour transfers at that tiny point over the next 6%, and the status glyph grows only after 74%. The robot remains its sampled silhouette while shrinking, rather than morphing early into a large ring. Tests prohibit status reveal before the tiny-point threshold.

A sole blue/amber status now uses one reversible glyph: the blue arc closes and changes colour, the numeral and exclamation mark exchange through two hinged halves, and yellow fill follows. Reversal removes fill before the flap returns to the numeral. The flap is drawn within one clipped Canvas; native 3D view transforms were rejected after frame inspection exposed displaced glyph fragments. Frame strips verify no fragment outside the glyph and no flap background overlapping the ring.

The native continuity/layout and added departure/morph checks report zero failures. The central review app was replaced and cases 08–10 are available for user-visible review. Production activation remains separate.

## Continuous blue/amber refinement

The prior blue/amber transition froze the live rotation when busy became zero, then added a full turn from the morph amount; reversing that amount reversed the extra turn. DecisionSpin now integrates a continuous angular velocity over 620 ms: decelerating into amber and accelerating forward into blue. Retargeting captures the current phase and velocity. Subsequent result flights receive that actual phase too.

Morph channels now share the layout progress with overlap rather than stacking several separate eased windows. Fill grows spatially, and split-flap character halves reveal only their exposed regions, eliminating opaque flap backing. Native frame inspection, phase/velocity reversal checks and existing motion/queue/color/reduced-motion probes pass. Only the central preview was replaced; cases 09 and 10 remain available for visual acceptance.
