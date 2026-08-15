# John

3D platformer playground for **Godot 4.7** — movement, vaulting, Minecraft-style hotbar/inventory, potato grenades, punching, physics toys, and a smart navigation system driving procedurally animated enemies across a 400×400 m showcase map.

## Run

```bash
./run.sh
# or
flatpak run org.godotengine.Godot --path /path/to/john
```

## Controls

| Action | Key |
|--------|-----|
| Move | WASD |
| Look | Mouse |
| Jump | Space |
| Sprint | Shift |
| Crouch | Ctrl |
| Inventory | E / I |
| Hotbar | 1–9 / scroll wheel |
| Use item (grenade) | LMB / F |
| **Punch** | **RMB / Q** |
| Toggle camera | F3 (first / third person) |
| **Nav-graph debug view** | **F4** (nodes, edge types, live enemy paths) |
| Free mouse | Esc |

## Inventory

- Pickups go into the **bag** (open with E)
- **Drag** bag items onto the bottom **hotbar**
- Right-click a hotbar slot (with inventory open) to stash it back
- Select a hotbar slot, then LMB to use (grenades throw + explode)

Grenade pickups in the world **respawn after a few seconds**.

## Smart navigation

Enemies plan routes on a **custom voxel-sampled surface graph** (`scripts/nav/`)
built asynchronously at startup from all static geometry:

- **Typed edges**: WALK, STEP (small rises), DROP, JUMP (ballistic gap
  crossings), CLIMB (ledge grab + clamber) and WALL (floor↔wall transitions).
- **Clearance-aware**: every node stores headroom + lateral clearance, so each
  body only takes routes it physically fits through — crawl tunnels admit
  centipedes and spiders but reject centaurs ("maximum hole size").
- **Per-enemy profiles**: `nav_mode` (basic / parkour), `can_wall_walk`,
  jump strength, step height. Imps and humans parkour (jumps + hand-planted
  ledge climbs), spiders walk straight up walls, centaurs stay ground-bound.
- **Reactive step-up sensors** handle tiny ledges (≤0.6 m) instantly, even
  off-graph — small obstacles never stall a chase.
- A\* queries are budgeted per frame and repaths are staggered; distant
  enemies sleep (animation + AI LOD).

Press **F4** to see the graph and every enemy's current path.

## Knockback & grip

- Grenades and punches call the enemies' `apply_knockback` API: impulse is
  scaled by body mass (imps fly, centaurs stumble) and the procedural body
  visibly reels at the hit point — nearby feet are knocked loose.
- Every body has **grip strength**. Hits weaker than grip only shove; hits
  stronger (or repeated hits — grip wears down) **override the feet's grip**,
  rip even wall-walking spiders off their surface, and send the body into a
  ballistic tumble until it lands and recovers.

## World (400×400 m)

The original playground is the central **Spawn Plaza** (platform trail ~32 m,
spiral tower, sky bridge, Jenga, cube pile, ball pit, kegel lane). Roads with
signposts lead to feature districts:

| Zone | Shows off |
|------|-----------|
| Ledge Steps Field | 0.25–0.6 m micro-ledges — nobody gets stuck |
| Parkour Gauntlet | imps jump gaps and climb staggered ledges |
| Spider Canyon | wall-walking spiders on sheer walls, rickety plank bridge, grenade caches |
| Crawl Tunnel Warren | three graded tunnels — bodies route by what they fit through (watch with F4) |
| The Silo | hollow tower; exterior grab-ledge spiral, spider highway inside, **Broodmother** boss with massive grip |
| Knockback Range | shelves of kegel pins, perched enemies, the golden **Kegel King** (topple him…) |
| Rooftop District | jump-linked flat roofs, parkour pursuit |
| Windmill | rotating sails + rideable carousel, one wall-walking centipede |

Plus launch pads that fling anything (including enemies — grip check applies),
and at least one unmarked secret worth finding.

## Procedural animation

Enemies have **no keyframed or sine-wave animation**. Bodies are described by a
`ProcBodyPlan` resource (spine segments, legs, arms, head, tail — any counts),
built into a skeleton at runtime and driven entirely by simulation:

- **Legs** track the ground: feet stay planted in world space and take real,
  raycast-placed steps when they drift too far from home. A gait rule (neighbor
  feet can't swing together) makes bipeds alternate, quadrupeds trot, and
  spiders/centipedes ripple — emergently, per body form.
- Foot rays cast along the **body's own up axis**, so the same legs plant on
  floors, walls and ceilings while wall-walking.
- **Per-joint settings**: every joint has a role and preferences — preferred
  rest angle, stiffness/lag (tail and rear segments follow through), knee bend
  direction, rotation limits.
- **Head** looks at the player within neck limits; when the neck strains past
  comfort the torso turns (stepping with its legs) until the head relaxes.
- **Hands** aim at the target and strike with windup → hit → recover curves;
  the same hand system pins to ledge lips during parkour climbs.
- **Impacts** (`apply_impact`) kick the root, spin the spine and unplant feet
  near the hit for readable knockback on any body form.

Add a new body form in `scripts/anim/proc_body_plan.gd` (see the five presets)
and pass its name as the enemy's `body_form`.

## Layout

```
scripts/player.gd           Movement + vault + throw + punch
scripts/inventory.gd        Autoload bag + hotbar
scripts/inventory_ui.gd     Hotbar / drag-drop UI
scripts/world_pickup.gd     Collectibles
scripts/grenade_projectile.gd
scripts/world_builder.gd    Procedural level: plaza + showcase zones
scripts/launch_pad.gd       Impulse pads
scripts/rotating_platform.gd  Windmill sails / carousel
scripts/kegel_king.gd       Golden pin → grenade shower
scripts/enemy.gd            Enemy brain (chase / path / jump / climb /
                            wall-walk / launched states, grip + knockback)
scripts/nav/nav_graph.gd          Surface graph: sampling, typed edges, A*
scripts/nav/nav_agent_profile.gd  Per-agent size + capability profile
scripts/nav/nav_debug_draw.gd     F4 visualization
scripts/anim/proc_body_plan.gd     Body form definitions (5 presets)
scripts/anim/proc_body_builder.gd  Runtime skeleton + visuals generator
scripts/anim/proc_animator.gd      Gait, spine, head, arms, tail solver
scripts/anim/proc_leg.gd           Planted-foot stepping state
scripts/anim/proc_ik.gd            Two-bone IK + rotation helpers
```
