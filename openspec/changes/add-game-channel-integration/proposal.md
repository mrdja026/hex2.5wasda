# Change: Add Game Channel Integration

## Why

Enable the Godot game to join the #game channel and share a turn-based world with other clients by using the backend as the source of truth.

## What Changes

- Define client-facing requirements for the shared #game contract
- Add Godot integration to auth via auth_game, join #game, send commands (including forced moves), and apply state updates
- Display a turn carousel for previous/current/next
- Default backend base URL to localhost:8002

## Impact

- Affected specs: game-channel
- Affected code: Godot client networking and entity synchronization
