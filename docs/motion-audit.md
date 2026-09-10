# Native motion audit

This pass covers all 13 independent review cases using the production RootView, BoardModel, geometry, robot resources and status renderer. It does not use DSH models, network calls or real session actions. User acceptance and production installation remain separate from this self-review.

## Defects reproduced and fixed

- Returning success/failure strokes used a different phase from the running ring. A failing regression reproduced the endpoint mismatch; flights now share the running phase and matched endpoint speed.
- Blue-to-yellow incorrectly reversed the resume curve and erased its arc. It now closes the gap, changes color, fills the circle, then resolves the exclamation point, on its own 0.82-second timeline.
- Text switched between font line boxes and outlines across states. All status glyphs now use the same centered 19-point canvas. This also removes the odd/even child-frame mismatch. The exclamation point retains its separate optical correction.
- Cold snapshots incorrectly used the robot-birth acceleration despite displaying an existing task. They now start at normal speed.
- Removing the bottom result shrank the shell while leaving that disk outside the bottom edge. Its center now follows the shell bottom during the fade.
- The review heading counted playback runs rather than showing the selected case. It now displays the actual case number out of 13.

## Coverage

| Case | Examined behavior |
| --- | --- |
| 01 | Robot backflip, point handoff, concurrent number and blue stroke, rotation handoff |
| 02 | Success flight, source number alignment, returning blue arc phase |
| 03 | Failure flight and return to remaining running task |
| 04 | Last running task succeeds; result counts and shell shrink together |
| 05 | Last running task fails; result counts and shell shrink together |
| 06 | Clear red, then last green; cube arrival |
| 07 | Clear green, then last red; cube arrival |
| 08 | Robot to point, yellow ring, fill and exclamation |
| 09 | Forward closing arc, complete ring, yellow fill, symbol change |
| 10 | Yellow clears, top-origin blue drawing, deceleration to running speed |
| 11 | Decision cancellation to idle robot |
| 12 | Four status types; progressive clearing without bottom clipping |
| 13 | Approval to running; same resume motion as case 10 |

Each case was captured for 180 frames (2,340 full-component images per complete pass). Every case changed across its capture. Contact strips and transition boundaries were inspected. Cases 06, 07 and 12 were captured again after the bottom-edge fix.

Actual-size, 2x and 3x raster checks covered all four colors. The visible glyph bounding-box center matched the circle horizontally in all 12 samples. In case 02, measured horizontal glyph center remained 199.5 raster pixels across frames 20–44 while the shell grew and the count changed. These are measurements for the tested rendering setup, not a claim that fractional coordinates or antialiasing never occur on other displays.

IdleProbe covers glyph geometry, phase continuity, cold-start speed, closed-ring-before-fill, velocity handoffs, bottom containment, idle contour interpolation, blink timing, reversal and shared shell movement. MotionProbe covers route geometry, outcome queues, stale completion IDs and reduced motion.

## Reproduction

Run `sh tools/review/audit.sh /tmp/notch-review-frames` on macOS with the Swift toolchain. It builds an isolated local harness and captures all cases through NSHostingView. `NOTCH_AUDIT_CASES=6,7,12` selects a subset. The script does not install the helper or modify DSH sessions.

The interactive review remains `sh tools/review/build.sh`. Production installation is not part of these scripts.

## Follow-up: dissolve symbols and avoid clearing overlap

Cases 09 and 10 (including approval case 13) now cross-dissolve the centered numeral and exclamation outlines instead of folding their halves. Ring timing is unchanged.

Removed red, green and yellow disks now fade according to their distance from surviving neighbors. Opacity reaches zero by a 20-point center separation, before the 19-point disks and blue stroke can overlap. A sole result returning to the idle robot retains its existing handoff because there is no surviving neighbor. Cases 06, 07, 09, 10, 11, 12 and 13 are the targeted replay set for this change.

The targeted set completed 1,260 full-component captures. Transition strips were inspected, including the lower red disk becoming invisible before reaching the blue ring. Native IdleProbe passed the separation invariant and existing motion checks. The independent preview executable was rebuilt and byte-verified; production installation is still pending user acceptance.
