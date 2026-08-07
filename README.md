# John

3D platformer template for **Godot 4.7** — movement, jump, sprint, crouch, and automatic ledge vaulting.

## Requirements

- [Godot 4.7+](https://godotengine.org/) (Flatpak: `org.godotengine.Godot`)

## Run

```bash
# Flatpak
flatpak run org.godotengine.Godot --path /path/to/john

# Or open the project folder in the Godot editor and press F5
```

## Controls

| Action | Keyboard | Gamepad |
|--------|----------|---------|
| Move | WASD | Left stick |
| Look | Mouse | Right stick |
| Jump | Space | A / Cross |
| Sprint | Shift | RB / R1 |
| Crouch | Ctrl | B / Circle |
| Free mouse | Esc | — |

## Features

- Third-person camera with spring arm collision
- Walk / sprint / crouch speeds
- Coyote time + jump buffering
- Variable jump height (release jump early for a short hop)
- **Auto-vault** while moving **up** into a grabbable ledge (never while falling)
- Demo level with gold vault ledges, stairs, and gap platforms

## Vaulting

Vault triggers when all of these are true:

1. Character is airborne
2. Vertical velocity is upward (jumping / ascending)
3. A wall/ledge is detected ahead within reach
4. The ledge top is within min/max vault height
5. There is clearance above the landing spot

Mark ledges as grabbable by either:

- Adding the body to the `grabbable` group, or
- Attaching `scripts/grabbable_ledge.gd` (sets group + physics layer)

Untagged world geometry can still vault if the face is vertical and a flat top is found.

## Project layout

```
scenes/main.tscn      Demo level + HUD
scenes/player.tscn    Player pawn
scripts/player.gd     Controller (move / jump / vault)
scripts/grabbable_ledge.gd
```

Tune vault distances, speeds, and jump feel on the Player node export groups.
