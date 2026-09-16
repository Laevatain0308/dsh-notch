# Presentation: arbitration and motion

## Purpose

Notch owns everything about how information appears: what is shown, in what order, how many entities are represented individually, which one is expanded, and which motion plays. Providers contribute state and nothing else. This is settled before the second provider exists, because arbitration cannot be retrofitted once providers assume they own a slot.

## ADDED Requirements

### Requirement: Providers do not influence presentation

Notch SHALL determine placement, order, size, aggregation, and which entity is expanded; a provider SHALL NOT supply any of these.

#### Scenario: A provider supplies presentation hints

- **WHEN** a provider supplies a position, an order, or a size
- **THEN** Notch SHALL ignore it

### Requirement: Priority follows tier and recency

Notch SHALL compose the surface by a deterministic policy in which an entity awaiting a decision outranks a finished result, which outranks activity, then progress, then ambient state.

#### Scenario: A decision competes with a finished result

- **GIVEN** one entity awaits a decision and another has just finished
- **WHEN** the surface is composed
- **THEN** the entity awaiting the decision SHALL be presented first

### Requirement: The surface is bounded

Notch SHALL represent at most four entities individually, and SHALL aggregate the remainder as a count rather than shrinking every entity to fit.

#### Scenario: More entities than capacity

- **WHEN** more than four entities are present
- **THEN** Notch SHALL represent the highest-priority ones individually
- **AND** SHALL represent the remainder as a count

### Requirement: Aggregation is by behaviour class

Notch SHALL aggregate entities of the same behaviour class across providers.

#### Scenario: Several providers report progress

- **GIVEN** several providers each hold a progress entity
- **WHEN** the surface is composed
- **THEN** they SHALL present as one progress affordance
- **AND** SHALL NOT present as one affordance per provider

### Requirement: One entity is expanded at a time

Notch SHALL expand one entity at a time, and SHALL queue or refuse competing adjudicative requests by a stated policy.

#### Scenario: Two entities require a decision

- **GIVEN** one entity is expanded awaiting a decision
- **WHEN** a second entity also requires one
- **THEN** the second SHALL wait, and no more than one SHALL wait
- **AND** beyond that Notch SHALL refuse it and report the refusal to its provider

#### Scenario: The queue spans providers

- **GIVEN** one provider holds the decision on screen
- **WHEN** a second provider raises one
- **THEN** the second SHALL wait rather than replace or displace the first
- **AND** it SHALL be presented once the first is settled, whoever raised it

#### Scenario: The waiting decision promotes

- **GIVEN** one decision is on screen and one waits behind it
- **WHEN** the one on screen is settled, by answer, withdrawal, abandonment, or its entity being removed
- **THEN** the waiting one SHALL become the one on screen

### Requirement: Stillness is not animated

Notch SHALL stop drawing when no state is changing.

#### Scenario: Nothing is moving

- **GIVEN** every entity is in a settled state
- **WHEN** no transition is in flight
- **THEN** Notch SHALL NOT redraw continuously
