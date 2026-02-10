## Context

The Godot client integrates with the some-kind-of-irc backend, which is the authoritative source of #game state and turn logic. A shared contract is required so both sides interpret the same payloads and command grammar.

## Goals / Non-Goals

- Goals: minimal client integration, shared contract adherence, configurable backend target
- Non-Goals: reimplement server game logic, replace the chat UI, or add new gameplay systems

## Decisions

- Use REST for command submission and WebSockets for state updates
- Use a single GameNetwork autoload as the client entry point
- Apply updates as data-driven snapshots/deltas to keep scenes independent

## Risks / Trade-offs

- Contract drift between repos can break sync -> mitigate with manual sync of the spec

## Migration Plan

- Add configuration, implement client integration, verify with a local backend

## Open Questions

- None
