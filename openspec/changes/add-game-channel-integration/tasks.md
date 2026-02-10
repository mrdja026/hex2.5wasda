# Tasks: Add Game Channel Integration

## 1. Game Channel Contract (Client)

- [x] 1.1 Define client-side requirements for the #game protocol (snapshot, updates, commands)

## 2. Godot Integration

- [x] 2.1 Add backend base URL default (localhost:8002)
- [x] 2.2 Implement a GameNetwork autoload to auth via auth_game and listen for updates
- [x] 2.3 Map snapshot/update payloads to scene entities and obstacles
- [x] 2.4 Send turn commands via REST using predefined command strings
- [x] 2.5 Remove GAME_USER_ID env requirement
- [x] 2.6 Add forced command support for out-of-turn UI actions
- [x] 2.7 Display turn carousel (previous/current/next)

## 3. Verification

- [ ] 3.1 Manual integration: connect, join #game, send move, receive updates
