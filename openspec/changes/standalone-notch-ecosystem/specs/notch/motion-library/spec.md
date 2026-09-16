# Motion library

## Purpose

Motion is the reason this surface exists, and it is Notch's asset rather than each provider's problem. Every transition Notch can express is catalogued under an identifier keyed to the transition it serves, so a new provider reuses motion instead of commissioning it, and an unmatched need degrades through a recorded fallback instead of silently becoming nothing. The library is enumerated, browsable, and extended by addition — never by a provider-specific branch.

## ADDED Requirements

### Requirement: Transitions resolve through the motion library

Notch SHALL resolve each state transition to a catalogued motion, and SHALL play a recorded fallback when no catalogued motion fits.

#### Scenario: A transition is catalogued

- **WHEN** a transition matches a catalogue entry
- **THEN** Notch SHALL play that motion

#### Scenario: No motion fits

- **WHEN** no catalogue entry matches the transition
- **THEN** Notch SHALL play the recorded fallback
- **AND** SHALL record the miss, so the motion can be added to the library later

### Requirement: Motion is authored only in the library

Motion SHALL exist only as catalogue entries owned by Notch; a provider SHALL NOT supply curves, durations, or keyframes.

#### Scenario: A provider supplies animation parameters

- **WHEN** a provider includes animation parameters
- **THEN** Notch SHALL ignore them

### Requirement: The library is browsable and extensible

Notch SHALL provide a way to view every catalogued motion, and a motion SHALL be considered to exist only when it renders there.

#### Scenario: Adding a motion

- **WHEN** a new motion is added
- **THEN** it SHALL be added as a catalogue entry stating the transition it serves
- **AND** SHALL be viewable alongside the existing entries

#### Scenario: A catalogue entry with no scene

- **WHEN** a catalogue entry exists but cannot be rendered in the viewer
- **THEN** it SHALL NOT be considered complete

### Requirement: The gap log is developer-facing

Notch SHALL record transitions that fall back, and SHALL present that record to Notch's authors rather than to the user.

#### Scenario: Reading the gaps

- **WHEN** a developer reviews the motion library
- **THEN** the transitions that fell back SHALL be listed
- **AND** the list SHALL NOT be presented as part of the island or to the user as information
