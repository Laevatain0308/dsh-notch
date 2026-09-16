# Capability surface

## Purpose

The capability surface is what Notch offers a provider, and it is grouped by **behaviour pattern** rather than by domain. The grouping is the permission model: a provider is granted behaviour classes, and a behaviour class is what the user consents to and what Notch enforces. A domain-named surface (`harness`, `browser`, `media`) could not be reasoned about — two providers in one domain need different authority, and one provider may span domains — so no domain-specific capability is exposed.

## ADDED Requirements

### Requirement: Capabilities are grouped by behaviour pattern

Notch SHALL group every provider-facing capability into a behaviour class, and SHALL NOT expose a capability named for a domain or a specific provider.

#### Scenario: A provider requests capabilities

- **WHEN** a provider registers
- **THEN** it SHALL request behaviour classes
- **AND** SHALL NOT request operation names or domain identifiers

#### Scenario: A need matches no class

- **WHEN** a provider needs behaviour that no class describes
- **THEN** a class SHALL be added to Notch's catalogue with its own consent meaning and its own presentation
- **AND** the need SHALL NOT be met by a provider-specific extension in Core

### Requirement: The behaviour classes are a closed set

Notch SHALL expose exactly five behaviour classes — `ambient`, `progress`, `activity`, `result`, and `awaiting` — and SHALL express failure as a state of `result` rather than as a class of its own.

#### Scenario: A provider needs to show a failure

- **WHEN** a provider reports a failure
- **THEN** it SHALL express it as a `result` state
- **AND** SHALL NOT request a failure class


### Requirement: Adjudicative classes are a distinct tier

Notch SHALL distinguish informational classes, which display state, from the adjudicative class, which blocks work until the user decides.

#### Scenario: Grant of informational classes only

- **GIVEN** a provider granted informational classes
- **WHEN** it requests an interaction requiring a decision
- **THEN** Notch SHALL refuse the request
- **AND** SHALL report the refusal to the provider

### Requirement: Granted classes bound what a provider may express

Notch SHALL reject any state or interaction its provider's granted classes do not cover.

#### Scenario: Message outside the grant

- **WHEN** a provider sends a state whose class it was not granted
- **THEN** Notch SHALL reject that message

### Requirement: The surface is published for provider authors

Notch SHALL publish, for each behaviour class, its semantics, what it permits, how it is worded in the consent decision, and its limits.

#### Scenario: A provider author chooses a class

- **WHEN** a provider author needs to display something
- **THEN** the reference SHALL state which class covers it
- **AND** what the class permits
- **AND** what happens when that class is not granted

### Requirement: A provider functions without an optional class

A provider SHALL remain functional when any class it requested is not granted.

#### Scenario: Partial grant

- **GIVEN** a provider granted a subset of the classes it requested
- **WHEN** it starts
- **THEN** it SHALL operate using the granted classes
- **AND** SHALL NOT fail to start
