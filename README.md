# John

3D platformer playground for **Godot 4.7** — movement, vaulting, Minecraft-style hotbar/inventory, grenades, and physics toys.

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
| Toggle camera | F5 (first / third person) |
| Free mouse | Esc |

## Inventory

- Pickups go into the **bag** (open with E)
- **Drag** bag items onto the bottom **hotbar**
- Right-click a hotbar slot (with inventory open) to stash it back
- Select a hotbar slot, then LMB to use (grenades throw + explode)

Grenade pickups in the world **respawn after 4 seconds**.

## World

- Tall platform trail (~32m), spiral climb tower, sky bridge
- Gold ledges support auto-vault while jumping up
- Physics toys: Jenga tower, cube pile, ball pit, bowling/kegel set
- Five procedurally animated enemies roam the ground: human, imp, centaur, spider, centipede

## Procedural animation

Enemies have **no keyframed or sine-wave animation**. Bodies are described by a
`ProcBodyPlan` resource (spine segments, legs, arms, head, tail — any counts),
built into a skeleton at runtime and driven entirely by simulation:

- **Legs** track the ground: feet stay planted in world space and take real,
  raycast-placed steps when they drift too far from home. A gait rule (neighbor
  feet can't swing together) makes bipeds alternate, quadrupeds trot, and
  spiders/centipedes ripple — emergently, per body form.
- **Per-joint settings**: every joint has a role and preferences — preferred
  rest angle, stiffness/lag (tail and rear segments follow through), knee bend
  direction, rotation limits.
- **Head** looks at the player within neck limits; when the neck strains past
  comfort the torso turns (stepping with its legs) until the head relaxes.
- **Hands** aim at the target and strike with windup → hit → recover curves.
- Body height/pitch/roll come from the planted feet; acceleration lean, yaw
  banking, landing bounces, and noise-based idle sway add life.

Add a new body form in `scripts/anim/proc_body_plan.gd` (see the five presets)
and pass its name as the enemy's `body_form`.

## Layout

```
scripts/player.gd           Movement + vault + throw
scripts/inventory.gd        Autoload bag + hotbar
scripts/inventory_ui.gd     Hotbar / drag-drop UI
scripts/world_pickup.gd     Collectibles
scripts/grenade_projectile.gd
scripts/world_builder.gd    Procedural level + toys
scripts/enemy.gd            Enemy AI (chase / attack / gravity)
scripts/anim/proc_body_plan.gd     Body form definitions (5 presets)
scripts/anim/proc_body_builder.gd  Runtime skeleton + visuals generator
scripts/anim/proc_animator.gd      Gait, spine, head, arms, tail solver
scripts/anim/proc_leg.gd           Planted-foot stepping state
scripts/anim/proc_ik.gd            Two-bone IK + rotation helpers
```
