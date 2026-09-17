# Adding a motion

Motion belongs to Notch, not to a provider. A provider says what state is; Notch
decides what that looks like, and it decides by looking the change up in a
catalogue keyed on the change itself. Nothing else — no provider-supplied curve, no
duration, no keyframe, and no branch anywhere that asks which provider sent it.

So adding a motion is three edits, in this order.

## 1. A catalogue entry

`macos/Sources/MotionLibrary.swift`, in `entries`:

```swift
entry(.settle, to: .nothing, "the ring closes as the last of it ends"),
```

- The first argument is a `Motion`: the drawing itself, shared by every transition
  that resolves to it. Add a case to the enum only when nothing existing will do.
- The rule names what the change *became* (and optionally what it was). A rule that
  names the destination outranks one that only names the origin, because a motion
  says what something became.
- Write `plays` for the person who has to read the list, not for a log.

**The fallback is not an entry.** It is what plays when nothing matches, and
cataloguing it would make every transition a match — which would leave the gap log
with nothing to report and the library with no way to say what is missing.

## 2. A scene

`macos/Sources/MotionBrowser.swift` builds one card per entry automatically, so most
motions need nothing here. A motion that needs its own setup — a particular count of
running entities, a decision already on screen — gets it by extending
`MotionLibrary.surface(_:count:)`, which is the single fixture the scenes and the
probes share.

A **state** goes in `MotionLibrary.states` rather than `entries`, and its card holds
it: the island is put into that state and left there, because a state is watched by
waiting. A **change** gets a card that snaps to its starting state and then plays,
over and over — a motion watched once is a motion nobody can compare with the one
beside it. A change is never animated into from the previous card's ending: two
motions shown in sequence are not a transition between them.

A motion exists only when it renders in the browser. An entry whose scene draws
nothing is not a motion; it is a claim about one.

## 3. Check the key

```sh
npm run test:motion-library   # the catalogue against what the island can show
npm run build:app && open dist/Notch.app --args --motions
```

The probe checks the list the way a list is checked: no two entries claim the same
transitions, every motion is either catalogued or is the fallback, every entry
serves at least one transition the island can produce, and a transition with no
entry resolves to the fallback and is recorded. It prints the transitions that fall
back, because that is the list somebody authoring motion needs — fourteen of
forty-two at the time of writing, all of them one kind of informational state
becoming another.

Then watch it. The probe cannot see what a motion looks like, and the list cannot
either.

## What a gap means

A transition with no entry is not a defect. It plays the recorded fallback, which
is a real motion — the ring settling into its new shape — and it is recorded where
Notch's authors read and not where the user does. That record is the answer to
"what should be authored next", which is why it is keyed by transition rather than
logged as a stream: the useful question is what is missing from the library, not
what happened at 14:03.
