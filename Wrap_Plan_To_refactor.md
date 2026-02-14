# Priority Fixes Summary

Based on your answers, here's the action plan:

## ✅ Confirmed Fixes

### **Priority 1: Godot Performance (Polling → Timers)**
**Issue:** Network polling every frame (60Hz) wastes CPU.
```gdscript
# game_network.gd - Move _ws.poll() to Timer
# game_network.gd - Move heartbeat tick to Timer
```
**Impact:** Reduced CPU usage, follows Godot best practices (AGENTS.md line 92).

---

### **Priority 2: Backend Collision Optimization**
**Issue:** O(n²) collision checks are unnecessary—only validate on player's turn.
```python
# game_service.py:_is_blocked_position
# Only check player positions dynamically
# Obstacles are static, check once at spawn via BattlefieldService
```
**Impact:** Reduces collision checks by ~90% (only active player's turn).

---

### **Priority 3: Static Obstacle Optimization**
**Issue:** Obstacles shouldn't check "is_blocked" every frame—they're immovable.
```python
# battlefield_service.py - Obstacles are static after generation
# game_service.py - Separate static vs dynamic collision checks
```
**Impact:** Clearer separation, faster pathfinding.

---

### **Priority 4: Godot Payload Validation**
**Issue:** No runtime checks for `game_snapshot`/`game_state_update` shape.
```gdscript
# Game.gd - Add validation in _on_network_snapshot_received
# Validate: players[], obstacles[], battlefield{}, active_turn_user_id
```
**Impact:** Catch backend bugs early, prevent silent desync (AGENTS.md line 110).

---

### **Priority 5: Grid Size in Snapshot**
**Issue:** Hardcoded 64x64 in 3 files—should come from backend.
```python
# game_service.py - Include map.width/height in game_snapshot
# Game.gd - Read BACKEND_GRID_MAX_INDEX from snapshot.map
```
**Impact:** Future-proof for map size changes.

---

### **Priority 6: WebSocket Auto-Kick**
**Issue:** Backend doesn't detect stale clients holding turn order.
```python
# websocket_manager.py - Track last_pong timestamp per client
# game_service.py - Skip turn if client hasn't ponged in 30s
```
**Impact:** Prevents dead clients from blocking turns.

---

### **Priority 7: Obstacle Cache Coherency**
**Issue:** `BattlefieldService._channel_cache` never invalidates—risk for future dynamic obstacles.
```python
# battlefield_service.py - Add cache invalidation API
# OR: Document that cache is intentionally permanent (static obstacles only)
```
**Impact:** Prevent bugs if dynamic obstacles are added later.

---

## 🔧 Implementation Order

1. **Quick wins (1-2 hours):**
   - Grid size in snapshot (Priority 5)
   - Godot Timer refactor (Priority 1)

2. **Performance (2-3 hours):**
   - Lazy collision checks (Priority 2)
   - Static obstacle separation (Priority 3)

3. **Reliability (3-4 hours):**
   - Payload validation (Priority 4)
   - Auto-kick stale clients (Priority 6)

4. **Technical debt (1 hour):**
   - Document obstacle cache behavior (Priority 7)

---

## 📊 Impact Summary

| Fix | Performance | Reliability | Future-Proof |
|-----|-------------|-------------|--------------|
| P1: Timers | ✅ Moderate | - | - |
| P2: Lazy collision | ✅✅ High | - | - |
| P3: Static obstacles | ✅ Moderate | - | ✅ |
| P4: Validation | - | ✅✅ High | - |
| P5: Dynamic grid | - | - | ✅✅ Critical |
| P6: Auto-kick | - | ✅ Moderate | - |
| P7: Cache docs | - | ✅ Low | ✅ |

---

## ✅ Deferred (Acceptable for Now)

- ❌ Turn state persistence (Redis) - Acceptable since turn-based
- ❌ NPC async processing - Acceptable with current player counts
- ❌ Battlefield in updates - Already correct (snapshot-only)

---

**Total Effort:** ~10-12 hours  
**Biggest Bang:** P2 (lazy collision) + P5 (dynamic grid) + P4 (validation)

Ready to implement? I can generate the code changes for each priority if you confirm this plan.

## 🚨 Critical Bug: Battlefield Spawn & Targeting Desync

### Summary
A critical gameplay bug remains where a playable character (human or NPC) can still end up effectively **outside the intended battlefield play zone** (e.g. misaligned into buffer tiles or off-grid space), which then breaks:
- Targeting via Tab / auto-target (no valid adjacent enemies are detected in client space)
- Click-to-move consistency (client believes a hex is valid, backend rejects or vice versa)
- Attack resolution when relying on `username`-based targeting

### Observed Symptoms
- After joining `#game`, some sessions show a player or NPC visually rendered in the buffer ring or an area the client considers non-playable.
- Tab-targeting and adjacency checks fail for that unit, even though backend state reports it as active.
- Click-to-move occasionally does nothing or results in a backend error even when the hovered hex appears valid on the client.
- Network `attack` still resolves opponents purely by `username`, which can be ambiguous or out of sync if client-side state falls behind.

### Likely Causes
- Backend and client use different coordinate spaces / mappings (backend 64x64 grid vs. Godot axial hex space), and our current normalization logic fixes most but not all edge cases.
- Battlefield snapshot is authoritative, but the client still maintains its own `is_blocked`/buffer understanding that can drift or fail to reflect late repositioning.
- Targeting is driven by `username` only, without a stable, session-scoped identifier on the client that survives reconnects and snapshot changes.

### Proposed Direction (No Code Yet)
- Treat this as a **SoT contract bug** between backend `game_snapshot` and Godot, not just a rendering glitch.
- Persist a minimal, stable identity tuple for each player/NPC on the client, for example:
  - `backend_user_id` (int) and `backend_username` (string)
  - Optionally embed this in a short-lived JWT/session token so the client can always prove "who am I" and "who am I targeting" without relying solely on display strings.
- Ensure that every snapshot/update includes both `user_id` and `username`, and that Godot stores these on the PlayerUnit permanently for the life of the session.
- Make targeting and click-to-move **primarily keyed by backend IDs**, with `username` as a human-readable label only.
- Add an explicit sanity check in Godot's network sync:
  - If any player is mapped outside the computed play zone or lands on a buffer/blocked tile, log a loud validation error and optionally request a fresh normalized snapshot.

### Acceptance Criteria
- No spawned or normalized player/NPC ever appears on a tile that the client treats as buffer or non-playable.
- Tab-targeting and adjacency logic work reliably for any active turn user, including NPCs.
- Click-to-move either results in a valid backend move or a clear backend error that matches client expectations; no more "silent" non-moves.
- Targeting uses a stable backend identity (ID + username), not just free-form strings, and remains consistent across reconnects and snapshots.
