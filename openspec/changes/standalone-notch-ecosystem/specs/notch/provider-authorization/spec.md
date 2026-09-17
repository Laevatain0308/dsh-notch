# Provider authorization

## Purpose

Notch is a system-wide output port, so any local program can attempt to write to it. Left open, that is a phishing surface: a program could present a plausible prompt and collect a click. A provider is therefore unknown until the user allows it, the allow is bound to the identity the operating system reports rather than to a name the program claims, and the consent interaction is built so that it cannot itself become the intrusion.

## ADDED Requirements

### Requirement: A provider is unknown until the user allows it

Notch SHALL render nothing from a provider until the user has allowed it.

#### Scenario: First registration by an unknown program

- **WHEN** an unknown program connects and registers
- **THEN** Notch SHALL request the user's decision
- **AND** SHALL NOT render any of its entities before that decision

#### Scenario: The entities arrive before the decision

- **WHEN** a provider's entities arrive before the user has decided
- **THEN** Notch SHALL drop them
- **AND** SHALL NOT queue them for later display

#### Scenario: Denial or silence

- **WHEN** the user denies the request, or does not answer it
- **THEN** Notch SHALL NOT render that program's entities

### Requirement: Identity is observed, not claimed

Notch SHALL derive a provider's identity from the operating system's report of the connecting process, and SHALL NOT accept an identity the provider declares about itself.

#### Scenario: A granted identity changes

- **GIVEN** a provider was granted at an observed identity
- **WHEN** the program at that identity is replaced or modified
- **THEN** Notch SHALL revoke the grant
- **AND** SHALL require the user's decision again before rendering

### Requirement: Consent is expressed over behaviour classes

The decision SHALL be expressed over behaviour classes, so that what is being allowed is legible without knowledge of the provider.

#### Scenario: Reading the consent surface

- **WHEN** the consent surface is shown
- **THEN** it SHALL state the observed program identity
- **AND** SHALL state the requested behaviour classes in Notch's own wording

### Requirement: The consent decision appears on the island

Notch SHALL present a consent request on the island itself, in the region an expanded decision occupies, in Notch's own words, and SHALL NOT require the user to open another window to answer it.

#### Scenario: A program asks while nothing else is showing

- **GIVEN** no decision is on screen
- **WHEN** a program asks to be allowed
- **THEN** the island SHALL present the request as a decision the user can answer
- **AND** SHALL offer allowing it and refusing it

#### Scenario: A decision is already on screen

- **GIVEN** a decision is on screen
- **WHEN** a program asks to be allowed
- **THEN** Notch SHALL defer the request
- **AND** SHALL present it once the region is free

#### Scenario: The user dismisses the request

- **GIVEN** a consent request is on screen
- **WHEN** the user dismisses it without deciding
- **THEN** the request SHALL stop being presented for that connection
- **AND** the program SHALL remain undecided, neither allowed nor refused

### Requirement: The consent surface accepts no provider content

The consent surface SHALL be rendered by Notch from its own catalogue, SHALL NOT be an entity, and SHALL NOT display provider-supplied text, images, options, or links.

#### Scenario: A provider supplies content with its registration

- **WHEN** a provider includes text, an icon, a link, or options alongside its registration
- **THEN** none of it SHALL appear on the consent surface

#### Scenario: Provider content overlaps the consent surface

- **WHEN** a provider's entities are displayed
- **THEN** they SHALL NOT occupy or cover the consent surface's region

### Requirement: A consent request cannot be forced

A consent request SHALL arise only from a connection attempt, SHALL be dismissible, and SHALL prompt at most once every 30 seconds per identity.

#### Scenario: Repeated attempts after denial

- **WHEN** a program connects repeatedly after being denied
- **THEN** Notch SHALL NOT prompt more often than once every 30 seconds

#### Scenario: A prompt while another interaction is pending

- **WHEN** the user is answering another interaction
- **THEN** Notch SHALL defer the consent request
- **AND** SHALL NOT interrupt the pending decision

### Requirement: Adjudicative authority is a separate grant

Notch SHALL require a separate grant for the adjudicative class, and SHALL identify the requesting provider while an interaction it raised is displayed.

#### Scenario: A provider asks the user to decide

- **GIVEN** a provider holds the adjudicative class
- **WHEN** it raises an interaction
- **THEN** the expanded surface SHALL name that provider

#### Scenario: A provider without the class raises an interaction

- **GIVEN** a provider does not hold the adjudicative class
- **WHEN** it raises an interaction
- **THEN** Notch SHALL refuse it

### Requirement: A decision reaches the program that asked

Notch SHALL tell the program what the user decided, so that waiting for a decision does not mean asking for one.

#### Scenario: The user allows a program that is waiting

- **GIVEN** a program has asked and the user has not decided
- **WHEN** the user allows it
- **THEN** Notch SHALL tell that program
- **AND** it SHALL NOT have to ask again to learn the answer

#### Scenario: The user refuses a program that is waiting

- **GIVEN** a program has asked and the user has not decided
- **WHEN** the user refuses it
- **THEN** Notch SHALL tell that program
- **AND** SHALL NOT leave it waiting for an answer that is not coming

### Requirement: Consent accumulates one class at a time

A decision SHALL be about the classes a program does not already hold, and allowing one SHALL NOT withdraw another.

#### Scenario: A program asks for one more class

- **GIVEN** a program is allowed to show progress
- **WHEN** it asks to show results as well
- **THEN** Notch SHALL ask the user about the results
- **AND** SHALL already hold the progress it was allowed

#### Scenario: The question states only what is new

- **GIVEN** a program is allowed to show progress
- **WHEN** it asks for progress and results
- **THEN** the consent surface SHALL state the results as what is being asked for
- **AND** SHALL NOT ask the user to allow progress a second time

### Requirement: The user revokes, and revocation is immediate

Notch SHALL let the user revoke a grant from Notch's own surface, and SHALL NOT depend on the provider's cooperation.

#### Scenario: Revoking a provider

- **WHEN** the user revokes a provider
- **THEN** Notch SHALL remove its entities
- **AND** SHALL refuse its further messages

### Requirement: Grants are recorded and reviewable

Notch SHALL keep a local record of each grant — the observed identity, the classes, and when it was made — in a file readable only by the user, and SHALL let the user review it.

#### Scenario: Reviewing grants

- **WHEN** the user reviews providers
- **THEN** Notch SHALL list each granted identity, its classes, and when it was granted

### Requirement: A denial is recorded and never self-reversed

Notch SHALL record a denial against the observed identity, and SHALL NOT prompt that identity again on its own initiative.

#### Scenario: A denied program reconnects

- **GIVEN** a program was denied
- **WHEN** it connects again
- **THEN** Notch SHALL NOT present the consent surface
- **AND** SHALL NOT render its entities

### Requirement: A denied provider may re-request

A denied provider SHALL obtain a fresh decision only from a new connection, only after the user has asked Notch to reconsider it, and no sooner than 10 minutes after the denial.

#### Scenario: The user asks Notch to reconsider

- **GIVEN** a denial older than 10 minutes
- **WHEN** the user asks Notch to reconsider that program
- **THEN** Notch SHALL present the consent surface on that program's next connection
- **AND** SHALL NOT present it before then

#### Scenario: The interval has not passed

- **GIVEN** a denial recorded less than 10 minutes ago
- **WHEN** the program reconnects
- **THEN** Notch SHALL NOT present the consent surface
- **AND** SHALL NOT treat the reconnect as a request

### Requirement: The user can clear a denial

Notch SHALL let the user delete a recorded denial from Notch's own surface, after which that identity's next registration SHALL be treated as a first registration.

#### Scenario: Clearing a denial

- **WHEN** the user deletes a denial record
- **THEN** Notch SHALL forget the denial for that identity
- **AND** SHALL present the consent surface on its next request
