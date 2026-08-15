# Everything New — Enemy AI / Nav Overhaul (Aug 2026)

**Status:** Uncommitted local work on top of commit `c844c94` ("Add inventory, procedural enemies with foot IK, and expanded world").

**User verdict (latest):** Pathing AI got **stupider**. Enemies correctly climb stairs now but are **hell-bent on replaying the player's exact breadcrumb line** even when they lack the same movement options (vault, sprint arcs, grabbable ledges). Territory/home/roam logic was added but trail-following dominance is the main regression.

---

## REWORK (this session) — route acquisition redesigned

The tiered fallback was rebuilt so the graph is primary and trail replay is a
validated last resort. Bad decisions reversed, in order:

### A. Route priority fixed (`enemy.gd`)
- `_process_chase()` smart-route branch now: **graph request → validated trail
  (last resort) → reactive probes → keep closing in while the graph thinks**.
  Previously any empty/pending graph result dropped straight into trail replay.
- `_on_path_result()` no longer calls `_try_follow_trail()` on an empty result.
  Empty chase results feed `_graph_fail_streak` (with a 6 s decay window);
  the trail is only considered after **2+ consecutive confirmed failures**
  and never while a query is pending or the graph is still building.
- Chase queries now target `_get_chase_point()` (player's **ground** position,
  velocity-led) instead of the raw player position.

### B. Trail replay validated, never blind (`enemy.gd`, `path_recorder.gd`)
- `_try_follow_trail()`: join radius 12 m → **8 m**; join height comes from
  `_trail_join_dy()` (ability-derived: step/jump/climb/wall) instead of a
  blanket 18 m; the validated waypoint line must **end within 4 m flat /
  2.5 m Y of the player's current position** or it is rejected — truncated
  replays to nowhere are gone.
- `nearest_index()` in the recorder now **always enforces the vertical band**
  (the old `loose_y` mode ignored `max_dy` entirely, letting street-level
  enemies latch onto rooftop crumbs).
- `_should_abandon_trail()` is now route-based: player left their own trail
  tip, player left where **this path is headed** (`_path_goal`), or a direct
  route to the player became viable → abandon immediately (`_on_route_failed`).
  While replaying a trail the enemy keeps re-querying the graph so a real
  route takes over ASAP.

### C. Fair pathfinding (`enemy.gd`)
- `MAX_PATHFINDERS`/wave-slot (`instance_id % 8`) deleted. Replaced with a
  **per-physics-frame budget of query starts** (`PATH_STARTS_PER_FRAME = 3`,
  static counters) + each enemy's existing randomized 0.75–1.2 s repath
  cooldown. Everyone gets a turn; nobody is starved into trail-following.

### D. Nav graph precision restored (`nav_graph.gd`, `world_builder.gd`)
- `CELL` 3.0 → **2.0** (stairs/step geometry sampled again).
- Bake bounds 150×150 → **360×360** (`AABB(-180,-6,-180)`) — every feature
  district is on-graph again. Build stays time-budgeted (`BUILD_BUDGET_US`
  3500 → 5000) and completes in ~5–10 s of play without a single hitch;
  32.7k nodes verified headless.
- `ASTAR_MAX_EXPANSIONS` 3500 → **8000** (worker thread only).
- `MAX_PENDING` 8 → **16**, `MAX_DELIVER_PER_FRAME` 2 → **4** (delivery is
  cheap; caps kept).
- **`_simplify()`** added on the worker: pure-geometry waypoint thinning
  (no raycasts, thread-safe) removes the grid zigzag that raycast `_smooth()`
  used to fix on the main thread. `_smooth()` remains for sync `find_path()`.

### E. Smart-route thresholds tightened (`enemy.gd`)
- The `absf(to_target.y) > 0.75` trigger is **gone** — flat-ground chase never
  pathfinds. Triggers now: rise > `max_step_height + 0.25`, drop beyond
  `max_drop + 0.5`, stuck > 0.8 s / no progress > 0.9 s, or cached
  "direct route not viable".
- `_direct_route_viable()` tolerates safe drops (up to `max_drop`) instead of
  demanding step-height flatness both ways, and fixes a bug where the
  target delta was offset by the enemy position twice.
- `_is_blocked_ahead()` probes at `max_step_height + 0.15` so hoppable curbs
  no longer count as blockers (flank checks also actually test the flank
  direction now — they compared the cached forward result before).

### F. Home / roam actually pathfind (`enemy.gd`)
- Paths are tagged with `PathPurpose` (CHASE / HOME / ROAM) at request time.
  Results for a stale purpose are dropped; home/roam paths are never
  retargeted at the player, and `_clear_path()` returns the enemy to the
  state the path was for.
- Fixed an oscillation bug: territory brain used to re-enter RETURN_HOME
  every frame while a home path was being followed (killing it), and
  re-engaged chase at 36 m while `return_distance` sent it home at 30 m —
  an infinite flip-flop. Re-engage now uses hysteresis at
  `min(chase_range, return_distance) * 0.7`.
- RETURN_HOME requests graph paths on cooldown and probes ledges when stuck;
  ROAM pathfinds to goals >3 m away and re-picks blocked goals instead of
  grinding into fences. `_on_route_failed()` near the player just re-chases;
  far away it heads home; after `max_home_return_attempts` (5) the enemy
  adopts its current spot as home and roams (all still per-spawn tunable).

### G. Kept working fixes
Enemy collision layer 8 split, budgeted build + capped deliveries, no
recursive `_process_chase`/`_process_path`, air steering + wall slide,
knockback friction + `replant_feet()`, horizontal ground chase point when
the player is airborne, crowded-skip, LOD sleep.

**Headless verified:** `--headless --quit-after 2000` → zero script errors,
`NavGraph: 32738 nodes ready`, graph ready between frames 300–600.

---

## Session arc (last ~10 messages)

1. **Enemy procedural animation + foot IK** — earlier work (proc_animator system, not the older `enemy_procedural_anim.gd` plan).
2. **GitHub push** — `c844c94` to `anonymusdennis/john`.
3. **Spawn more enemies** — `world_builder.gd` expanded spawns near player + map zones.
4. **"Scarily accurate" pathfinding** — major `enemy.gd` + `nav_graph.gd` rework: async A*, trail replay, reactive jump/climb, LOS checks.
5. **1 FPS / freeze fixes** — shrunk nav bake, time-budgeted build, capped async deliveries, enemy collision layer split, crowded detection, removed path smoothing on delivery.
6. **Stack overflow fix** — broke mutual recursion `_process_chase` ↔ `_process_path`.
7. **Four behavior bugs reported:**
   - Enemy turns around when player jumps
   - Stair jump loop (wall bounce, no mid-air control)
   - Knockback infinite slide (feet never plant)
   - Stale trail following + need home/roam when player leaves
8. **Territory brain added** — `RETURN_HOME`, `ROAM`, abandon-trail heuristics, air steering, knockback friction + `replant_feet()`.
9. **Headless validation** — game runs; no linter errors.
10. **This document** — audit for a smarter model to rework the approach.

---

## Files changed (11 files, +645 / −96 lines)

| File | What changed |
|------|----------------|
| `scripts/enemy.gd` | **+597 lines** — bulk of AI brain changes (see below) |
| `scripts/nav/nav_graph.gd` | Perf + goal-node selection + coarser graph |
| `scripts/nav/path_recorder.gd` | Looser vertical join for elevated trails |
| `scripts/world_builder.gd` | Nav bake bounds, spawn order, enemy defaults, `home_position` |
| `scripts/anim/proc_animator.gd` | `replant_feet()`, camera-distance LOD skip |
| `scripts/nav/nav_debug_draw.gd` | Capped nodes drawn, slower rebuild |
| `scenes/enemy.tscn` | `collision_layer = 8` (enemy layer) |
| `scenes/player.tscn` | `collision_mask = 13` (includes enemy) |
| `project.godot` | Physics layer 4 = `"enemy"` |
| `scripts/player.gd` | Punch hits enemy layer |
| `scripts/grenade_projectile.gd` | Explosion hits enemy layer |

---

## `scripts/enemy.gd` — detailed changelog

### New states
- `RETURN_HOME` — path/steer toward `home_position`
- `ROAM` — wander random goals in `roam_radius` around home

### New exports (`Territory` group)
- `home_position`, `roam_radius` (10), `return_distance` (30 ≈ "10 nav cells")
- `abandon_trail_height` (2.5), `abandon_trail_flat` (5.0)
- `max_home_return_attempts` (5), `roam_goal_interval` (4s)
- `use_trail_following` (true)

### New exports (`Air / Knockback` group)
- `air_control`, `air_control_jump`, `launched_friction`, `launched_max_time`

### Chase / facing fixes (for "enemy turns when I jump")
- `_get_chase_point()` — when player airborne, chase horizontal position at **ground hint** under player
- `_get_face_dir()` — XZ-only facing
- `_apply_neck_relief()` — skipped when player is clearly above

### Route acquisition changes (likely **root of stupidity**)
Three-tier fallback still documented in header, but chase logic now aggressively escalates to smart route:

```
_needs_smart_route() → true when:
  - vertical delta > max_step_height
  - stuck_timer > 0.45 OR progress_timer > 0.45
  - target Y delta > 0.75
  - cached "direct route not viable"
```

When smart route needed:
1. `_try_request_path()` (async NavGraph)
2. If empty + not pending → **`_try_follow_trail()`** ← problem
3. `_try_reactive_ascent()` (probe jump/climb lips)
4. If blocked → flank or idle

**Trail following (`_try_follow_trail`):**
- Join radius widened to **12m** with dynamic `max_dy` up to **18m**
- `path_recorder.nearest_index` now weights vertical less when `max_dy >= 8`
- Trail segments replayed and classified per enemy abilities
- `_path_from_trail = true` — abandon only via `_should_abandon_trail()` (player left trail by height/flat distance)

**This means:** once graph path fails or is pending, enemies **prefer copying player footsteps** over finding their own graph route. Player can vault/sprint; enemies cannot → they get stuck replaying impossible segments.

### Mid-air control (stair loop fix attempt)
- `_air_steer_toward()` in `JUMPING` and airborne `PATH` segments
- `_slide_along_walls()` after `move_and_slide` in jump
- `_jump_fail_streak` — after 3 bad landings → `_on_route_failed()`

### Knockback / slide fix attempt
- `_process_launched()` — ground friction (`launched_friction`), max time, `animator.replant_feet()` on land
- `_process_recover()` — replant feet each frame on floor
- `proc_animator.replant_feet()` — force all feet to ground ray hits

### Territory brain
- `_update_territory_brain()` — if player > `return_distance` → home; abandon stale trail
- `_on_route_failed()` — increment attempts; after 5 → re-home to current pos + roam
- `_process_return_home()`, `_process_roam()`, `_pick_roam_goal()`

### Performance / stability patches
- `MAX_PATHFINDERS = 8` — `_may_pathfind()` uses cheap time-wave slot (`instance_id % 8`), **not** true nearest-8 selection
- `_update_crowded()` — ray up; if something standing on enemy → skip AI/path
- `_hook_nav_graph()` — stagger repaths on graph ready
- `_process_path` no longer calls `_process_chase` recursively (stack overflow fix)
- Route cache: `_refresh_route_cache`, `_direct_route_viable`, `_has_direct_los`, `_is_blocked_ahead`

### Reactive ascent (new probes)
- `_find_jump_lip()`, `_find_climb_lip()`, `_try_reactive_ascent()`
- Fires when stuck or smart route needed

### Collision
- Enemy `collision_layer = 8`, `collision_mask = 1 | 2` (world + player, **not** other enemies)

---

## `scripts/nav/nav_graph.gd` — detailed changelog

### Performance (fixes 1 FPS / 5s freeze)
- `CELL` **1.5 → 3.0** (coarser graph, fewer nodes)
- Replaced per-frame fixed counts with **`BUILD_BUDGET_US = 3500`** (~3.5ms/frame)
- `ASTAR_MAX_EXPANSIONS` 9000 → **3500**
- `MAX_PENDING` 24 → **8**
- **`MAX_DELIVER_PER_FRAME = 2`** — caps main-thread path callbacks
- **`MAX_PENDING_DELIVERIES = 16`** — drops stale results
- **Removed `_smooth()` on path delivery** (was raycasting on main thread per result)

### Reachability tweaks
- `JUMP_DY_UP` 1.4 → **2.2**, `JUMP_DY_DOWN` 3.5 → **4.0**
- Jump links search distance **2–4 → 2–5** cells
- `_nearest_node(p, prof, for_goal)` — goal nodes search wider radius (7 vs 4), heavier Y weight (6.0 vs 1.2)

### Tradeoff
- Smaller bake area + coarser cell = **fast but imprecise** graph near stairs/ledges
- Fewer expansions + capped deliveries = enemies may **wait** for paths or get **no path** → fall through to trail replay

---

## `scripts/nav/path_recorder.gd`

- `nearest_index()` — when `max_dy >= 8`, vertical band relaxed; adds `dy * 0.35` to distance score so enemies below can latch onto elevated breadcrumbs

**Side effect:** enemies join player trail from far below and commit to climbing player's exact vertical route.

---

## `scripts/world_builder.gd`

- Nav graph bounds: `AABB(-205,-6,-205, 410×60×410)` → **`AABB(-75,-6,-75, 150×50×150)`** (spawn plaza only)
- Nav graph starts **before** enemy spawn (was after)
- `ENEMY_DEFAULTS` tuned: all forms faster, centaur now `parkour`, centipede `can_wall_walk`
- `_spawn_enemy()` sets `home_position = pos` before `add_child`

**Tradeoff:** distant map zones have **no nav graph** — enemies there rely on chase/trail only.

---

## `scripts/anim/proc_animator.gd`

- `replant_feet()` — instant foot plant after knockdown
- Skip IK/gait when >60m from camera (perf LOD)

---

## Physics layer split

| Layer | Name | Purpose |
|-------|------|---------|
| 4 (bit 8) | enemy | Enemies don't collide with each other |
| Player mask | 13 | Can stand on / punch / grenade enemies |

Fixes dogpile freeze when landing on enemy pile.

---

## Bugs fixed along the way

| Symptom | Fix attempted |
|---------|----------------|
| 1 FPS | Nav bake shrink, delivery caps, animator LOD, debug draw cap |
| Freeze ~5s after start | Time-budgeted LINK phase, smaller bake |
| Stack overflow | Remove `_process_chase` ↔ `_process_path` mutual calls |
| Landing on enemies freezes game | Enemy layer isolation + crowded skip |
| Enemy turns on player jump | Horizontal chase point + XZ facing |
| Stair wall-bounce loop | Air steer + wall slide + jump fail streak |
| Knockback infinite slide | Friction + replant feet |
| Player left stairs, enemy still climbs | `_should_abandon_trail()` + return home |

---

## Known bad decisions / still broken — **ALL ADDRESSED by the rework above; kept for history**

### 1. Trail following prioritized over graph (MAIN REGRESSION)
`_try_follow_trail()` runs when graph path is empty **even if graph could eventually solve**. Trail is treated as "proven route" but encodes **player-only affordances** (vault, sprint momentum, grabbable edges, narrower collision).

**Symptom:** Enemy climbs stairs OK, then keeps following player's line after player left, or loops on impossible segments.

**Fix direction:** Trail should be **last resort**, not tier 2. Validate each trail segment against enemy profile before adopting. Abandon immediately if segment requires vault/player-only move. Prefer graph repath to **player's current position** (or last known ground cell), not trail polyline.

### 2. `_may_pathfind()` wave slot is not fair
Only 1/8 of enemies can query per 600ms window (by `instance_id % 8`). Others fall to trail/chase → **dumb herd behavior**.

### 3. Nav graph too coarse + too small
- `CELL = 3.0` misses narrow stairs / step geometry
- Bake only covers 150×150 around origin — zone enemies off-graph
- Removing `_smooth()` may leave jagged/unreachable waypoints

### 4. Abandon-trail thresholds too weak
`abandon_trail_flat = 5m`, `abandon_trail_height = 2.5m` — player can leave stairs horizontally and enemy may still think trail is valid (compares to `rec.latest()`, not full path deviation).

### 5. `_needs_smart_route` too eager
`absf(to_target.y) > 0.75` forces path/trail for tiny height deltas → over-escalation away from simple chase.

### 6. RETURN_HOME / ROAM under-tested
- Return home uses same path system that may fail → `_on_route_failed` loops
- Roam doesn't pathfind around obstacles, just `_steer_move`
- `return_distance = 30` may not match user's "10 nodes" intent literally

### 7. Reactive ascent may fight graph path
Jump/climb probes can fire alongside PATH state, causing erratic overrides.

### 8. Performance fixes may have traded too much IQ
Capping path deliveries to 2/frame with 40+ enemies means long latency before any enemy gets a path → prolonged trail following.

---

## Architecture reference (for rework)

```
Player
  └── NavPathRecorder (breadcrumb trail in group)

WorldBuilder
  └── NavGraph (voxel A*, async worker thread)
  └── Enemies (enemy.gd)

Enemy route priority (CURRENT — problematic):
  CHASE direct → needs_smart_route?
    → request_path (async, capped)
    → _try_follow_trail (if empty)  ← CHANGE THIS
    → _try_reactive_ascent
    → flank / idle

Enemy route priority (SUGGESTED):
  CHASE direct → graph path to player ground goal
    → wait/retry graph (with backoff, fair queue)
    → local reactive probes (jump/climb) on stuck only
    → trail ONLY if graph unreachable AND trail validated per-segment
    → if player far / trail stale → RETURN_HOME → ROAM
```

### Key functions to rework
- `_process_chase()` — route escalation order
- `_try_follow_trail()` — add per-segment capability check; don't adopt whole trail
- `_should_abandon_trail()` — compare enemy progress vs player position, not just trail tip
- `_may_pathfind()` — proper fair queue or per-enemy cooldown, not wave slot
- `_needs_smart_route()` — tighten thresholds; don't trigger on minor Y delta
- `nav_graph.gd` — consider CELL=2.0 in spawn area, multi-zone bakes, restore light smoothing off-thread or pre-baked

### Tunables per spawn (existing hook)
`world_builder._spawn_enemy(root, form, pos, overrides: Dictionary)` — can set any enemy export.

---

## How to test

```bash
flatpak run org.godotengine.Godot --path /home/headadmin/Documents/projects/john
```

1. Spawn stairs — jump up, then run away flat: enemy should **not** keep climbing stairs
2. Let enemy chase up stairs — should use **graph or local probes**, not 1:1 player path
3. Knock enemy with grenade/punch — should slide, friction stop, feet replant
4. Run >30m away — enemy returns home and roams ~10m radius
5. Watch FPS with 40 enemies — should stay playable (F4 nav debug if enabled)

---

## Git state

All above is **local uncommitted** changes since `c844c94`. Run `git diff --stat` for current counts.
