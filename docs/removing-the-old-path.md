# Removing the old path

Notch has two ways for state to reach the island, and everything that has gone
wrong in the last several rounds has gone wrong in the seam between them. This is
the work order for deleting one of them.

## The two paths

**Old.** The DSH Host plugin folds its sessions into a `Board`, serves it at
`/dsh-notch/status`, and the island polls it. The island's `BoardModel` holds the
rows, the lamps are drawn from the rows, the expanded panel renders the rows, and
every interaction (`/seen`, `/approve`, `/answer`, `/focus`, `/pending-focus`) is an
HTTP call back.

**New.** A provider sends entities over the socket, `NotchCore` holds them,
`Composition` turns them into a `Surface`, and the island draws that.

Both are live. The capsule draws the surface and falls back to the board; the
expanded panel draws the surface and falls back to the board's rows; the orbit's
*layout* reads the surface and its *drawing* reads the board.

## Why this is the whole problem

Every failure in this stretch has been this seam, and each was fixed on one side
only:

- the consent panel opened and drew nothing (the surface counted consent as
  content);
- the island could not be collapsed while work was running (content held the
  region);
- the green lamp could not be dismissed (the tap read the surface, the dismissal
  needed the board);
- a **non-DSH provider draws an empty ring** — the arc is laid out from the
  surface's counts and the cube and its number are drawn from the board's, so a
  provider that is not DSH gets a ring with nothing in it. This is live and
  reproducible in the demo today.

That last one is the acceptance test for step 1 below.

## Where the seam is, exactly

| File | What it still reads from the board |
| --- | --- |
| `macos/Sources/StatusOrbit.swift` | `model.busyCount`, `retainedBusyCount`, `needsAction`, `statusFlight`, `decisionReturn`, `closingDecision` — the cube, its number, and which glyph is drawn |
| `macos/Sources/IdleRobot.swift` (`IdleStatusSlot.hasStatus`) | `model.anyFailed`, `completedUnreadCount`, `busyCount` — whether the robot or the status is shown at all |
| `macos/Sources/RootView.swift` | the expanded panel's rows, ask wizard, and approval buttons; `expanded` driven by `needsAction`; `surfaceCounts` and `capsuleTargets` exist only to bridge the two |
| `macos/Sources/Client.swift` | the HTTP client and the `runtime.json` handshake |
| `src/http.ts` | the routes the island no longer needs |
| `src/board.ts` | read by the adapter **and** by the island; it should end up the adapter's own |

## The end state

- The island renders from `NotchService.surface` and the consent decision, and
  from nothing else. No rows, no polling, no fallback.
- `BoardModel` keeps what is genuinely the island's: the orbit layout, the flights,
  the expansion. It is driven by `applySurface` and its counts come from
  `Surface.summary`. It has no client.
- The DSH plugin keeps its `Board` — it is how DSH's sessions are folded — but the
  board becomes the adapter's private state, and the adapter feeds entities from it.
  Nothing else reads it.
- Every interaction is a provider action or a settlement: `action.invoke` for
  opening, `interaction.settled` for answering. `/seen` becomes the adapter's
  `markSeen` (already written), `/focus` becomes `open` plus `pending-focus`
  (already written).
- Deleted: the routes nothing calls, `Client.swift`'s HTTP surface, the board's
  expanded content, and the two bridge closures.

## Order

1. **Make the drawing read the surface.** `StatusOrbit` and `IdleStatusSlot` take
   the capsule's counts (`shownWorking`, `shownCompleted`, `shownFailed`,
   `shownDeciding`) instead of the board's. Acceptance: in the demo, the motion
   catalogue (provider-driven) and the recording cases (board-driven) draw the same
   island for the same state — the cube and its number included. Toggle with `m`.
2. **Route the interactions.** Open, answer, ack and focus go through the provider
   protocol for every provider, including DSH. The board's HTTP routes stop being
   called by the island.
3. **Retire the panel.** The expanded content is the surface's decision and slots
   only; the ask wizard and the approval buttons go, because a question is a
   decision entity and an approval is one too.
4. **Delete the fallbacks.** `surfaceCounts` and `capsuleTargets` go, and with them
   the board's counts from `BoardModel`. Anything that still needed them was a
   step that was not finished.
5. **Delete the old path.** `Client.swift`'s HTTP methods, the plugin routes with no
   callers, `runtime.json` and the pid watchdog's remains. Then the board is DSH's
   own again.

Do not do 4 and 5 before 1–3: the fallbacks are what make the island keep working
while the drawing and the interactions move.

## How to verify

- `npm test` (137 tests) and the ten probes: `npm run test:geometry|motion|motion-library|idle|scrollbar|outcome|surface|consent|conformance|endpoint`.
- `npm run build:demo && open "dist/DSH Notch Demo.app" --args --motions` — the
  catalogue, one island per entry, six to a page, `m` to switch to the recording
  cases and back. **This is the instrument that was missing**: the same program
  shows the old path's rendering and the new one's, so a difference is visible
  rather than argued about.
- The island itself: `npm run build:app && open dist/Notch.app`, and the settings
  window (`--settings`) and the catalogue (`--motions`) from the same build.
- Screenshots are the check that has caught the most defects. Take them after every
  step, and compare against `docs/motion-audit.md`'s cases, which describe what each
  state is supposed to look like.

## What has been true all along

Probes and tests have been green through every one of these failures, because they
test each side of the seam and never the seam. The cube that is missing in a
provider-driven tile is missing in the real island for any provider that is not DSH.
Assume the same is true of anything else that reads the board, and check it by
looking at the screen.
