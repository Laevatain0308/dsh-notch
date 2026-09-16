# The Notch provider protocol

The only thing a provider and Notch share. Nothing here names a provider: Core must serve a source it has never heard of, so the vocabulary is grouped by **behaviour pattern** rather than by domain, and that grouping is the permission model — a provider is granted classes, and a class is what the user consents to.

`v1/` is the current version. Behaviour is specified in [`openspec/changes/standalone-notch-ecosystem`](../openspec/changes/standalone-notch-ecosystem); this directory is that specification made executable, and a disagreement between the two is a bug in one of them.

| File | Holds |
| --- | --- |
| `v1/index.ts` | The five behaviour classes, their states, the lifetimes, every numeric bound, every refusal code, and the message types |
| `v1/session.ts` | One provider's connection and the rules its messages must satisfy |
| `v1/core.ts` | Every session at once, and the limits none of them can enforce alone |
| `v1/conformance.json` | The contract as data: message sequences and the outcomes they must produce |

## Why the classes are not named after domains

`harness`, `browser`, `media` cannot be reasoned about: two providers in one domain need different authority, and one provider may span domains. A behaviour class is legible without knowing the provider — "this program may show progress" — and it is enforceable, because a state outside the granted classes is refused outright.

| Tier | Class | Meaning | May require a decision |
| --- | --- | --- | --- |
| informational | `ambient` | a read-only state with no lifecycle | no |
| informational | `progress` | quantified advance, determinate or not | no |
| informational | `activity` | present or absent; concurrency is the entity count | no |
| terminal | `result` | one outcome, with unread semantics | no |
| adjudicative | `awaiting` | work is blocked until the user decides | **yes** |

Failure is a state of `result`, not a class: a failure and a success share a lifecycle and unread semantics and differ only in how Notch draws them.

## Shape of the exchange

A provider connects to an endpoint Notch owns, registers, sends a **snapshot**, then deltas. Notch grants a subset of the requested classes and states the bounds it will enforce. Everything Notch sends back is either a request (`action.invoke`) the provider interprets itself, or the settlement of an interaction.

Two rules that carry most of the design:

- **Identity is observed, not claimed.** Notch takes the provider's identity from the transport, never from the registration. `displayName` in a registration is a display hint and carries no authority.
- **A delta needs the snapshot that opens a subscription.** Applying one without it would let a reconnecting provider's partial view overwrite what Core holds.

## The conformance corpus

Core is written twice: once here, where the rules can be tested in a few
milliseconds, and once in Swift, where the island lives and where a provider's
identity can be read from the operating system. Two implementations of one
contract drift unless something holds them together, so the contract itself is a
file — `v1/conformance.json` — and both implementations replay it.

The corpus speaks only the wire: connect a provider, deliver a message at a
time, and observe. It never calls an implementation's internals, so nothing in
it needs translating.

| Operation | Asks for |
| --- | --- |
| `connect` | a session for an identity, optionally with a display name |
| `receive` | deliver one provider message, and whether it was accepted — with its refusal code when it was not |
| `tick` | advance the clock, and what must be reported back to which provider |
| `disconnect` | the connection ended, and what it left outstanding |
| `answer` | the user answers the decision on screen |
| `decision` | what the user is being asked, and what waits behind it |
| `entities` | what one provider holds: key, class, state, and whether it is unread |
| `providers` | the registered providers, their classes and their entity counts |

Two conventions keep expectations independent of how an implementation stores
things: `tick` and `disconnect` results are compared as a set ordered by
provider, and `providers` as a set ordered by identity. Anything the corpus does
not state is not compared.

A refusal is checked by `code`, never by its prose: the reason is written for a
person and an implementation is free to word it differently, while the code is
what a provider branches on.

## Where it runs

The rules are implemented twice, and the corpus is what keeps them equal.

| | TypeScript | Swift |
| --- | --- | --- |
| Files | `v1/index.ts`, `v1/session.ts`, `v1/core.ts` | `macos/Sources/Protocol.swift`, `ProviderSession.swift`, `NotchCore.swift` |
| Runs where | the tests, and a provider's own side | inside the Notch application |
| Held to the corpus by | `npm test` — every case is a test named `conformance: …` | `npm run test:conformance` — a probe that replays the same file and prints `FAILURES=0` |
| The endpoint | none — it is the Swift side's to own | `macos/Sources/Endpoint.swift`, checked by `npm run test:endpoint` |
| The surface | none — presentation is the island's alone | `macos/Sources/Surface.swift`, checked by `npm run test:surface` |

The Swift one is the one that ships. It has to be: a standalone desktop
application cannot require a Node runtime to answer a question, and a provider's
identity can only be read from the operating system by native code — Node
exposes no way to ask for a local peer's process. So the TypeScript is where a
rule is easiest to read, change and check, and the Swift is where it runs. Change
one, and the corpus tells you whether you changed the other.

Nothing in the Swift implementation reads the corpus differently: it starts a
`NotchCore`, replays connect/receive/tick/answer/disconnect, and compares what it
observes against the same expectations, field for field. Its `objection` function
is the comparator — a corpus expectation is a statement about the fields it
names, and nothing else is compared.

One asymmetry is deliberate. The TypeScript rules read a parsed JavaScript
object, where a field that is present and a field that is wrong both exist;
Swift cannot decode into typed structs without inventing refusals of its own —
`message-invalid` where the contract says `fraction-invalid`. So the Swift
`ProviderMessage` carries the message's fields unread and every judgement comes
from the rules, exactly as it does in TypeScript.

## Status

The contract is implemented and tested here, and the corpus passes — 94 tests,
27 of which replay it. Nothing is wired to anything yet: Core runs in the tests
rather than in the application, and the DSH plugin is still a host plugin rather
than a provider adapter.

It needs no build step today because only the tests import it. It joins the
build when a Node SDK consumes it at runtime.
