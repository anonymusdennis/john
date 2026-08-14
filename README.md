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

## Layout

```
scripts/player.gd           Movement + vault + throw
scripts/inventory.gd        Autoload bag + hotbar
scripts/inventory_ui.gd     Hotbar / drag-drop UI
scripts/world_pickup.gd     Collectibles
scripts/grenade_projectile.gd
scripts/world_builder.gd    Procedural level + toys
```
