# Native contour and transition repair

The SVG projector may change its hull start vertex between frames. The former 64-point arclength export inherited this changing origin. Index-wise interpolation then connected unrelated contour locations: the stretch midpoint fell to 41.3% of the smaller endpoint area.

The exporter now intersects 192 fixed angular rays with a dense sampling of the original outline. Native sampling uses shape-preserving cubic Hermite interpolation; action handoffs carry the incoming geometry velocity and dissipate it over 60 ms before blending to the next clip. Authored clip durations remain unchanged.

The macOS 15+ panel uses NSAnimationContext with the same SwiftUI spring as the standalone preview (duration 0.4, bounce 0.08). macOS 14 retains a 400 ms smooth timer fallback. Top-right anchoring remains the target-frame invariant.

Validation: every adjacent clip midpoint retains at least 98% of the smaller endpoint area; 100 action handoffs preserve position and their incoming velocity; interruption/reversal and native Canvas render probes pass. Native screenshots around previously defective tilt, stretch and dance frames were inspected. The central preview was rebuilt and opened with matching resources. Production helper activation and live acceptance of the revised spring remain separate from these checks.

References: Apple WWDC23 Animate with springs, https://developer.apple.com/videos/play/wwdc2023/10158/ ; SwiftUI spring documentation, https://developer.apple.com/documentation/swiftui/animation/spring . Parameters above are project choices, not Apple-prescribed values.
