# Provider protocol

## Purpose

The protocol is the only connection between a provider and Notch. Neither reaches into the other: Notch contains no behaviour that recognises a provider, and a provider learns nothing about how Notch draws. State travels as events from the provider; the provider declares the actions Notch may invoke back, and interprets them itself.

## ADDED Requirements

### Requirement: Notch owns the endpoint

Notch SHALL own the well-known local endpoint that providers connect to; a provider SHALL NOT host an endpoint that Notch must discover.

#### Scenario: A provider starts

- **WHEN** a provider starts
- **THEN** it SHALL connect to Notch's endpoint
- **AND** SHALL NOT require Notch to locate it first

#### Scenario: Notch is not running

- **WHEN** a provider starts and Notch is not running
- **THEN** the provider SHALL continue without Notch
- **AND** SHALL NOT fail the work it exists to do

### Requirement: Notch is started by the user alone

Notch SHALL be started by the user or by a login item the user enabled; a provider SHALL NOT start it and SHALL NOT ask the operating system to open it.

#### Scenario: A provider finds Notch absent

- **WHEN** a provider starts and Notch is not running
- **THEN** the provider SHALL wait
- **AND** SHALL NOT launch Notch
- **AND** SHALL NOT request the operating system to launch it


### Requirement: Providers declare the actions Notch may invoke

A provider SHALL declare at registration which actions Notch may invoke on it, with their argument and result types, and Notch SHALL contain no knowledge of what those actions mean.

#### Scenario: The user activates an entity

- **WHEN** the user activates an entity whose provider declared an action for it
- **THEN** Notch SHALL invoke that action
- **AND** the provider SHALL interpret the invocation
- **AND** Notch SHALL NOT act on the provider's semantics

#### Scenario: No action is declared

- **WHEN** Notch would invoke an action the provider did not declare
- **THEN** Notch SHALL NOT invoke anything

### Requirement: State is pushed, never polled

A provider SHALL push its state changes as events, and Notch SHALL NOT request a provider's state on a schedule.

#### Scenario: Provider state changes

- **WHEN** a provider's entity changes state while the connection is healthy
- **THEN** Notch SHALL learn of it without asking

### Requirement: Registration negotiates version and classes

Registration SHALL carry the protocol version and the requested behaviour classes; Notch SHALL answer with its protocol version, the granted classes, and the limits it will enforce.

#### Scenario: Incompatible protocol version

- **WHEN** a provider's protocol version is incompatible with Notch's
- **THEN** Notch SHALL refuse the registration with a stated reason
- **AND** SHALL NOT apply it partially

### Requirement: Subscriptions begin with a snapshot

A provider SHALL send a full snapshot of its entities when a subscription begins, and Notch SHALL reject deltas that arrive before one.

#### Scenario: Reconnect after either side restarts

- **GIVEN** a connection was lost for any reason
- **WHEN** a provider reconnects
- **THEN** it SHALL send a full snapshot before any delta
- **AND** Notch SHALL replace its view of that provider's entities from that snapshot

#### Scenario: Delta without a snapshot

- **WHEN** a delta arrives in a subscription that has received no snapshot
- **THEN** Notch SHALL reject it

### Requirement: Provider liveness is leased

Registration SHALL establish a lease that the provider renews every 2 seconds and that expires after 6 seconds, and Notch SHALL remove the entities of an expired lease.

An accepted message SHALL renew the lease; a refused one SHALL NOT, because a provider that is not being understood is not evidence of a provider that is alive.

#### Scenario: A provider sends only messages Notch refuses

- **WHEN** a provider's messages are all refused until its lease expires
- **THEN** its entities SHALL be removed
- **AND** it SHALL have to register again

#### Scenario: A provider dies silently

- **WHEN** a provider stops renewing its lease
- **THEN** Notch SHALL remove its entities once the lease expires

#### Scenario: A provider unregisters

- **WHEN** a provider unregisters
- **THEN** Notch SHALL remove its entities immediately

#### Scenario: A lease lapses and the provider comes back

- **WHEN** a provider's lease has expired
- **THEN** its grant SHALL have ended with it
- **AND** a later message from the same identity SHALL be rejected until it registers again

### Requirement: A refusal states a code and a reason

Every refusal SHALL carry a code from a stated vocabulary alongside the reason the provider is told, so a provider can act on it without reading prose.

#### Scenario: A message is wrong in more than one way

- **GIVEN** a provider that already holds a decision
- **WHEN** it sends a message that is both invalid and over a bound
- **THEN** the refusal SHALL name the invalid message, not the bound
- **AND** a message that is well formed SHALL still be refused for the bound

### Requirement: An answer reaches only the question shown

Notch SHALL deliver an answer only to the decision the user is looking at, and SHALL refuse one addressed to any other.

#### Scenario: An answer addressed to a question that is not on screen

- **GIVEN** one decision is on screen and another waits behind it
- **WHEN** an answer arrives addressed to the waiting one
- **THEN** Notch SHALL refuse it
- **AND** both decisions SHALL remain as they were

### Requirement: A pending interaction never strands the user

Notch SHALL settle an interaction whose provider has become unreachable, or whose deadline has passed, rather than leaving it outstanding.

#### Scenario: A decision outlives its deadline

- **GIVEN** a decision has been outstanding for fifteen minutes
- **WHEN** nothing has answered it
- **THEN** Notch SHALL settle it as cancelled

### Requirement: A provider may ask for a different deadline

Notch SHALL apply a fifteen-minute deadline by default, SHALL honour a deadline its provider asks for within a stated range, and SHALL bound that request rather than accept it.

#### Scenario: A provider asks to be answered within the minute

- **WHEN** a provider states a deadline shorter than the default but within the range
- **THEN** the decision SHALL be settled at the deadline the provider asked for

#### Scenario: A provider asks for a deadline Notch will not give

- **WHEN** a provider states a deadline below the shortest Notch allows, or above the longest
- **THEN** Notch SHALL use the nearest bound it does allow

#### Scenario: A provider asks for something that is not a duration

- **WHEN** a provider states a deadline that is not a positive number of milliseconds
- **THEN** Notch SHALL refuse the interaction
- **AND** SHALL NOT raise or lower it into one

#### Scenario: Provider disappears while awaiting a decision

- **GIVEN** an entity is awaiting a decision
- **WHEN** its provider's lease expires
- **THEN** Notch SHALL settle the interaction
- **AND** SHALL stop presenting it as awaiting
- **AND** SHALL record that the interaction was abandoned, not withdrawn

#### Scenario: A decision nobody answers

- **GIVEN** an entity has been awaiting a decision
- **WHEN** the decision deadline passes without an answer
- **THEN** Notch SHALL settle the interaction as cancelled
- **AND** SHALL release the provider to raise its next decision
- **AND** SHALL present no later decision for that entity in its place

#### Scenario: A provider holds a decision open by re-sending it

- **GIVEN** an entity is awaiting a decision
- **WHEN** its provider re-sends that entity repeatedly
- **THEN** the decision deadline SHALL stay as first set
- **AND** the decision SHALL be settled when that deadline passes

#### Scenario: One decision at a time per provider

- **WHEN** a provider with an outstanding decision raises another
- **THEN** Notch SHALL refuse the second
- **AND** SHALL accept the next once the first is settled, by answer, withdrawal, abandonment, or deadline

#### Scenario: A refused decision leaves nothing behind

- **GIVEN** the adjudicative queue is full
- **WHEN** a provider raises a decision and is refused
- **THEN** it SHALL hold no entity for it
- **AND** asking again once the queue has room SHALL succeed

#### Scenario: A provider reconnects with a decision pending

- **GIVEN** a provider holds the decision on screen
- **WHEN** it reconnects under the same identity
- **THEN** Notch SHALL keep its place in the queue
- **AND** SHALL NOT ask the user the same question twice
