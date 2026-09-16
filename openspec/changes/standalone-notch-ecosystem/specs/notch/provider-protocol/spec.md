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

Registration SHALL establish a lease that the provider renews, and Notch SHALL remove the entities of an expired lease.

#### Scenario: A provider dies silently

- **WHEN** a provider stops renewing its lease
- **THEN** Notch SHALL remove its entities once the lease expires

#### Scenario: A provider unregisters

- **WHEN** a provider unregisters
- **THEN** Notch SHALL remove its entities immediately

### Requirement: A pending interaction never strands the user

Notch SHALL settle an interaction whose provider has become unreachable, or whose deadline has passed, rather than leaving it outstanding.

#### Scenario: Provider disappears while awaiting a decision

- **GIVEN** an entity is awaiting a decision
- **WHEN** its provider's lease expires
- **THEN** Notch SHALL settle the interaction
- **AND** SHALL stop presenting it as awaiting
