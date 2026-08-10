# Godot FPS (4.7)

Godot 4.7 first-person shooter with a procedural dungeon, AKS-74U viewmodel, and Mixamo-animated police enemies.

## Enemy weapon orientation tuner

To align the enemy handgun without guessing numbers:

1. In Godot: **Project → Run Specific Scene** (or open `scenes/weapon_tuner.tscn` and press **F6**)
2. Orbit with the mouse, use sliders for position / rotation / size
3. Preview animations with keys **1–5** (walk / pistol / shoot / run / die)
4. Press **S** to save → `resources/enemy_weapon_pose.tres` (the game loads this automatically)
5. Press **C** to copy values to the clipboard

Then run the main game as usual to verify.

## Clone & open

```bash
git clone <your-repo-url>
```

Open the folder in **Godot 4.7** (Forward+), wait for asset import, press **F5**.

Or run without the editor (after export):

```text
export_release.bat   → build/GodotFPS.exe
run_game.bat         → play via Godot binary
```

## Features

First-person shooter built in **Godot 4.7** with:

- **Procedural dungeon** (multi-room BSP-style layout, PBR materials, pillars, doors, props, local lights)
- **AKS-74U viewmodel** (`assets/guns/animated_aks-74u.glb`) using the camera-local transform tuned in the three.js prototype
- **Police enemies** (`police-compressed-basetoolbox.com.glb`) with cleverly combined FBX clips:
  - `Walking.fbx` / `Running.fbx` for chase
  - `Pistol Walk.fbx` for combat movement
  - `Shooting.fbx` for attacks
  - `Dying.fbx` for death
- **Poly Haven** 1K textures (brick, concrete, metal, wood) + procedural fallbacks
- Hitscan combat, doors (E), pickups, mag/reserve ammo, HUD, pause / death UI

## Run

1. Install [Godot 4.7](https://godotengine.org/download) (Forward+).
2. Open the project folder `GodotFPS` in the Project Manager.
3. Wait for first-time import of `.glb` / `.fbx` assets.
4. Press **F5** (or Play).

## Controls

| Action | Key |
|--------|-----|
| Move | WASD |
| Sprint | Shift |
| Look | Mouse |
| Shoot | LMB |
| Reload | R |
| Open door | E |
| Pause | Esc |

## Viewmodel transform (from three.js)

```
position = (-0.260, -0.001, 0.078)
scale    = 3.23568
```

Defined in `scripts/weapon.gd` as `GUN_POS` / `GUN_SCALE`.

## Notes

- **Godot 4.7** is at `C:\Temp\Godot\Godot_v4.7-stable_win64.exe` on this machine.
- Police mesh is `police.glb` (Draco-decompressed from the Base Toolbox export; stock Godot cannot load `KHR_draco_mesh_compression`).
- Animations were converted FBX→GLB with FBX2glTF (`Walking.glb`, `Running.glb`, `PistolWalk.glb`, `Shooting.glb`, `Dying.glb`) and retargeted at runtime onto the police Mixamo skeleton (`mixamorig:Hips` → `mixamorigHips`).
- Level seed: set `Level.seed_value` on the Level node (0 = random each run).
- Viewmodel transform matches the three.js prototype (`scripts/weapon.gd`).
