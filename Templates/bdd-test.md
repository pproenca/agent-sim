# BDD Test Specification

<!-- Generated from exploration sessions. Each scenario maps to an observed app behavior. -->

## Feature: {Feature Name}

### Background

Given the app is launched in {entry state}
And the user is on the "{screen name}" screen

### Scenario: {descriptive scenario name}

- **Given** I am on the "{screen name}" screen
- **When** I tap "{element label}"
- **Then** I should see the "{expected screen name}" screen
- **And** the screen should contain "{expected element label}"

#### Evidence

- **Observed during**: Sweep {date}, Action #{index}
- **Fingerprint before**: {hash}
- **Fingerprint after**: {hash}
- **Screenshot**: {path}

---

### Scenario: {another scenario}

- **Given** I am on the "{screen name}" screen
- **When** I tap "{element label}"
- **Then** I should remain on the same screen
- **And** I should see "{expected feedback element}"

---

<!-- Each observed navigation path becomes a scenario.
     Each unexpected behavior becomes a scenario with `@bug` tag. -->

### @bug Scenario: {unexpected behavior description}

- **Given** I am on the "{screen name}" screen
- **When** I tap "{element label}"
- **Then** I should see the "{expected screen}" screen
- **But** instead I see the "{actual screen}" screen

#### Issue

{Link to issue report or inline description of the bug.}
