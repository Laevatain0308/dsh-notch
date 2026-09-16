# Entity model

## Purpose

Entities are the unit of information Notch exchanges with a provider, and the reason its motion is possible. An entity has an identity that survives updates, a state drawn from the classes Notch grants its provider, and a lifetime. Notch animates the transition between successive states of one entity rather than re-rendering a list.

## ADDED Requirements

### Requirement: Entities have stable identity

A provider's entity SHALL be addressable by a provider-scoped key that is stable across updates.

#### Scenario: Update matches an existing entity

- **GIVEN** a provider holds an entity under a key
- **WHEN** it sends an update carrying that key
- **THEN** Notch SHALL treat it as the same entity
- **AND** SHALL animate a transition from the previous state to the new one
- **AND** SHALL NOT treat it as a new appearance

#### Scenario: Update does not match

- **WHEN** an update carries a key unknown in the current subscription
- **THEN** Notch SHALL treat it as an appearance of a new entity
- **AND** SHALL play the appearance motion

### Requirement: Entity state is Notch's vocabulary

An entity's state SHALL be drawn from the behaviour classes granted to its provider, and SHALL NOT be provider-defined.

#### Scenario: State outside the grant

- **WHEN** a provider sends a state its granted classes do not cover
- **THEN** Notch SHALL reject that entity
- **AND** SHALL NOT render it

### Requirement: Entities have bounded lifetimes

Every entity SHALL carry a lifetime semantic: transient, held until acknowledged, or held by its provider.

#### Scenario: Transient entity elapses

- **GIVEN** an entity declared transient
- **WHEN** its displayed duration elapses with no update
- **THEN** Notch SHALL remove it
- **AND** SHALL play the removal motion

#### Scenario: Held entity and a silent provider

- **GIVEN** an entity held by a provider whose lease is current
- **WHEN** that provider sends no update
- **THEN** Notch SHALL keep the entity in its last state

### Requirement: Acknowledgement is reported, not interpreted

Notch SHALL report a user's acknowledgement of an entity to its provider, and SHALL NOT assign it meaning.

#### Scenario: User dismisses an entity

- **WHEN** the user dismisses an entity that carries unread semantics
- **THEN** Notch SHALL stop presenting it as unread
- **AND** SHALL notify the owning provider
- **AND** SHALL leave the meaning of that notification to the provider

### Requirement: Entity count is bounded per provider

Notch SHALL allow one provider to hold at most sixteen entities at once.

#### Scenario: Provider exceeds its bound

- **WHEN** a provider registers more than sixteen entities
- **THEN** Notch SHALL refuse the excess
- **AND** SHALL report the refusal to the provider
