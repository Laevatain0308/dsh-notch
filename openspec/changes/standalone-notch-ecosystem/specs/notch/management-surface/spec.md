# Management surface

## Purpose

Notch's own interface — the place the user governs the ecosystem rather than watches it — is a separate settings window, not the island. The island shows live state and takes a decision about it; configuration and audit are rare, deliberate, and read at length. Keeping them out of the island is what preserves the property the arbitration policy rests on: everything in the island is live.

## ADDED Requirements

### Requirement: Notch's own interface is a separate window

Notch SHALL present its settings in a window separate from the island.

#### Scenario: Opening the settings

- **WHEN** the user opens Notch's settings
- **THEN** a window SHALL appear
- **AND** the island SHALL NOT expand, change state, or host the settings content

### Requirement: The settings share the island's design language

The settings window SHALL use the same visual language as the island.

#### Scenario: Comparing the two surfaces

- **WHEN** the settings window and the island are both visible
- **THEN** colours, typography, corner treatment, and motion SHALL be recognisably the same design

### Requirement: The settings list providers and their grants

The settings SHALL list each provider with the identity observed for it, the classes granted to it, and when the grant was made.

#### Scenario: Reviewing grants

- **WHEN** the user opens the providers page
- **THEN** each granted identity SHALL be listed with its classes and grant time

### Requirement: The settings carry every governance action

The settings SHALL provide revocation, clearing a denial, and asking Notch to reconsider a denied provider.

#### Scenario: Revoking from the settings

- **WHEN** the user revokes a provider
- **THEN** its entities SHALL be removed immediately

#### Scenario: Clearing a denial from the settings

- **WHEN** the user clears a denial
- **THEN** that identity's next request SHALL be treated as a first request

### Requirement: The island never hosts configuration

Notch SHALL NOT present configuration, provider lists, or audit records in the island.

#### Scenario: Configuration is needed

- **WHEN** the user needs to change or review a grant
- **THEN** Notch SHALL direct them to the settings window
- **AND** SHALL NOT offer the action inside the island
