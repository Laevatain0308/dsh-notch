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

### Requirement: The consent surface accepts no provider content

The consent surface SHALL be rendered by Notch from its own catalogue, SHALL NOT be an entity, and SHALL NOT display provider-supplied text, images, options, or links.

#### Scenario: A provider supplies content with its registration

- **WHEN** a provider includes text, an icon, a link, or options alongside its registration
- **THEN** none of it SHALL appear on the consent surface

#### Scenario: Provider content overlaps the consent surface

- **WHEN** a provider's entities are displayed
- **THEN** they SHALL NOT occupy or cover the consent surface's region

### Requirement: A consent request cannot be forced

A consent request SHALL arise only from a connection attempt, SHALL be dismissible, and SHALL be rate-limited per identity.

#### Scenario: Repeated attempts after denial

- **WHEN** a program connects repeatedly after being denied
- **THEN** Notch SHALL NOT prompt more often than the stated interval

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

### Requirement: The user revokes, and revocation is immediate

Notch SHALL let the user revoke a grant from Notch's own surface, and SHALL NOT depend on the provider's cooperation.

#### Scenario: Revoking a provider

- **WHEN** the user revokes a provider
- **THEN** Notch SHALL remove its entities
- **AND** SHALL refuse its further messages

### Requirement: Grants are recorded and reviewable

Notch SHALL keep a local record of each grant — the observed identity, the classes, and when it was made — and SHALL let the user review it.

#### Scenario: Reviewing grants

- **WHEN** the user reviews providers
- **THEN** Notch SHALL list each granted identity, its classes, and when it was granted
