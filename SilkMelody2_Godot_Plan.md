# SilkMelody 2: Unity → Godot Core-Mechanic Migration Plan

> **Audience:** a Sonnet implementation agent working phase by phase. Opus wrote this plan after reading the local Unity project in full.
> **Rule #1:** the Unity code is the **spec**. Every number below was read from the C# scripts, prefabs, `.anim` files or ProjectSettings. If something here looks wrong, re-read the Unity file named next to it before changing anything. Don't invent values.

| | Path |
|---|---|
| Unity source (read-only, never edit) | `D:\UnityProjects\SilkMelody` (Unity 2021.1, URP 2D) |
| Godot project (target) | `D:\GodotProjects\silk-melody-ocean` (Godot **4.7**, GL Compatibility) |
| Godot editor binary | `D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe` (standard build, **no .NET**) |

---

## 0. Decisions (fixed, don't revisit)

1. **Language: GDScript.** The installed Godot is the non-.NET build, and the GL Compatibility renderer means a web export stays possible. Use static typing everywhere (`var x: float`, `func f() -> void`).
2. **Unit conversion: 1 Unity unit = 16 px.** The tileset is 16 px per tile at PPU 16, so one tile = one Unity unit = 16 px. Character sprites are PPU 64 (128 px frames = 2 units), so **scale character, enemy and VFX sprites by 0.25**.
3. **Y axis flips.** Unity +y is up; Godot +y is down. Every Unity y-offset, velocity and impulse gets negated. All px values in this doc are **already converted to Godot space** unless marked "Unity:".
4. **Persistent world scene.** Unity keeps Player, GameMaster, LevelLoader and camera alive with `DontDestroyOnLoad`. In Godot, use one persistent `World.tscn` (Player, Camera, HUD, Fader) and swap rooms under a `RoomContainer` node. Don't use `change_scene_to_file` for rooms.
5. **Player = flag/lock model, not a big FSM.** `Player.cs` uses independent flags (`isDashing`, `inAttack`, `inSilkSkill`, `isParrying`, `disableControlCounter`, …) plus an animation-state enum. Mirror that structure 1:1 so behaviour matches exactly. A refactor into a formal FSM can come later, once behaviour parity is confirmed.
6. **Physics: bodies are `CharacterBody2D`, not `RigidBody2D`.** Simulate Unity's rigidbody behaviour by hand: gravity, linear drag, and impulses (`velocity += impulse / mass`; every mass is 1). This gives exact control over feel.
7. **Unity linear drag formula** (apply each physics tick to the whole velocity, after gravity): `velocity *= 1.0 / (1.0 + drag * delta)`.
8. **Animation events → `AnimationPlayer` method-call tracks** at the exact times listed below. Sprites use `Sprite2D` with `hframes` and a frame track in the same `AnimationPlayer`.
9. **Time freeze (hit-stop)** via an autoload `Hitstop` that sets `Engine.time_scale` and waits with `get_tree().create_timer(t, true, false, true)` (the 4th arg `ignore_time_scale = true`). Equivalent to Unity's `WaitForSecondsRealtime`.

---

## 1. Scope

### In scope (the "core mechanic")
- Player: run, variable jump, coyote time, ledge grab, dash, slash (forward/up), pogo (down-air), parry + riposte, damage, i-frames, stun, knockback, death, silk meter, three silk skills (Heal, Gossamer, Silk Burst), status effects (paralyzed, slowed, drained).
- Combat feedback: hit-stop, camera shake, sprite flash, hurt vignette (simple), sounds.
- Enemy base (`Enemy.cs`) + Crawling, Dipsa (+ bullet / `Projectile.cs`), Crabber. Copper-shard loot.
- Camera follow, room limits, shake, zoom trigger.
- Rooms DirtCave0–3 (converted from Unity YAML), room transitions, rest chair (checkpoint + save), death → respawn.
- HUD: health masks (+ blue lifeblood masks), silk bar, copper-shard counter.
- Save/load to JSON.

### Out of scope (don't port now)
Inventory/journal/map/shop UI, talismans and red/blue/yellow tools (the `UseRedTool`/`SwapTool` code paths: leave `tool_cooldown` in the data but no behaviour), NPCs/dialogue, bosses (BossBatter, GreatCrawler), LapisLazer, TwistedDipsa, Shockwave, DoorSwitch, MaskUpgrade, SilkbindSandal, main menu, pause menu, URP shaders/post-processing, A* Pathfinding library, Mossy rooms, DirtCave4–15.

The `DashAttack` input action has **no binding** in `InputMaster.inputactions`, so the standalone dash-attack is unreachable in the original. Still implement `_do_dash(also_attack=true)` because pogo and the riposte use it, but add no input for it.

---

## 2. Target Godot layout

```
res://
  project.godot
  assets/
    player/        ← copy of Unity Assets/Player/Sprite/*.png
    enemies/       ← Crawling.png, NormalDipsa.png, Crabber.png, bullet sprite
    tiles/         ← sunnyland_tileset.png
    props/         ← RestChair.png, loot sprites
    ui/            ← MaskIcon.png, MaskEmptyIcon.png, SilkBar.png, SilkThread.png
    sfx/           ← Assets/Audio/SFX/* needed (list in §9)
  autoload/
    game_state.gd  ← GameMaster + PlayerData + WorldData + SaveSystem
    hitstop.gd
    room_loader.gd ← LevelLoader
  resources/
    player_stats.gd   (class_name PlayerStats extends Resource)  – tuning defaults
  scenes/
    world/world.tscn, world.gd          (persistent root; main scene)
    player/player.tscn, player.gd, player_slash.tscn, player_slash.gd,
           gossamer.tscn, gossamer.gd, silk_burst.tscn, silk_burst.gd, player_sfx.gd
    camera/game_camera.gd, zoom_trigger.gd
    enemies/enemy.gd (base), crawling.tscn/.gd, dipsa.tscn/.gd, crabber.tscn/.gd,
            projectile.tscn/.gd (Dipsa bullet)
    loot/loot.tscn, loot.gd
    interactables/rest_chair.tscn/.gd, room_exit.tscn/.gd (ChangeLevelTrigger)
    ui/hud.tscn, hud.gd, fader.tscn
    rooms/dirt_cave_0.tscn … dirt_cave_3.tscn, sunnyland_tileset.tres
  tools/
    unity_room_converter.py
```

Main scene = `res://scenes/world/world.tscn`.

---

## 3. Project settings (Phase 0)

**Display:** viewport `384×216`, window override `1536×864`, stretch mode `canvas_items` (already set), aspect `expand`. Default texture filter **Nearest** (`rendering/textures/canvas_textures/default_texture_filter = 0`). Unity camera orthographic size 6 means 12 units = 192 px tall, so set `Camera2D.zoom = Vector2(216/192, 216/192) = 1.125` to match the original framing.

**Physics:** remove the stray `3d/physics_engine="Jolt Physics"` line (harmless, but this is a 2D game). Keep the default 60 physics ticks; all formulas below are delta-based.

**2D physics layer names** (Godot layers are 1-based):

| # | Name | Unity layer | Used by |
|---|---|---|---|
| 1 | Ground | Ground (6) | TileMapLayer "Tilemap" collision |
| 2 | Player | Player (7) | Player body |
| 3 | Enemy | Enemy (8) | Enemy bodies + enemy contact-hitbox Areas |
| 4 | PlayerAttack | PlayerAttack (9) | Slash / Gossamer / SilkBurst Areas |
| 5 | EnemyAttack | EnemyAttack (10) | Bullets, enemy slashes |
| 6 | Loot | Loot (11) | Loot bodies |
| 7 | DeadEnemy | DeadEnemy (12) | Dead enemy bodies |
| 8 | PlayerTrigger | PlayerTrigger (13) | Player's pickup/interact Area |

Collision rules (decoded from Unity's `m_LayerCollisionMatrix`, adapted for CharacterBody2D):
- Player body mask: Ground only. (In Unity the player physically bumped enemies, but contact damage + knockback dominated. Here, contact damage comes from a **Hurtbox Area2D** instead, so bodies never push each other.)
- Player Hurtbox (Area2D, layer none, mask Enemy + EnemyAttack). Disable its monitoring during i-frames: this replaces Unity's `Physics2D.IgnoreLayerCollision(Player, Enemy/EnemyAttack)`.
- Enemy body mask: Ground. Dead enemy: layer DeadEnemy, mask Ground.
- PlayerAttack Areas: mask Enemy + EnemyAttack + Ground (Ground is needed so the dash/pogo slash can detect "touched ground").
- Bullets (EnemyAttack): CharacterBody2D, mask Ground; plus an Area2D that hits the player's Hurtbox.
- Loot: body mask Ground; pickup Area detects PlayerTrigger.

**Input map** (from `Assets/Player/InputMaster.inputactions`, Gameplay map):

| Action | Keyboard | Gamepad |
|---|---|---|
| `move_left/right/up/down` | Arrow keys | Left stick + D-pad |
| `jump` | X | A (south) |
| `attack` | C | X (west) |
| `dash` | Z | Right trigger |
| `silk_skill` | Q | B (east) |
| `parry` | F | Y (north) |
| `pause` | Esc | Back/Select |

Read movement as `Input.get_vector("move_left","move_right","move_up","move_down")`. **Godot "up" is negative y**, so `ver_input = -v.y` (positive = up, like Unity). Thresholds: `ver_input >= 0.1` = up, `<= -0.1` = down.

**Autoloads:** `GameState` (`autoload/game_state.gd`), `Hitstop`, `RoomLoader`.

---

## 4. Data (`GameState`): port of `PlayerData.cs` / `WorldData.cs` / `GameMaster.cs` / `SaveSystem.cs`

`GameMaster.InitNewGameData()` creates `new PlayerData()`, so the **C# field defaults** are the live values. The prefab's `damage: 1` is overwritten and doesn't apply.

```
PlayerData (runtime, saved)                Unity value  →  Godot
max_hp                 5
current_hp             5
lifeblood_hp           0      (blue bonus masks, absorb damage first)
current_silk           0
max_silk               8
silk_heal              3
damage                 4
move_speed             7 u/s       → 112 px/s
jump_force             12 u/s      → 192 px/s (upwards = -192)
dash_force             20 u/s      → 320 px/s
max_dash               1
extra_jump             0
dash_time              0.25 s
enemy_knockback_power  5           → 80 px/s impulse
attack_cooldown        0.15 s
parry_window           0.25 s
parry_cooldown         1.0 s
tool_cooldown          0.35 s (unused for now)
stun_time              0.4 s
i_frame_time           1.5 s
respawn_scene          "DirtCave0"
respawn_chair_name     ""
respawn_pos            Vector2.ZERO
copper_shard           0
scale_shard            0
WorldData: visited_rooms: Array[String], enemy_kill_count: Dictionary(enemy_type → int)
```

Player-prefab-only tuning (from `Tenroh.prefab`, not PlayerData; put these in `PlayerStats` resource or as `@export`s):

| Field | Unity | Godot |
|---|---|---|
| gravityScale | 5 × 9.81 = 49.05 u/s² | **784.8 px/s²** |
| linearDrag | 2 | drag 2 (formula §0.7) |
| maxJumpTime | **0.3 s** (prefab overrides the 0.5 code default) | 0.3 s |
| coyoteTime | 0.2 s | 0.2 s |
| dashRecoil | (0, 25) | (0, **-400**) px/s |
| body collider | size 0.802×1.435, offset (0, -0.170) | RectangleShape 12.8×23.0, offset (0, +2.7) |
| groundCheck | box at (0, -0.889), size (body.x − 0.05, 0.1) | use `is_on_floor()`; optionally a ShapeCast 12×1.6 at (0, 14.2) |
| ledge **green** box | offset (0.5·facing, 0), size 0.2×0.1 | (8·facing, 0), 3.2×1.6 px |
| ledge **red** box | offset (0.5·facing, 0.5), size 0.2×0.1 | (8·facing, **-8**), 3.2×1.6 px |
| DashAttackPos | (1, -0.3) | (16, 4.8) |
| PogoAttackPos | (0.27, -0.47) | (4.3, 7.5) |
| footstepFrequency | 0.5 s | 0.5 s |

Expected feel, for sanity checks: run 7 tiles/s; terminal fall ≈ 25 tiles/s (from drag); full-hold jump ≈ 5 tiles high; dash ≈ 4 tiles.

**Save system** (`SaveSystem.cs`): `user://player.json` and `user://world.json`, written with `JSON.stringify(dict, "\t")`. `save()` serialises PlayerData and WorldData; `load()` overwrites fields that exist in the file; also add `delete_save()` and `save_exists()`. Store Vector2 as `[x, y]`.

---

## 5. Player (`Player.cs`, 1,045 lines). Port faithfully.

### 5.1 Per-frame order (`Update`)
Run in `_physics_process(delta)` in this exact order:
1. `_check_grounded()` (`is_on_floor()` from the previous `move_and_slide`)
2. `if not in_attack: attack_timer += delta`; `if not is_parrying: parry_timer += delta`
3. If `not resting and control_lock == 0 and not is_dashing and not is_paralyzed and not in_silk_skill and not is_parrying and not in_menu`, run in order: `handle_movement`, `handle_jump`, `handle_attack`, `handle_parry`, `handle_dash`, `handle_ledge_grab` (if `can_ledge_grab`), `handle_coyote_time`, `handle_silk_skill`.
4. `_animation_control()`
5. `_landing_dust()`: if airborne `air_time += delta`, else { if `air_time > 0.2`: dust + landing sfx; `air_time = 0`; refill `dash_count = max_dash`, `jump_count = extra_jump` }
6. Physics integration: `if gravity_on: velocity.y += 784.8 * delta`; apply drag 2; `move_and_slide()`.

Use a `gravity_on: bool` flag in place of Unity's `rb.gravityScale = 0 / original`. Use an `is_kinematic: bool` flag (sitting on a chair, dead) that skips step 6.

**Input edge detection** must match Unity's `WasPressedThisFrame`/`WasReleasedThisFrame`: use `Input.is_action_just_pressed/just_released` inside `_physics_process`. That's reliable in Godot 4 when physics-interpolation and agile input are off; if presses get dropped, buffer them in `_unhandled_input` and consume them in physics.

### 5.2 Movement
- `velocity.x = hor_input * 112 * (0.5 if is_slowed else 1.0)` (overwrites x every frame while controllable).
- Facing changes only when `not in_attack`. Flip with `$Visual.scale.x = -1/1` (a child node holding the sprite, slash spawn points and ledge probes). **Don't flip the CharacterBody2D's own scale.** When facing changes while grounded, play dust.

### 5.3 Jump (`HandleJump`)
- On press: if `is_grounded or is_ledge_grabbing or coyote_air_timer <= 0.2` → `jump()`; elif `jump_count > 0` → `jump(); jump_count -= 1`.
- `jump()`: `jump_timer = 0.3; is_jumping = true; velocity.y = -192; coyote_air_timer = 0.2 + 1.0` (prevents a coyote double jump), jump sfx, dust.
- While held and `is_jumping`: if `jump_timer > 0`: `velocity.y = -192; jump_timer -= delta`, else `is_jumping = false`.
- On release while `is_jumping`: `jump_timer = 0; is_jumping = false; velocity.y = 0` (hard cut); `coyote_air_timer = 1.2`.

### 5.4 Coyote time
If `not is_grounded and not is_ledge_grabbing`: `coyote_air_timer += delta`, else `= 0`.

### 5.5 Ledge grab (`HandleLedgeGrab`)
Skip if dashing. Two small probes (Area2D or `PhysicsDirectSpaceState2D.intersect_shape`, mask Ground) at the green and red offsets above, mirrored by facing.
`is_ledge_grabbing = green and not red and not is_jumping and not is_grounded`.
While grabbing: `velocity = ZERO; gravity_on = false; refill dash & jumps`. Otherwise `gravity_on = true`. **Note:** that else-branch restores gravity every frame the player is controllable. That's intended Unity behaviour; keep it.

### 5.6 Dash (`HandleDash`, `Dash` coroutine)
On press, `if not is_dashing and dash_count > 0`: `dash_count -= 1`, dust, then start the dash with direction `(facing, 0)`.
`_do_dash(also_attack, dir)`: cancel any running dash; dash sfx; `is_dashing = true`; if `also_attack`: `in_attack = true`; `gravity_on = false; velocity = ZERO; velocity += dir * 320` (**dir is not normalized**: pogo uses `(±1, +1)` in Godot space, i.e. 320 px/s on both axes). Wait `dash_time` (0.25 s). Then `is_dashing = false; gravity_on = true`; if `also_attack`: `in_attack = false`, clear the dashAttack/pogo anim flags.
Drag (2) still applies during the dash, so speed decays: that's the original feel.
Implement it as a cancellable coroutine: keep a `_dash_id: int` counter and check it after `await`, or use a Timer node. Several code paths "StopCoroutine(dashCoroutine)".

### 5.7 Attack (`HandleAttack`)
Fires when `attack just pressed and attack_timer > 0.15 and not in_attack`:
- `ver_input >= 0.1` → play `attack_up`, spawn slash **up**: local pos (0, -8), rotation -90°.
- `ver_input <= -0.1 and not is_grounded` → **pogo** (§5.8).
- else → play `attack`, spawn slash **forward**: local pos (16, 0) (mirrored by facing).
- attack sfx, `attack_timer = 0`.
`in_attack` is set by animation events: `attack`/`attack_up` clips are 0.2167 s long with `begin_attack_anim` at 0.0 s and `end_attack_anim` at 0.2 s. The cooldown counts only while not in an attack, so the effective re-attack interval is 0.2 + 0.15 s.
The normal slash's `knockback_power = enemy_knockback_power` (80 px/s). It has **no self-recoil**.

### 5.8 Pogo (`PogoAttack`)
Dust; `_do_dash(true, Vector2(facing, 1))`; set the pogo anim flag; spawn the **pogo slash** at PogoAttackPos (child of Visual, so it follows the player) with lifetime `dash_time`.

### 5.9 Slashes (`PlayerSlash.cs` + prefabs)
One scene `player_slash.tscn` (Area2D, layer PlayerAttack) with exports:

| Variant | Collider (Godot px) | knockback | has_recoil | can_reset_dash | is_dash_attack | hitbox lifetime |
|---|---|---|---|---|---|---|
| Slash (normal/up) | Rect 37.7×26.0, offset (8.3, 1.6) | 80 (set from stats) | false | false | false | 0.15 s |
| DashSlash (riposte) | Rect 25.9×11.6, offset (-0.4, -1.6) | 16 | true | false | true | `dash_time` |
| PogoSlash | Polygon from `PogoSlashPrefab.prefab` `m_Points` (×16, y negated); fallback circle r≈10 | 16 | true | **true** | true | `dash_time` |

Behaviour:
- Hitbox is active until `timer >= lifetime` **or** `impacted`; then disable the shape (deferred).
- Visual fade: alpha drops by `fade_speed * delta`, `fade_speed += fade_accel * delta` (normal slash accel 100, dash/pogo 10). Free the node 1 s after alpha reaches 0.
- On `area_entered`/`body_entered` with an **Enemy** (also check the parent, like the Unity failsafe):
  - if not `impacted`: `impacted = true`; if `has_recoil and not piercing`: `player.attack_recoil(can_reset_dash)`.
  - `enemy.damaged(GameState.damage, (enemy.pos - player.pos).normalized() * knockback)`.
  - spawn slash spark + particles at the enemy; `current_silk = min(current_silk + 1, max_silk)` **per enemy hit**.
- On a **Projectile** on EnemyAttack with `melee_hittable`: same impact handling, `projectile.damaged(...)`.
- On **Ground** and `is_dash_attack`: `player.dash_attack_touch_ground()`; if not piercing, `impacted = true`.

`attack_recoil(reset_dash)`: cancel dash; `is_dashing = false; gravity_on = true; in_attack = false`; clear anim flags; `velocity = ZERO; velocity += Vector2(0, -400)`; if `reset_dash`, refill dash & jumps.
`dash_attack_touch_ground()`: same minus the recoil and the refill (`velocity = ZERO`).

### 5.10 Parry & riposte
- `handle_parry`: on press, `if not in_attack and is_grounded and parry_timer >= 1.0`: `parry_timer = 0; velocity = ZERO`; start `_parrying()`: `is_parrying = true`, anim parry state 1, wait 0.25 s, state 0, `is_parrying = false`. (Parrying blocks all control, §5.1.)
- If `damaged()` is called while `is_parrying`: cancel `_parrying` and run `_parry_riposte()`, **taking no damage**:
  1. anim state 2 (ParryReceived), parry sfx, `Hitstop.freeze(0.35)` (time scale 0 for 0.35 s real).
  2. Start i-frames (hurtbox off).
  3. attack sfx, anim state 3 (ParryRipose); spawn a DashSlash at DashAttackPos with `has_recoil = false, piercing = true, lifetime = dash_time`; dust; `is_dashing = true; in_attack = true; gravity_on = false; velocity = (facing * 320 * 1.5, 0)`.
  4. Wait `dash_time`, then `is_dashing = in_attack = is_parrying = false; gravity_on = true`; anim state 0.
  5. Wait 0.1 s, then end i-frames.
  6. `parry_timer = parry_cooldown`, so the next parry is available immediately.
- `inflicted_status_effect()` is ignored while parrying.

### 5.11 Taking damage (`Damaged(amount, knockbackDir)`)
1. Return if `in_i_frame or is_dead`. If `is_parrying` → riposte (above), return.
2. Free any active Gossamer / SilkBurst instance.
3. Damaged sfx. Lifeblood absorbs first: if `amount <= lifeblood_hp`, take it from lifeblood and set amount to 0; else `amount -= lifeblood_hp; lifeblood_hp = 0`. Then `current_hp = clamp(current_hp - amount, 0, max_hp)`.
4. Reset states: `gravity_on = true`; `is_dashing = in_attack = is_paralyzed = in_silk_skill = is_parrying = false`; restore sprite material; clear dashAttack/pogo flags. Also cancel the running dash/parry coroutines and stop the AnimationPlayer's current one-shot, so later method-call events (e.g. `end_heal`) don't fire.
5. Hurt vignette pulse (§8), `camera.shake(intensity, 0.3, unscaled=true)`, hurt spark (random rotation ±15°) and hurt particles.
6. If `current_hp <= 0` → `_death()`. Else, in parallel: `Hitstop.freeze(0.35 * original_amount)`; `_i_frame()`; `_stunned()`; then `velocity += knockback_dir * 80 + Vector2(0, -80)`.
   - The order matters: `_stunned()` zeroes velocity **before** the knockback impulse is added (in Unity, the coroutine runs synchronously up to its first yield).
- `_i_frame()`: `in_i_frame = true`, hurtbox monitoring off, sprite alpha 0.5; wait 1.5 s; restore.
- `_stunned()`: `is_hurt = true; control_lock += 1; velocity = ZERO`; wait 0.4 s; `control_lock -= 1; is_hurt = false`.
- Contact damage: when the Hurtbox overlaps an Enemy contact area and `not enemy.no_contact_damage` → `damaged(1, (player.pos - enemy.pos).normalized())`. Unity only fired on collision *enter*. In Godot, also re-check overlaps when i-frames end (`get_overlapping_areas()`), otherwise standing inside an enemy never hurts again.
- `_death()`: `is_dead = true; control_lock += 1; is_kinematic = true; velocity = ZERO`; `RoomLoader.respawn()`; wait `transition_time` (1 s); `is_dead = false; current_hp = max_hp; control_lock -= 1`.

### 5.12 Status effects (`InflictedStatusEffect`, used by projectiles)
Enum `NONE, PARALYZED, SLOWED, DRAINED`. Paralyzed: `velocity = ZERO; is_paralyzed = true` for 1 s. Slowed: `is_slowed = true` for 2 s (×0.5 move speed). Drained: `current_silk -= 2` (clamp ≥ 0).

### 5.13 Silk skills (`HandleSilkSkill` + anim events)
On `silk_skill` press while `not in_attack` (works in the air too); the cost is paid **at press**:
- `ver_input >= 0.1` and silk ≥ 6 → cost 6, play **gossamer**.
- `ver_input <= -0.1` and silk ≥ 4 → cost 4, play **silk_burst**.
- else silk ≥ 8 and `current_hp < max_hp` → cost 8, play **heal**.

Animation clips and method-call tracks (times in seconds, from the `.anim` files):

| Clip | Length | Events |
|---|---|---|
| `heal` (tenroh_heal, 2 frames) | 1.0167 | 0.0 `begin_heal` · 0.5833 `actual_heal` · 1.0 `end_heal` |
| `gossamer` (tenroh_gossamer, 2 frames) | 1.0167 | 0.0 `begin_gossamer` · 1.0 `end_heal` |
| `silk_burst` (tenroh_burst, 6 frames) | 0.9833 | 0.0 `begin_silk_burst` · 0.1667 `throw_silk_burst` · 0.8333 `catch_silk_burst_recoil` · 0.9667 `end_heal` |
| `attack`, `attack_up` (3 frames) | 0.2167 | 0.0 `begin_attack_anim` · 0.2 `end_attack_anim` |
| `hurt` | loop | 0.0 `end_attack_anim` |

- `begin_heal`: silkbind sfx; `in_silk_skill = true; velocity = ZERO; gravity_on = false`; spawn the SilkBind VFX at local (4, 0) (0.6 s, then free).
- `actual_heal`: `current_hp = min(current_hp + 3, max_hp)`; flash white 0.25 s.
- `end_heal`: `in_silk_skill = false; gravity_on = true`.
- `begin_gossamer`: same lock; spawn **Gossamer** as a child at local (4, 0).
  - Gossamer: every 0.1 s, query enemies in a **circle of radius 38.4 px** around its spawn point; for each one `damaged(3, dir * 0.16)` (knockback is negligible). It lives 0.75 s (VFX clip length), then frees itself.
- `begin_silk_burst`: lock (same as `begin_heal` without the VFX).
- `throw_silk_burst`: spawn **SilkBurst** as a child of Visual at local (64, 0); RectangleShape **128×32**; on enemy enter: `damaged(10, Vector2(dir.x * 240, -80))`. It lives 0.483 s, then frees itself.
- `catch_silk_burst_recoil`: `velocity += Vector2(-facing * 160, -32)`.

### 5.14 Animation state (`AnimationControl`)
Priority order: dead/hurt/paralyzed → `HURT`; dashing → `DASHING`; `velocity.y < -0.1*16` (rising) → `JUMPING`; `velocity.y > 1.6` → `FALLING`; `|velocity.x| > 1.6` → `RUNNING`; ledge grab → `LEDGE`; else `IDLE`. Loop clips: idle (3 frames, 0.5167 s), run (2 frames, 0.35 s), jump/fall/dash/hurt/ledge (1 frame). One-shot clips (attack, skills, parry states, dash-attack, pogo) override the state clip while they play.
Sprite sheets are horizontal strips of 128×128 frames; frame counts are in §9. For exact per-frame timing, read the `m_PPtrCurves` keyframes in `Assets/Player/Animation/*.anim`.

### 5.15 Misc
- `rest_chair_recovery()`: cancel all coroutines; `current_hp = max_hp`; `is_dashing = in_attack = false`; clear anim flags.
- Footsteps: every 0.5 s while grounded and in the RUNNING state.
- All SFX are played with volume `randf_range(0.8, 1.0)` (in dB: `linear_to_db`) and `pitch_scale = randf_range(0.7, 1.3)`.

---

## 6. Enemies

### 6.1 Base `enemy.gd` (`Enemy.cs`), `class_name Enemy extends CharacterBody2D`
Exports: `max_hp, damage, knockback_able = true, no_contact_damage = false, enemy_type, drop_amount, loot_scene, gravity_scale, drag, will_be_destroyed = false`.
Children: `Visual` (Sprite2D + AnimationPlayer, flipped for facing), `ContactArea` (Area2D, layer Enemy) for player contact damage, `LootPos`.
- Physics: `velocity.y += 157 * gravity_scale * delta` (Unity gravity 9.81 u/s² = 157 px/s²), then drag, then `move_and_slide()`.
- `damaged(amount, knockback)`:
  1. if `knockback_able`: `velocity = ZERO; velocity += knockback`; start `stop_moving()` (`should_stop_moving = true` for 0.25 s, restartable).
  2. if not `is_invulnerable`: invulnerable for **0.05 s**; damaged sfx (random volume/pitch); hit particles; white flash 0.15 s (shader with a `flash` uniform); `current_hp -= amount`; if `<= 0` → `death()`.
- `death()`: `GameState.world.enemy_kill_count[type] += 1`; disable ContactArea; modulate (0.3, 0.3, 0.3); flip the sprite vertically (`Visual.scale.y = -1`); collision layer → DeadEnemy; stop the AnimationPlayer; gravity_scale 1, drag 1; `is_dead = true`; spawn `drop_amount` loot at LootPos, each with velocity `(randf_range(-80, 80), randf_range(-160, -80))`; `Hitstop.slow(0.2, 0.2)` (time scale 0.2 for 0.2 s real); free after 10 s. AI scripts must check `is_dead` and stop.
- A `should_stop_moving` flag that AI movement respects.

### 6.2 Crawling (`CrawlingAI.cs`, prefab `Crawling.prefab`)
hp 8, type 0, drop 3, gravity_scale 1, drag 1, body Rect 18.1×10.5. Sprite faces **left** by default.
- Patrol speed 3 u/s → **48 px/s**. `CheckObstaclePos` at local (-12.4 px · dir), where dir = -1 for moving left (mirror it).
- Each physics tick: `near_fall` = a raycast down 16 px from the probe hits nothing (mask Ground); `near_wall` = a point/circle (r 1.6 px) at the probe overlaps Ground.
- `stabilized` becomes true once neither is true. If stabilized and (near_fall or near_wall): `stabilized = false`, then turn around (`velocity = ZERO`, flip dir & visual).
- If stabilized and not `should_stop_moving`: `velocity.x = lerp(velocity.x, dir * 48, 1 - pow(0.9, delta / 0.02))` (Unity lerps by 0.1 per 0.02 s fixed step).

### 6.3 Dipsa (`DipsaAI.cs` + `RbPathfindAI.cs`), flying shooter
hp 8, type 1, drop 5, gravity_scale **0**, drag 1.5, body Circle r 8 px.
- Idle until the player is within **160 px** (detection radius 10 u); then `alerted = true` permanently.
- Alerted: `should_stop_moving = dist <= 160`. When not stopped, steer toward the player: `velocity += dir * 80 * delta` (acceleration 5 u/s² = 80 px/s²; drag gives ~53 px/s top speed). No pathfinding for now; a direct line is fine for the test rooms. Optional later: `NavigationAgent2D`.
- Every 3 s, if within 160 px: start `stop_moving()`, then spawn a bullet at ShootPos (-3.8, 12.8) with velocity `dir_to_player * 80`.
- Flip the sprite toward the movement direction (sprite faces left by default).

### 6.4 Dipsa bullet (`Projectile.cs`, `NormalDipsaBullet.prefab`)
Layer EnemyAttack, Circle r 1.6 px, no gravity, no drag, damage 1, durability 1, `max_bounce` 0, `melee_hittable` false, `inflict_status` NONE.
- On hitting the player: `player.damaged(1, dir)`, then `player.inflicted_status_effect(status)`; then die.
- On hitting Ground: `bounce_counter += 1`; `if bounce_counter > max_bounce` → die.
- Die = disable collision, gravity on (scale 1), fade alpha at 10/s, free. Hard lifetime 10 s.
- `damaged()` (only if `melee_hittable`): knockback, flash, durability −= amount, die at ≤ 0.

### 6.5 Crabber (`CrabberAI.cs`), ground charger
hp 12, type 3, drop 4, gravity_scale 1, drag 1, body Rect 17.8×10.2.
- Detection **96 px** (6 u); attack radius **48 px** (3 u); `time_between_attack` 3 s.
- Alerted: unless `in_attack`, `should_stop_moving = dist <= 48`; when moving, walk horizontally toward the player. The Unity A* force (400 × fixedDt) fought tile friction. **Target ≈ 64 px/s and tune by eye.** Every 3 s, if within 48 px, play `attack`.
- `attack` clip (1.35 s) events: 0.0 `begin_attack` (`in_attack = true; should_stop_moving = true`) · 0.3333 `dash_forward` · 1.0 `dash_forward` · 1.3333 `end_attack`.
- `dash_forward`: `velocity.x += sign_to_player * 96` (Unity: `AddForce(dir*300)`, one fixed step = Δv 6 u/s).

### 6.6 Loot (`Loot.cs`, `CopperShardSmall.prefab`)
CharacterBody2D on layer Loot, gravity_scale 2, drag 1, body Rect 5.8×6.9. Pickup Area detects PlayerTrigger. Value 1 copper. Spin visual: `sprite.scale.x = sin(rand_phase + time * 5)`. Auto-free after 20 s. On pickup: add to `copper_shard`, hide, sfx, free after 1 s.

---

## 7. World systems

### 7.1 World scene (`world.tscn`)
```
World (Node2D, world.gd)
  RoomContainer (Node2D)
  Player (player.tscn)
  GameCamera (Camera2D, game_camera.gd)
  CanvasLayer HUD (hud.tscn)
  CanvasLayer Fader (ColorRect + AnimationPlayer: fade_out/fade_in)
  CanvasLayer Vignette (ColorRect with a radial shader, alpha param)
```
On start: load `GameState` (from the save, if it exists) and call `RoomLoader.start()`, which loads `respawn_scene` and places the player.

### 7.2 RoomLoader (`LevelLoader.cs` + `ChangeLevelTrigger.cs`)
- `transition_time = 1.0`.
- `load_level(room_name, spawn_name)`: `player.control_lock += 1; player.gravity_on = false`; fade out over 1 s; free the old room and instance `res://scenes/rooms/<snake_case(room_name)>.tscn` under RoomContainer; `GameState.add_visited_room(room_name)`; place the player at the `Marker2D` named `spawn_name` (in group `spawn_points`); `gravity_on = true`; update the camera limits; fade in; `control_lock = max(control_lock - 1, 0)`.
- `respawn()`: set `do_respawn = true`, then `load_level(respawn_scene, "")`. With `do_respawn` set: if `respawn_chair_name == ""` → place at `respawn_pos`, `is_kinematic = false`; else find the RestChair node by name, place the player there and call `chair.get_on_chair()`.
- First boot (`SpawnPointInit`): if no chair and `respawn_pos == ZERO`, use the room's `PlayerStart` marker as `respawn_pos`.
- `RoomExit` (Area2D, mask Player): exports `level_name`, `spawn_pos_name`; fires once on body enter.

### 7.3 Rest chair (`RestChair.cs` + `InRangeInteractable.cs`)
- Area2D trigger 43×23 px; an "Up to rest" label shows while the player is in range and not sitting.
- Sit when in range and `ver_input == 1` (fully up), not sitting and not in a menu: `player.resting = true`; `player.rest_chair_recovery()`; `velocity = ZERO`; `is_kinematic = true`; position = `SitSpot` marker; `GameState.respawn_chair_name = name; respawn_scene = current room`; hurtbox off (invulnerable); save sfx; `GameState.save()`; hide the label; soft white flash (alpha 100/255 decaying 0.3/s); show "Saving…" for 1 s.
- Stand when sitting and `ver_input == -1`: `resting = false; is_kinematic = false`; hurtbox on; show the label.
- While `resting`, the player gets no control (§5.1).

### 7.4 Camera (`CinemachineShake.cs`, CM vcam1 prefab, `ZoomCameraTrigger.cs`)
- Follows the player with smoothing (Cinemachine damping 1: `position_smoothing_speed ≈ 5`), drag margins 0.2 each side (Godot margins are fractions of the half-screen from centre; Unity dead zone 0.2 of screen), look-ahead 0.5 s (optional: offset toward velocity.x).
- Limits come from the room's collision `TileMapLayer.get_used_rect()` × 16, set on every room load.
- `shake(intensity, time, unscaled)`: random offset with amplitude ∝ intensity (start at `intensity * 1.2` px for intensity 5 ≈ 6 px, tune), decaying linearly to 0 over `time`. If `unscaled`, tick with real time (`Time.get_ticks_msec`) so it runs during hit-stop. Set `process_mode = PROCESS_MODE_ALWAYS`.
- Zoom trigger: Area2D with `target_size` (Unity ortho size) and `zoom_time`; on enter, tween `zoom` to `Vector2.ONE * 216.0 / (target_size * 32.0)` over `zoom_time`.

### 7.5 HUD (`HealthUI.cs`, `SilkBarUI.cs`, `ShardUI.cs`)
- Masks: one `TextureRect` per `max_hp` (MaskIcon when `i < current_hp`, else MaskEmptyIcon), then `lifeblood_hp` extra masks tinted (0, 0.75, 1). Rebuild when max_hp or lifeblood changes; refresh on current_hp change. Drive it from `GameState` signals (`stats_changed`) rather than polling.
- Silk bar: `max_silk` segments (SilkThread icon filled/empty).
- Copper-shard counter label.

### 7.6 Hurt vignette (`PPVolumeController.cs`)
On damage: vignette intensity 0.6, lerping back to the base value over 2 s. A ColorRect with a simple radial-darkening shader is enough.

---

## 8. DirtCave room converter (`tools/unity_room_converter.py`)

> **2026-11-26: all builder scripts and the room pipeline were deleted** (`tools/build_*.gd`, `tools/unity_room_converter.py`, `tools/room_data/`, `tools/room_previews/`, `tools/setup_project_settings.gd`). The committed `.tscn`/`.tres` files are now the source of truth and are edited in the Godot editor. References to builders below are historical; the deleted files are in git history (last present in commit 48f59f4).


Rooms to convert: **DirtCave0 ↔ DirtCave1 ↔ DirtCave2 ↔ DirtCave3**.

| Room | Tiles | Contents | Exits (levelName → spawnPosName) |
|---|---|---|---|
| DirtCave0 | 1,104 | start room, no enemies | → DirtCave1/Entry0 |
| DirtCave1 | 1,903 | Crawling, Dipsa | → DirtCave2/Entry0, → DirtCave0/Entry0 |
| DirtCave2 | 1,850 | Crawling, Dipsa, Crabber (hub) | → DirtCave3/Entry0, → DirtCave1/Entry1, → DirtCave14 ✗, → DirtCave4 ✗ |
| DirtCave3 | 677 | **RestChair** (dead end) | → DirtCave2/Entry1 |

Exits marked ✗ lead to unported rooms. Emit them as `RoomExit` nodes with `disabled = true` (or wall them off).

**Tileset facts:**
- Image `Assets/Misc/TilesetSprite/Sunnyland/artwork/Environment/sunnyland_tileset.png` is 400×368 px, sliced into 128 sprites of 16×16, PPU 16, point filter. Sprite pivots are center-aligned (`alignment: 0`), so tiles sit exactly on their cells.
- Sprite rect y is measured **from the bottom** in Unity. Godot atlas coord = `(x/16, (368 - y - h)/16)`.
- The `.png.meta` maps sprite `fileID` (213xxxxx) ↔ sprite name in `internalIDToNameTable`, and name ↔ rect in `spriteSheet.sprites`.

**Scene YAML facts** (example: `DirtCave3.unity`):
- A `Grid` (cell size 1) with three Tilemap children named **Background**, **Tilemap** (has `TilemapCollider2D` + `CompositeCollider2D`, so it is the collision layer) and **Foreground**.
- Each Tilemap component has `m_Tiles:` entries `- first: {x, y, z}` → `second: { m_TileSpriteIndex: N, m_TileMatrixIndex: M, ... }`, plus `m_TileSpriteArray:` (`- m_RefCount`, `m_Data: {fileID: 213xxxxx, guid: 261212b9…}`) and `m_TileMatrixArray` (check `e00`/`e11` for -1 = flipped tiles; none were found in DirtCave3, but handle a flip if present).
- Unity's YAML has custom tags (`--- !u!114 &123`). Don't use a YAML library: split on `\n--- !u!` and parse the needed blocks with regex/line scanning.
- Map a Unity tile at cell (x, y) to Godot cell **(x, -y - 1)**. Also add the Tilemap/Grid GameObject's `Transform.m_LocalPosition` offset (usually 0).

**Converter output:**
1. `scenes/rooms/sunnyland_tileset.tres`: one `TileSetAtlasSource` (16×16), with a full-square physics polygon on physics layer 0 (collision layer = Ground) for every tile.
2. Per room, `scenes/rooms/dirt_cave_N.tscn`: root `Node2D` named `DirtCaveN` with
   - `Background` (TileMapLayer, z -10, no collision), `Tilemap` (TileMapLayer, collision enabled), `Foreground` (TileMapLayer, z 10, collision disabled);
   - `Marker2D`s for every GameObject whose name starts with `Entry` (Unity position × 16, y negated), in group `spawn_points`;
   - `RoomExit` instances for every `ChangeLevelTrigger` (position + BoxCollider2D size/offset from the same GameObject; `levelName`, `spawnPosName` exports);
   - `PlayerStart` marker from the Tenroh prefab instance position (DirtCave0: Unity (0.22, 21.93));
   - enemy instances (Crawling / Dipsa / Crabber prefab instances, found by prefab GUID: read from each `.prefab.meta`) with their position overrides (`m_Modifications` → `m_LocalPosition.x/y`);
   - the RestChair instance (DirtCave3) with its GameObject name kept, since the respawn logic finds it by name.
   - Write the `TileMapLayer.tile_map_data` as a `PackedByteArray`, **or**, simpler and safer, write a tiny `@tool` GDScript that reads a JSON dump and calls `set_cell()` and is run headless. **Recommended:** Python dumps JSON (cells, markers, exits, enemies); a Godot `EditorScript`/headless script (`godot --headless -s tools/build_rooms.gd`) builds and saves the `.tscn` files with `PackedScene.pack()`. This avoids hand-encoding Godot's binary tile format.
3. Prefab instances in Unity scenes store positions as `m_Modifications` with `propertyPath: m_LocalPosition.x/y`. Plain GameObjects store `m_LocalPosition` in their Transform block. Handle both, plus parent transforms if a trigger is nested (resolve `m_Father` chains).

---

## 9. Assets to copy (from `D:\UnityProjects\SilkMelody\Assets`)

Copy only the `.png`/audio files, not `.meta`. Player strips are 128 px frames: idle 3, run 2, attack 3, attackUp 3, parry 3, heal 2, gossamer 2, burst 6, and single frames for jump, fall, dash, dashAttack, pogoAttack, hurt, grabLedge.

| Group | Source |
|---|---|
| Player | `Player/Sprite/tenroh_*.png`, `Slash.png`, `DashSlash.png`, `PogoSlash.png`, `SlashSpark.png` (4 frames), `HurtSpark.png`, `GossamerSilk.png` (10 frames of 512), `SilkBurst.png` (6 frames of 512×128), `SilkBind.png` (7 frames of 256) |
| UI | `Player/Sprite/MaskIcon.png`, `MaskEmptyIcon.png`, `SilkThread.png`, `SilkBar.png` |
| Enemies | `Enemy/Crawling/Crawling.png`, `Enemy/Dipsa/NormalDipsa.png`, `Enemy/Crabber/Crabber.png` (check the frame slicing in each `.png.meta`) |
| Props | `Interactable/RestChair/RestChair.png`, `Loot/Sprite/*` |
| Tiles | `Misc/TilesetSprite/Sunnyland/artwork/Environment/sunnyland_tileset.png` |
| SFX (`Audio/SFX/`) | `player_attack.ogg`, `player_damaged.ogg`, `parry.ogg`, `dash.ogg`, `silk_bind.ogg`, `jump.ogg`, `landing.ogg`, `footstep.mp3`, `hit_enemy.ogg`, `loot_pickup.ogg`, `save_sfx.ogg`, `gossamer.ogg`, `silk_burst.ogg` |

To check sprite slicing and PPU for a file, read its `.png.meta` (`spritePixelsToUnits`, `spriteSheet.sprites[].rect`).

---

## 10. Build phases for Sonnet

> **2026-11-26: all builder scripts and the room pipeline were deleted** (`tools/build_*.gd`, `tools/unity_room_converter.py`, `tools/room_data/`, `tools/room_previews/`, `tools/setup_project_settings.gd`). The committed `.tscn`/`.tres` files are now the source of truth and are edited in the Godot editor. References to builders below are historical; the deleted files are in git history (last present in commit 48f59f4).


Run **one phase per Sonnet session**. Each phase ends with:
- (a) a headless parse/run check: `"D:\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe" --headless --path D:\GodotProjects\silk-melody-ocean --import`, then `--headless --path … --quit-after 120` with **zero script errors** in the output;
- (b) a short note appended to §12 *Progress log* (what was done, deviations from this plan, open issues).

Don't start the next phase in the same session.

| # | Phase | Done when |
|---|---|---|
| P0 | Project settings (§3), folder layout (§2), autoloads (empty stubs + `GameState` data + save/load), copy assets (§9). Set up a git repo with a Godot `.gitignore`. | Project opens; autoloads load; `GameState.save()` round-trips. |
| P1 | Room converter (§8) → tileset + DirtCave0–3 scenes with markers/exits/enemy placeholders (`Marker2D`s named by type until P5). | Each room opens in the editor and the tiles look like the Unity scene (compare against a Unity screenshot if the user provides one). |
| P2 | World scene, Player movement only (§5.1–5.6, 5.14), camera follow + limits (§7.4). Loads DirtCave0 directly. | Walk, jump (variable), coyote, ledge grab and dash work; numbers match §4. |
| **R1** | **Opus review of feel/structure** (user playtests). | User signs off. |
| P3 | Combat: slashes, pogo, recoil, parry/riposte, damage pipeline, i-frames, stun, hit-stop, shake, vignette (§5.7–5.12). Add a debug "dummy enemy" (the Enemy base with 999 hp) to the test room. | Hitting the dummy gives silk; pogo bounces; parry works against a debug damage key. |
| P4 | Silk skills + HUD (§5.13, §7.5). | Heal/Gossamer/Burst cost and behave per the table; HUD reflects hp/silk/lifeblood/shards. |
| P5 | Enemy base + Crawling, Dipsa + bullet, Crabber, loot (§6); replace the P1 placeholders. | All three enemies behave per spec in DirtCave1/2; kills drop shards. |
| **R2** | **Opus review of combat feel** (user playtests). | User signs off. |
| P6 | RoomLoader transitions, RoomExits, rest chair, death → respawn, save/load on boot (§7.1–7.3). | Walk 0→1→2→3 and back; sit on the DirtCave3 chair (saves); die and respawn at the chair; relaunch resumes from the save. |

Coding rules for every phase:
- Port behaviour, not structure: no `GameObject.Find`. Use exported NodePaths, groups (`player`, `spawn_points`, `enemies`) and the autoloads.
- No magic numbers in logic. Put tuning in `PlayerStats`/`@export` with the §4 values and a comment naming the Unity source field.
- Cancellable coroutines: use a per-routine generation counter or Timer nodes, never a bare `await` that can't be cancelled when `damaged()` resets state.
- Don't add mechanics that aren't in the Unity code. If the Unity code has an obvious bug, port it as-is and note it in the Progress log (examples: the ledge-grab gravity reset, `Mathf.Clamp` result discarded in `Update`).

---

## 11. Model usage

| Task | Model |
|---|---|
| This plan; R1/R2 reviews; "runs but feels wrong" debugging; any change to §0 decisions | **Opus 5.5** |
| Phases P0–P6 | **Sonnet 5.5** (one phase per session, reading this file first) |

Housekeeping: some BGM in the original README came from YouTube uploads. Don't copy BGM; replace it before any public release.

---

## 12. Progress log

_(Sonnet appends one entry per phase: date, phase, summary, deviations, open issues.)_

### P0 - 2026-11-25
- Done: git repo initialised (commit "Initial project state", then P0 commit); `.gitignore` extended. `project.godot` set per section 3 via `tools/setup_project_settings.gd` (engine API, so InputEvent serialisation is canonical): viewport 384x216, window override 1536x864, stretch canvas_items/expand, default texture filter Nearest, Jolt line removed, 8 physics layer names, 10 input actions (keyboard + gamepad, joypad events use device -1 = any pad; move_* deadzone 0.2), autoloads GameState/Hitstop/RoomLoader, main scene `res://scenes/world/world.tscn`. Folder layout from section 2 created (.gitkeep in empty dirs). Autoloads: `game_state.gd` (flat PlayerData fields + `GameState.world` WorldData inner class, `stats_changed`, `reset_to_new_game`, `add_visited_room`, `save/load_save/delete_save/save_exists`, JSON to `user://player.json` + `user://world.json`, Vector2 as [x, y], load only overwrites present keys), `hitstop.gd` (`freeze`, `slow`, generation counter), `room_loader.gd` (stub, `transition_time = 1.0`). `resources/player_stats.gd` + `player_stats_default.tres`. Minimal `world.tscn`/`world.gd` (RoomContainer + HUD/Fader/Vignette CanvasLayer placeholders). Assets copied per section 9. `tools/test_save_roundtrip.gd` (save round-trip + Hitstop overlap test, backs up/restores any real user save).
- Deviations: (1) `enemy_kill_count` keys are ints in memory, strings in JSON (JSON keys must be strings; converted back on load). (2) Dipsa bullet sprite: the NormalDipsaBullet prefab references `Enemy/TwistedDipsa/Sprite/Bullet.png` (guid 36c6c6ef...); copied to `assets/enemies/DipsaBullet.png`. (3) Extras copied beyond the section 9 list: `SlashParticles.png`, `ScaleShard.png` (Loot/Sprite/*). Tenroh `useLifeBloodNeedle` not copied (out of scope). (4) `tools/setup_project_settings.gd` kept as a re-runnable helper.
- Open issues: none known. Hitstop/RoomLoader/GameState cannot be called from a SceneTree `_initialize` (autoloads not in tree yet); await one `process_frame` first in tool scripts.

### P1 - 2026-11-25
- Done: `tools/unity_room_converter.py` (stdlib, `python -I`) parses the tileset `.png.meta` and DirtCave0-3 `.unity` files (regex block scan, parent transforms resolved incl. stripped prefab transforms) and writes `tools/room_data/tileset.json` + `dirt_cave_N.json` and composited previews `tools/room_previews/dirt_cave_N.png` (own PNG codec; markers drawn: green=Entry, red=exit box (grey=disabled), blue=PlayerStart, orange/purple/pink=Crawling/Dipsa/Crabber, yellow=RestChair). `tools/build_rooms.gd` (headless `-s`) builds `scenes/rooms/sunnyland_tileset.tres` (128 sliced sprites only, each with a full-square collision polygon on physics layer 0 = Ground) and `dirt_cave_0..3.tscn`. `scenes/interactables/room_exit.tscn/.gd` (`class_name RoomExit`, `@tool`). `tools/check_rooms.gd` verifies the rooms. Tile totals match Unity exactly (1104/1903/1850/677). Enemy prefab GUIDs read from `.prefab.meta` (Crawling 17b5050d..., Dipsa acccdb89..., Crabber 9aec5bbe..., RestChair 5471ba15..., Tenroh ba19acb3...).
- Findings: all Tilemap/Grid transforms are at the origin (offset 0, no scale), tile anchor 0.5, so cells map (x, y) -> (x, -y-1) exactly. No flipped/rotated tiles (all matrices identity); the builder errors out if a flip is ever encountered (alternative tiles not implemented). Atlas y-flip confirmed visually: previews are coherent caves. RestChair instance name is overridden to "RestChair" (`m_Name` modification), same as the prefab root. Enemy instance names carry Unity suffixes ("Dipsa (1)") and are kept as metadata `unity_name`; Godot names are `Crawling`, `Crawling2`, ... Exits to DirtCave4 / DirtCave14 are `disabled = true` (both in DirtCave2).
- Deviations: (1) `RoomExit` has extra exports `box_size` / `box_offset` (px) instead of editing the child shape per instance (instance-child edits are not saved by `PackedScene.pack`); `_apply_shape()` builds the RectangleShape2D at `_ready`. (2) `RoomExit` calls the autoload via `get_node_or_null("/root/RoomLoader")` so the script compiles under `-s` tool scripts. (3) A `PlayerStart` marker (group `player_start`) is emitted in all four rooms, since the Tenroh prefab is placed in every scene; only the respawn scene's one matters (plan 7.2). (4) Exit node names are `Exit_<Unity GameObject name>` (e.g. `Exit_DirtCave2-Entry1`; DirtCave0's is `Exit_ExitToEntry0`). (5) Preview PNGs come from the Python converter (not Godot rendering).
- Open issues: DirtCave2 has Entry0..Entry3 (Entry2/Entry3 belong to the unported rooms 4/14 exits). DirtCave1/3 PlayerStart is a Unity editor leftover and is not guaranteed to be a sensible spawn (DirtCave3's lies in a separate pocket left of the main chamber); only DirtCave0's is meaningful. `-s` tool scripts printing `Identifier not found: RoomLoader` was the symptom of referencing autoloads directly; avoid that in tool scripts.

### P2 - 2026-11-25
- Done: `scenes/player/player.tscn` (built by `tools/build_player.gd`, re-runnable) + `player.gd` (`class_name Player`, group `player`, layer Player/mask Ground, body 12.8x23 @ (0,2.7), `Visual` with one `Sprite2D` (scale 0.25; texture/hframes/frame switched by AnimationPlayer tracks), `DashAttackPos`, `PogoAttackPos`, `LedgeGreen`, `LedgeRed` markers, `DustPE` CPUParticles2D). Clips idle/run/jump/fall/dash/ledge_grab/hurt with exact `.anim` times (idle frames 0,1,2,0 at 0/0.1667/0.3333/0.5 len 0.5167; run 0,1,0 len 0.35; 1-frame clips len 1/60). `player.gd` ports 5.1 (full control gate + all flags declared: control_lock, is_dashing, in_attack, in_silk_skill, is_parrying, is_paralyzed, is_slowed, is_hurt, is_dead, resting, in_menu, in_i_frame), 5.2, 5.3, 5.4, 5.5 (both probes, gravity-reset quirk kept), 5.6 (`_do_dash(also_attack, dir)` + `cancel_dash()` via generation counter), 5.14, landing dust/refill, Unity drag, `gravity_on`, `is_kinematic`, `anim_override` hook for P3 one-shots. `player_sfx.gd` (footstep every 0.5 s grounded+RUNNING; jump/dash/landing/attack/damaged/parry/silkbind players, random volume 0.8-1.0 linear and pitch 0.7-1.3). `scenes/camera/game_camera.gd` (follow, smoothing 5, drag margins, zoom 1.125, `set_room_limits(room)`, `shake(intensity, time, unscaled)`, `snap_to_target()`). `world.tscn/world.gd` (Player + GameCamera + `DebugOverlay`; loads `dirt_cave_0` straight into RoomContainer, places the player at `PlayerStart`; F9 = test shake, debug builds only). `scenes/ui/debug_overlay.gd` (F3 toggle, on by default in debug builds). `tools/test_movement.gd` (headless test with a constructed flat room using the real tileset and the real player scene).
- Test numbers (`-s tools/test_movement.gd`, 60 Hz physics, ALL PASS): run 108.4 px/s effective (112 commanded; Unity linear drag takes it to 112/(1+2*dt); at Unity's 50 Hz that is 107.7) = 6.8 tiles/s; full-hold jump apex 71.5 px (4.47 tiles); tap jump (release after 1 frame) 2.8 px; dash 65.3 px (4.08 tiles) in 0.267 s (16 ticks, timer fires after 15); terminal fall 392.4 px/s (= gravity/drag, 24.5 tiles/s); coyote jump at 0.15 s = jumps, at 0.25 s = does not (extra_jump 0); ledge grab beside a wall top: grabbed, velocity 0, gravity off, held still; jump from ledge: vy -173, leaves ledge, rises 68 px in 40 frames.
- Deviations / findings: (1) **Jump height is ~4.5 tiles, not the plan's ~5**: the Unity formulas themselves give it (hand simulation: hold 0.3 s at 192 px/s, then gravity-then-drag every step): 63.8 px at 50 Hz (Unity), 68.5 px at 60 Hz, 71.5 measured in Godot. Nothing was tuned; the "5 tiles" in section 4 is a loose estimate. Also, jump speed is applied *before* gravity+drag in the same step, so the effective rise speed is 173 px/s, not 192. (2) Camera drag margins: implemented as 0.4 here. **Corrected by Opus review:** Godot drag margins are a fraction of the half-screen measured from the centre, so Unity's central 0.2 dead zone (±10 % of the screen) is `drag_*_margin = 0.2`. Now 0.2 (`DEAD_ZONE` const); §7.4's "±0.1" was also wrong. Look-ahead not implemented (optional). (3) `is_grounded` uses a 12x1.6 `intersect_shape` box at (0, 14.2) like Unity's OverlapBox (not `is_on_floor()`), so it stays true while gravity is off during a ground dash; ledge probes use the same query on the Visual-mirrored markers. (4) Input edges are buffered from `_input` (EDGE_ACTIONS) and OR-ed with `Input.is_action_just_pressed`, so taps between physics ticks are never lost. (5) Dash/other timers use `create_timer(t, true, true)` (process-in-physics, scaled by `Engine.time_scale` like WaitForSeconds). (6) `PlayerStats` gained `dust_offset` and `slowed_speed_modifier`. (7) Dash-attack/pogo/attack/parry/skill handlers are intentionally absent (P3/P4); comments mark where they go in `_physics_process`. (8) Test scripts must not reference `Player`/`GameState` identifiers statically (compiled before autoloads exist in `-s` mode); `test_movement.gd` uses an untyped player variable and `Input.flush_buffered_events()` after `parse_input_event` (otherwise the event is dispatched a tick late).
- Open issues: dust particles are a simple untextured brown puff (tune by eye); Unity's `AnimationControl` thresholds (0.1 u/s = 1.6 px/s) kept. `PlayerStart` of DirtCave0 is in a shaft at the top, so the game starts with a fall (as in Unity). No hurtbox / contact damage yet (P3).
- How to playtest: open the project in the Godot 4.7 editor and press F5 (main scene = `world.tscn`). Controls: arrows = move, X = jump (hold for height, tap for a short hop), Z = dash, gamepad: stick/D-pad, A = jump, right trigger = dash. F3 toggles the debug overlay (velocity px/s and tiles/s, on_floor/grounded, anim state, dash/jump counts, coyote timer, ledge grab); F9 triggers a test camera shake. Try: jump beside the wall tops in DirtCave0 to ledge-grab, walk off an edge and jump late (coyote 0.2 s), dash then jump.

### P3 - 2026-11-25
- Done: combat per section 5.7-5.12 and enemy base 6.1.
  - `player.gd`: attack (forward/up, `attack_timer > attack_cooldown and not in_attack`, `in_attack` driven by `begin_attack_anim` / `end_attack_anim` clip events), pogo (`_do_dash(true, (facing, +1))`), `attack_recoil`, `dash_attack_touch_ground`, parry (`_parrying`, `_parry_riposte` with hit-stop 0.35, i-frames, 1.5x dash, piercing no-recoil DashSlash, +0.1 s tail, `parry_timer = parry_cooldown`), full `damaged()` pipeline (lifeblood, state reset + cancelling dash/parry/riposte generations + `anim.stop()`, vignette pulse, unscaled shake 5/0.3, hurt spark + particles, hit-stop 0.35 x dmg, i-frames 1.5 s alpha 0.5 + Hurtbox monitoring off, stun 0.4 s zeroing velocity BEFORE the impulse dir*80 + (0,-80)), contact damage via `Hurtbox` (mask Enemy + EnemyAttack) incl. re-check of overlaps 2 physics ticks after i-frames end, status effects (paralyzed 1 s / slowed 2 s / drained -2 silk), `_death()` (emits `died`, calls `RoomLoader.respawn()` via `get_node_or_null` if present, restores hp after `transition_time`), `heal()`, `rest_chair_recovery()`, `flash_white()`, `PlayerTrigger` Area2D (layer 8). New tuning is in `PlayerStats` (Unity-source comments).
  - `player_slash.tscn/.gd` (`class_name PlayerSlash`, variants SLASH / DASH_SLASH / POGO_SLASH from the table in 5.9; pogo polygon = prefab m_Points x16, y negated), slash fade incl. the Unity quirk "fadeSpeedAccel becomes 100 once the hitbox ends", silk +1 per enemy hit (clamped, `stats_changed`), one hit per enemy per slash (an enemy's body and its ContactArea both overlap), ground contact -> `dash_attack_touch_ground`. Projectile handling is duck-typed (`melee_hittable` + `damaged`) until P5.
  - `scenes/enemies/enemy.gd` (`class_name Enemy`): full 6.1 base (knockback + restartable 0.25 s `should_stop_moving`, 0.05 s invulnerability, random-pitch sfx, particles, 0.15 s flash, death with kill count / DeadEnemy layer / tint / vertical flip / gravity+drag 1 / loot hook / `Hitstop.slow(0.2, 0.2)` / free after 10 s / `will_be_destroyed` fade). AI subclasses override `_ai_process(delta)` (skipped when dead). `training_dummy.tscn` = Enemy base, hp 999, gravity_scale 1, drag 1, Crawling frame 0, contact damage ON; `world.gd` places two on the floor next to the PlayerStart landing spot in debug builds only.
  - VFX: `scenes/vfx/flash.gdshader` (`flash` uniform, shared by player and enemies), `slash_spark.tscn` (4 stacked frames, 0.2167 s), `hurt_spark.tscn` (0.25 s scale+fade), `slash_pe.tscn` / `hurt_pe.tscn` (CPUParticles2D, self-freeing), `vignette.gdshader` + `scenes/ui/hurt_vignette.gd` (on the world's Vignette CanvasLayer; 0.6 -> base 0.3 over 2 s).
  - Animations added to `build_player.gd`: attack, attack_up (frames 0/1/2/2 @ 0/0.0333/0.0667/0.2 and 0/0.0667/0.1333/0.2, len 0.2167, no loop, begin/end events), dash_attack, pogo_attack, parry / parry_received / parry_riposte (frames 0/1/2 of tenroh_parry.png), hurt clip got `end_attack_anim` @0. The AnimationPlayer now runs in physics process mode with immediate method calls (events fire at exact physics times and pause during hit-stop).
  - Debug (debug builds only): F10 = 1 damage from the right, F11 = +1 lifeblood, F12 = fill silk; overlay shows hp/lifeblood/silk, in_attack, is_parrying, parry_timer, in_i_frame, control_lock.
  - Tools: `tools/build_combat.gd` (builds slash, vfx and dummy scenes; run it before `build_player.gd` after a fresh checkout/import), `tools/test_combat.gd`.
- Test table (`-s tools/test_combat.gd`, 60 Hz, ALL PASS): forward slash dummy hp 999 -> 995, silk +1, dummy knockback vx 80.0 px/s away, player velocity (0, 0); slash facing left hits and knocks left (-80); up slash hits dummy above (-4); cooldown: slash count 1 at t0, 1 at +0.25 s (ignored), 2 at +0.37 s (accepted); pogo onto dummy: min vy -400.0 px/s at impact, dash refilled to 1 and jumps to 2 (extra_jump 2), dummy -4, silk +1; pogo into floor: dash stops after 3 frames (0.05 s), speed 0; damage: hp 5 -> 4, hit-stop 0.0 -> 1.0 after 352 ms real, post-freeze velocity (77.4, -64.8) (= (80, -80) after one tick), i-frames start (alpha 0.5, hurtbox off), 2nd hit inside window ignored, stun 24 game frames (0.40 s), i-frames 90 game frames (1.50 s), hit accepted afterwards; lifeblood 2 -> 1 (hp untouched), lifeblood 1 + 3 dmg -> hp 3; parry: no hp loss, parry_state 2, freeze 351 ms, riposte vx 465 (480 before one tick of drag), moved 85.5 px in 0.25 s (98 px incl. the first tick), piercing no-recoil slash, i-frame tail, parry re-usable immediately; damage after the window -> -1 hp; contact: walking into the dummy -1 hp after 30 frames, pinned inside the dummy it hurts again after 89 game frames (1.48 s); death: `died` once, dead for 1.00 s, hp restored to 5. `test_movement.gd` still ALL PASS; `check_rooms.gd` ALL OK; import and `--quit-after 120` print no errors/warnings.
- Deviations / findings:
  1. `Engine.time_scale = 0` does NOT stop physics frames in Godot 4: `physics_frame` still fires and `_physics_process` runs with delta 0 (scaled timers / Unity-style WaitForSeconds pause correctly, but unscaled code keeps ticking). The hit-stop works as intended; test scripts must count only frames with `time_scale > 0` (see `_frames` / `_thaw` in `test_combat.gd`).
  2. An `Area2D` with `monitorable = false` does NOT report TileMapLayer bodies (verified: ground contact only works with monitorable true). The slash therefore keeps the default `monitorable = true`; it sits on layer PlayerAttack, which nothing masks.
  3. TileMapLayer is not a `CollisionObject2D`; ground is recognised with `node is TileMapLayer` (plus any body on layer Ground).
  4. Unity quirks ported as-is: if a dash/pogo slash touches Ground before an enemy in the same swing, `impacted` is already true and there is no recoil; `Damaged` while `isParrying` restarts a riposte if hit again during the 0.35 s freeze; the riposte DashSlash zeroes the riposte velocity if it touches Ground.
  5. `rest_chair_recovery()` cleans up the cancelled routines (i-frame flag, stun control lock, alpha) instead of Unity's bare `StopAllCoroutines`, which could leave `inIFrame` / `disableControlCounter` stuck.
  6. Status-effect timers use generation counters (a re-applied effect restarts its timer; Unity's first coroutine would end the effect early).
  7. The hurt vignette keeps Unity's persistent base intensity 0.3 (Global Volume Profile), so screen edges are slightly darkened at all times; `HurtVignette.base_intensity` is exported if you want 0.
  8. SlashPE / HurtPE are approximated (burst counts 5/10, cone 20 deg / all around, lifetimes, speeds, sizes by eye); SlashSpark / HurtSpark use the real frame, scale and alpha curves. Slash spark rotation: X axis along the knockback direction +-10 deg (equivalent of Unity's LookRotation with up = rot(90 + r) * knockback).
  9. Enemy death does not disable the body shape (plan: layer -> DeadEnemy with mask Ground; Unity's `bodyCollider.enabled = false` would let the corpse fall through the floor). The loot hook only spawns when `loot_scene` is set (P5).
  10. Which clip wins when pogo/dash-attack flags and the dash state overlap was not fully decoded from Tenroh.controller: priority is one-shot > parry state > pogo > dash_attack > state clip.
  11. P3-only fallback in `world.gd`: after `Player.died` the player is put back at PlayerStart after 1 s and made non-kinematic (the RoomLoader stub does not respawn yet). Remove when P6 lands.
- Open issues: dummies are knocked away by hits and slide (drag 1), they do not return; `PlayerTrigger` has no consumers yet (P5 loot / P6 chair); `gossamer_instance` / `silk_burst_instance` exist but nothing sets them (P4); the Hurtbox only handles Enemy contact areas (EnemyAttack projectiles will call `player.damaged` themselves in P5, like Unity); the feel of hit-stop / shake / vignette is untested by a human.
- How to playtest: open the project in Godot 4.7 and press F5 (main scene = `world.tscn`). Controls: arrows = move, X = jump, Z = dash, C = attack (Up+C = up-attack, Down+C in the air = pogo), F = parry (ground only, needs 1 s since the last parry); gamepad: X = attack, Y = parry. Two training dummies stand on the floor right of the landing spot (debug builds). Try: slash them (silk +1 per hit; overlay shows silk), pogo off one from above (bounce -400 px/s, dash refilled) and into bare floor (dash stops), touch one to get hurt (0.35 s freeze, shake, vignette, 1.5 s blinking i-frames; stand inside it to be hurt again after they end). Debug keys: F10 = 1 damage from the right (press F then F10 within 0.25 s to parry; the riposte dash follows), F11 = +1 lifeblood (absorbs damage first), F12 = fill silk, F9 = camera shake, F3 = overlay. Let hp reach 0 to see the death fallback (back at the start after 1 s).

### P4 - 2026-11-25
- Done: silk skills per section 5.13 and the HUD per section 7.5.
  - `player.gd`: `_handle_silk_skill()` (press edge, `not in_attack`, inside the control gate, works in the air; Unity if/else-if chain: Up + silk >= 6 -> gossamer, else Down + silk >= 4 -> silk burst, else silk >= 8 and hp < max -> heal; cost paid at press via `GameState.add_silk(-cost)`), animation-event methods `begin_heal / actual_heal / end_heal / begin_gossamer / begin_silk_burst / throw_silk_burst / catch_silk_burst_recoil`; skill lock = `in_silk_skill`, velocity zero, gravity off; `gossamer_instance` / `silk_burst_instance` are now set (and freed by the existing `damaged()` code). Costs, spawn offsets and the recoil impulse live in `PlayerStats` with Unity comments.
  - `build_player.gd`: clips `heal` (tenroh_heal, 2 frames 0/1 @ 0/0.25, len 1.0167, events 0 / 0.5833 / 1.0), `gossamer` (tenroh_gossamer, frames 0,1,0,1,0,1 in 1/6 s steps, len 1.0167, events 0 / 1.0), `silk_burst` (tenroh_burst, frames 0..5 @ 0/0.0667/0.1667/0.25/0.75/0.8333, len 0.9833, events 0 / 0.1667 / 0.8333 / 0.9667), all one-shot (`anim_override` wins until the clip ends). Frame ids were decoded from the `.anim` m_PPtrCurves through the `.png.meta` name tables.
  - `tools/build_skills.gd` (new builder; run order is now build_combat, build_skills, build_player): `scenes/vfx/silk_bind.tscn` (7 frames of 256 over 0.6 s, scale 0.25, `one_shot_anim.gd`), `scenes/player/gossamer.tscn/.gd` (`class_name Gossamer`), `scenes/player/silk_burst.tscn/.gd` (`class_name SilkBurst`), `scenes/ui/hud.tscn` + `scenes/ui/hud.gd` (`class_name Hud`).
  - Gossamer: circle r 38.4 px around its spawn position (centre fixed at spawn, like Unity's Start), `intersect_shape` on the Enemy layer (bodies + areas), every `timer > 0.1 s` (strict, reset to 0, like Unity) damage 3 with knockback `dir * 0.16`, VFX 10 frames of 512 over 0.75 s, frees itself when the clip ends, no silk gain. SilkBurst: Area2D 128x32 at local (64, 0) under Visual, damage 10 once per enemy, knockback `(dir.x * 240, -80)`, 6 frames over 0.483 s, no silk gain. SilkBind VFX at local (4, 0). Sounds: silk_bind via `PlayerSfx.SILKBIND`; gossamer.ogg / silk_burst.ogg are `SkillSfx` AudioStreamPlayers inside the skill scenes (random volume 0.8-1.0, pitch 0.7-1.3).
  - HUD: `HUD` CanvasLayer instanced in `world.tscn`. Masks (`MaskIcon` / `MaskEmptyIcon`, then lifeblood masks with the full icon tinted (0, 0.75, 1), like `HealthUI.cs`), silk bar (SilkBar_0 left cap + `max_silk` segments + SilkBar_2 right cap; filled segment = SilkThread_0, empty segment = SilkBar_1 groove, i.e. the UI.prefab `silkIcon` / `emptyIcon`), copper shard icon + label. Positions/sizes are the UI.prefab values / 5 (1920x1080 reference canvas -> 384x216). Driven only by `GameState.stats_changed`; rows are rebuilt only when `max_hp + lifeblood` / `max_silk` change.
  - Audit of `stats_changed`: `GameState` got `add_silk / add_lifeblood / add_copper_shard` helpers (each clamps and emits); used by the slash (+1 silk), drained status, skills (spend), debug F11 / F12. `damaged()`, `heal()`, `rest_chair_recovery()`, the `_death()` hp restore, `reset_to_new_game()` and `load_save()` already emitted. Loot (P5) must call `add_copper_shard`.
  - `debug_overlay.gd`: moved to the top-right (font 6) so it no longer covers the HUD; shows `in_silk_skill` and lists the skill keys.
- Test table (`-s tools/test_silk.gd`, 60 Hz, ALL PASS; times carry +-2 frames): heal in the air: silk 8 -> 0 at press, hp 3 -> 5 at 0.583 s (still 3 at 0.55 s), lock released at 1.000 s, max dy 0.21 px / speed 0 while casting, SilkBind freed, flash param back to 0; heal on the ground 4 -> 5 (clamp); heal refused at full hp (silk stays 8) and with silk 7; gossamer refused at silk 5 (Up held), burst refused at silk 3 (Down held); gossamer: Up+Q silk 6 -> 0, dummy at 24 px took 6 ticks of 3 = 18 (at 0.12 / 0.23 / 0.35 / 0.47 / 0.58 / 0.70 s), dummy at 100 px untouched, no silk gained, instance freed at 0.767 s, lock released at 1.000 s, dy 0; silk burst (right and mirrored left): Down+Q silk 4 -> 0, dummy at 64 px took 10 exactly once at 0.317 s, knocked (+-240.0, -80.0), player recoil (-+160, -32) at 0.833 s, lock released at 0.967 s, instance freed at 0.667 s, no silk gained; skills blocked while `in_attack` and by `control_lock`; interrupts: hit at 0.3 s during heal -> hp 3 -> 2 and stays 2 after 1.7 s, lock released at once, gravity on, no override clip; hit during gossamer / silk burst -> instance freed, no late recoil (max |vx| 0), lock released; HUD: initial 5 masks / 8 silk / '0', after damage 2 (3 full), silk +3 (3 filled), heal +2 (5 full), silk spent -6 (2 filled), lifeblood +1 (6 masks, last tinted, full texture), lifeblood absorbing a hit (back to 5 masks, hp 5), shards +7 ('7'), max_hp 7 / max_silk 10 (7 masks, 10 segments), new-game reset. `test_combat.gd`, `test_movement.gd`, `check_rooms.gd` still pass; import and `--quit-after 120` print no errors/warnings. A windowed screenshot confirmed the HUD layout (masks, silk bar with 5 of 8 filled, shard counter).
- Deviations / findings:
  1. Gossamer deals **6 ticks (18 damage)** over its 0.75 s life at 60 fps, not the plan's ~7 (21): the Unity code `if (timer > damageInterval) { timer = 0; ... }` makes a tick every 7 frames (0.117 s). Ported as-is, not tuned.
  2. **SilkBurst hitbox is delayed**: `SilkBurst.anim` animates the root `BoxCollider2D.m_Enabled` 0 -> 1 at t = 0.15 s (not in the plan). Ported (`hitbox_delay = 0.15`): the hit lands 0.317 s after the cast starts, not at the throw.
  3. Gossamer and SilkBind are children of `Visual` instead of the Player node: in Unity the whole player transform is flipped, so objects at local (4, 0) mirror with facing; here `Visual` carries the flip.
  4. Plan 5.11 (cancel the skill clip on damage) is followed, but Unity would NOT stop the Heal clip when hit (only an exit-time transition leaves it), so there ActualHeal / EndHeal would still fire after a hit. Here a hit cancels the heal (no late heal).
  5. One hit per enemy per Gossamer tick / SilkBurst: an enemy body and its ContactArea both overlap; Unity would call `Damaged` twice (the second is swallowed by the 0.05 s invulnerability, only the negligible knockback differs).
  6. Unity quirks ported: the if/else-if chain fall-through (Up held without 6 silk -> Down check -> Heal check); SilkBurst knockback x uses the normalised direction x component, not its sign; `EndGossamer` / `EndSilkBurst` both call `EndHeal`; the Gossamer circle centre is its spawn position, not the player; Heal / Gossamer states have LoopTime 1 but leave to Idle through an exit transition (0.754 x clip + 0.25 s blend = clip length), so each cast plays once.
  7. The Light2D children of the three skill prefabs (and their animated intensity) are not ported (URP 2D lights are out of scope).
  8. The HUD approximates UI.prefab at /5 scale (the Unity canvas scales with width); the shard icon is `CopperShard.png` (the prefab Image sprite was not decoded).
- Open issues: skill sounds, hit feel and the HUD look are untested by a human; the SilkBind VFX is not removed when the player is hit mid-heal (Unity does not either, it lives 0.6 s); P5 loot must call `GameState.add_copper_shard`; the debug F-keys only exist in debug builds.
- How to playtest: open the project in Godot 4.7 and press F5. Press F12 to fill silk (HUD silk bar fills; masks top-left, shard counter below). Q = heal (needs 8 silk and hp < max; use F10 to take damage first), Up + Q = Gossamer (6 silk, hits the dummies if you stand within ~2.4 tiles), Down + Q = Silk Burst (4 silk, hits things up to ~4 tiles ahead after a short delay, then pushes you back). Skills work in the air and are blocked while attacking. Get hit (F10 or touch a dummy) mid-cast to see the cast cancelled. F11 adds a blue lifeblood mask, F3 toggles the overlay (now top-right).

### P5 - 2026-11-25
- Done: enemies per section 6, loot, and the room placeholders replaced.
  - `tools/build_enemies.gd` (new builder; run order is now build_combat, build_skills, build_player, build_enemies, build_rooms): `scenes/enemies/{crawling,dipsa,crabber}.tscn` (+ `crawling.gd`, `dipsa.gd`, `crabber.gd`, all `extends Enemy`), `scenes/enemies/projectile.tscn/.gd` (`class_name Projectile`, the Dipsa bullet), `scenes/loot/loot.tscn/.gd` (`class_name Loot`, CopperShardSmall). Sprites are `AtlasTexture` frames per animation key (the Unity sprites are trimmed rects with a centre pivot, not a uniform strip, so `hframes` would misplace them); Idle / Attack clips from the `.anim` files (Crawling 4 frames len 0.6833, Dipsa 4 frames len 0.6833, Crabber idle 3 frames len 0.5167, attack 4 keys len 1.35 with `begin_attack` 0 / `dash_forward` 0.3333 + 1.0 / `end_attack` 1.3333). Animation runs in physics mode, immediate method calls.
  - `tools/build_rooms.gd` now instantiates the real enemy scenes at the Unity positions (names `Crawling`, `Crawling2`..., group `enemy_spawns`, metas `enemy_type` / `unity_name` kept); it awaits one process frame so the enemy scripts can compile. `tools/check_rooms.gd` checks that every spawn is a real instance of the right type standing in empty space. Debug-only dummies in `world.gd` stay.
  - `enemy.gd` additions: `get_player()`, `player_in_circle(r)` (= `Physics2D.OverlapCircle(..., playerMask)` against the Player layer body), Unity **ground friction** (see deviations), and the death flip now scales the Sprite2D (not Visual) like Unity's `sprite.transform.localScale`, so a sprite offset (Crabber) is kept.
  - Crawling: patrol with the probe 12.368 px ahead (mirrored), 16 px ray + r 1.6 px circle against Ground + DeadEnemy, `stabilized` logic and Unity's full-Vector2 lerp (0.1 per 0.02 s) ported 1:1. Dipsa: alert by a 160 px circle against the player body (permanent), `should_stop_moving = dist <= 160`, thrust 80 px/s^2 straight at the player, a shot every 3 s from ShootPos (-3.84, +12.8) at 80 px/s, sprite flip toward the player. Crabber: alert by a 96 px circle, stops inside 48 px, 3 s attack timer, `attack` clip with the two `dash_forward` events (+96 px/s toward the player). Projectile: Area2D that moves itself and polls its overlaps each tick (player -> `damaged(1, dir)` + `inflicted_status_effect`, Ground -> bounce counter; dies when `bounce_counter > max_bounce`), ignores the player during i-frames (Unity IgnoreLayerCollision), gravity 1 / drag 1 / collider off / fade 10 per s once dead, 10 s hard lifetime. Loot: CharacterBody2D (gravity_scale 2, drag 1, friction), pickup Area2D masks PlayerTrigger, sine spin (phase 90..270, speed 5), 20 s auto-free, pickup -> `GameState.add_copper_shard(1)`, hide, sfx, free after 1 s.
- Test table (`-s tools/test_enemies.gd`, 60 Hz, ALL PASS, about 90 s because the room smoke runs 10 s per room): Crawling steady patrol speed 29.5 px/s (model 30.3 = Unity lerp + friction; commanded 48), turns 12 px before a ledge (x -468 vs edge -480) and at a wall (x 130.5, body edge 139.6 vs wall 144), contact damage after 104 frames; slash: hp 8 -> 4, silk +1, knockback vx 75; death: layer 64, contact area off, kill count +1, 3 loot, all 3 picked up (+3 copper). Dipsa: idle at 200 px, alerted at 140 px and stays alerted; vx 41.2 px/s after 1 s (model 41.4), 53.3 px/s top speed, flips right; hovers inside 160 px; bullets at frames 182 and 363 (3 s cadence), |v| 80.0 toward the player, spawn offset (-3.8, 12.8); a bullet hurts 1 hp (frame 251); bullets die on Ground, pass the player during i-frames, paralyse with `inflict_status = 1`, have a hard lifetime; slash -4 hp, death drops 5. Crabber: idle at 150 px, alerted at 90 px; walks 63.4 px/s; the attack starts 181 frames after the alert and lasts 79 frames (clip 1.35 s, dashes at +20 / +59 frames with dv +96.0 / +94.6), the dash contact hurts the player (-1), back to idle; slash -4 (12 hp), death drops 4. Loot: lands and rests, spins, +1 copper once, freed 1 s after pickup, auto-free. DirtCave1 and DirtCave2 smoke (10 s with the player far away): 5 enemies each stay in the room, crawlers and crabbers rest on the floor, Dipsas hover unalerted. `test_save_roundtrip`, `test_movement`, `test_combat`, `test_silk`, `check_rooms` still pass; `--quit-after 300` prints no errors.
- Deviations / findings:
  1. **Ground friction (not in the plan)**: Unity enemies, loot and tiles all use the default physics material (friction 0.4, mixed sqrt(0.4*0.4) = 0.4), so Box2D decelerates a resting body by 0.4 * 9.81 * gravityScale u/s^2. `Enemy` (and `Loot`) now apply `move_toward(vx, 0, 0.4 * 157 * gravity_scale * dt)` while on the floor (`friction` export, 0 disables). Consequence, and the reason for the plan's "Crabber ~64 px/s": the Crawling lerp towards 48 px/s settles at about **30 px/s** (analytic (k*48 - mu*g)/(k+drag) with k = -ln(0.9)/0.02), not 48. 48 px/s is only the lerp target. Knockback slides are also a bit shorter than in P3. Set `friction = 0` on `crawling.tscn` if 48 px/s is preferred.
  2. Crabber walk: Unity force 400 * 0.02 = 8 u/s^2 = 128 px/s^2 horizontally (the 1 u/s^2 upward `force.y = 1` is ignored) against the friction above gives 63-65 px/s with no tuning, matching the plan target. Direction is the sign of the x offset to the player (Unity used the normalised A* waypoint direction, so Unity is slower when the player is far above/below); `dash_forward` uses the same sign (Unity: normalised path direction, AddForce 300 -> +96 px/s at sign +-1).
  3. No A* pathfinding for Dipsa/Crabber (plan allows it): Dipsa flies in a straight line (it can get stuck behind walls, nothing replans). Alert detection uses a circle against the player body collider (like `OverlapCircle`); the stop/shoot checks use the root-to-root distance (like Unity).
  4. Obstacle mask for Crawling = Ground + DeadEnemy (Unity `notWallMask` 12161 excludes Default, Player, Enemy, attack, loot and trigger layers; everything else counts). The plan listed Ground only.
  5. The bullet is an `Area2D` that moves itself, not a CharacterBody2D. It does not physically push the player (Unity bullet mass 0.0001); damage comes from the overlap poll. It dies on the first overlap with the Ground layer (a TileMapLayer or a Ground-layer body), like Unity `bounceCounter > maxBounce (0)`.
  6. Unity quirks ported: CrawlingAI lerps the whole velocity vector (y too, `moveVelocity.y = 0`); DipsaAI overwrites `shouldStopMoving` every frame (the 0.25 s knockback stop is overridden while it is alerted); the Crabber timer only counts while not in its attack animation and its `end_attack` also clears `should_stop_moving`; a dead enemy keeps its AI frozen (base skips `_ai_process`).
  7. Hit particles are the same approximation as the dummy (6 particles, 30 deg cone); Unity `PSPrefabs` (HitSilkPS) were not decoded.
  8. `Enemy.damage` is still unused (the player takes `PlayerStats.contact_damage` = 1, which equals every ported prefab damage of 1).
- Open issues / notes for P6: enemies are plain children of the room scene, so a room reload (RoomLoader) respawns them all at full hp, like Unity scene loading; loot and bullets are added to the enemy parent (the room) and are freed with it. `GameState.world.enemy_kill_count` is incremented per kill (key = enemy_type int) and saved with the world data. Enemies find the player with `get_tree().get_first_node_in_group("player")` every tick, so the player must stay in group `player` and must not be freed on respawn. Dipsa/Crabber alert detection uses the player body layer (Player, bit 2); bullets skip the player only while `in_i_frame` or `is_dead`, so the rest chair (Hurtbox off) should also keep the player `in_i_frame` (or the bullets will hit and be consumed without damage). The test script takes about 90 s.
- How to playtest: F5 starts in DirtCave0, which has no enemies (P6 adds transitions). To see them now, change `P2_START_ROOM` in `world.gd` to `dirt_cave_1.tscn` / `dirt_cave_2.tscn` (the player will fall from the PlayerStart position), or open a room in the editor and press F6. Crawlers patrol, Dipsas wake at 10 tiles, Crabbers at 6 tiles and lunge twice every 3 s inside 3 tiles; kills drop copper shards that fly out and are collected by walking over them (HUD counter).

### P6 - 2026-11-25
- Done: room transitions, exits, rest chair, death -> respawn, save/load on boot (plan 7.1-7.3). The port is feature-complete for the scope in section 1.
  - `autoload/room_loader.gd` (`LevelLoader.cs`): `register_world()` (called by `World._ready`), `start()`, `load_level(room, spawn)`, `respawn()`, `update_spawn_point(chair)`, `room_loaded` signal, `room_path()` / `snake_case()` ("DirtCave14" -> `dirt_cave_14.tscn`). `load_level`: `control_lock += 1`, `gravity_on = false`, fader fade-out (linear, `Fader`), wait `transition_time` (1.0 s, scaled physics timer), free the old room, instance the new one under `RoomContainer`, `add_visited_room`, place the player (respawn branch wins over the spawn-name branch, like Unity), `gravity_on = true`, `camera.set_room_limits` + `snap_to_target`, `control_lock = max(control_lock - 1, 0)` (Unity does that on every scene load), fade-in 1 s (does not block control, like Unity). A newer `load_level` supersedes an in-flight one (generation counter; the older only undoes its own lock). `start()` = MainMenu Continue / New Game: save on disk -> `GameState.load_save()`, else `reset_to_new_game()`; loads `respawn_scene`, applies the SpawnPointInit edge case (no chair and `respawn_pos == ZERO` -> `respawn_pos = PlayerStart`), sits on the saved chair; no fade, no control lock. Without a registered World (unit tests with a bare player) `load_level` / `respawn` return silently.
  - `scenes/ui/fader.gd` (`class_name Fader`, on the existing `Fader` CanvasLayer in `world.tscn`): black ColorRect, linear tween alpha, scaled time.
  - `scenes/interactables/rest_chair.tscn/.gd` (`class_name RestChair`, built by the new `tools/build_interactables.gd`; builder order is now build_combat, build_skills, build_player, build_enemies, build_interactables, build_rooms). Area2D (mask PlayerTrigger) with the prefab trigger (43.14 x 22.82 at (0.09, +13.86)), SitSpot (0, +3.2), sprite (PPU 64, scale 0.25), "Rest" label, `Ui` CanvasLayer with SoftFlash (alpha 100/255, -0.3/s) and "Saving..." (1 s), SaveSfx. Rooms now contain this scene instead of the Marker2D placeholder (node name `RestChair` kept; group `rest_chairs`). Sit: in range + `Input.get_vector(...)` fully up (Unity `Movement.y == 1`, so diagonals do not count) and not sitting; stand: sitting + fully down. `get_on_chair()` (also used by RoomLoader on respawn): `resting = true`, `rest_chair_recovery()` (hp = max_hp only, as Unity), velocity 0, `is_kinematic`, position = SitSpot, `GameState.respawn_chair_name = name` / `respawn_scene = current room`, invulnerable, save sfx, `GameState.save()`, label hidden. The soft flash and "Saving..." only play when the player presses Up (not on respawn), like Unity.
  - `player.gd`: `begin_rest_invulnerability()` / `end_rest_invulnerability()` (endless i-frame without blink: `in_i_frame = true`, Hurtbox off). The P5 note is honoured: bullets skip the player while `in_i_frame`, so they pass through a sitting player. Standing up re-checks overlapping enemies (existing i-frame-end logic). The P4 note (chair clears i-frames / stun on stand-up) is the existing `rest_chair_recovery()` cleanup.
  - `world.gd`: the P2 direct room load, the P3 death fallback (`_on_player_died`, `P3_RESPAWN_FALLBACK_DELAY`) and the F6/F7 room-cycle keys are removed; `_ready` registers with RoomLoader and calls `RoomLoader.start()`. F3 / F9-F12 debug keys stay. Debug dummies (debug builds only) now spawn only when DirtCave0 is loaded (every time it loads, like enemies); a `spawn_debug_dummies` flag lets tests turn them off. The `Player.died` signal is kept (tests use it).
  - `tools/build_rooms.gd` instances `rest_chair.tscn`; `tools/check_rooms.gd` checks the chair instance.
- Test table (`-s tools/test_world.gd`, 60 Hz, ALL PASS, ~45 s; backs up / restores any real user save, works on its own temporary one): boot without a save = DirtCave0, player at PlayerStart (3.5, -350.3 vs -350.9 after one tick), respawn_pos = PlayerStart, visited [DirtCave0], camera limits = room used rect, no save file written; exits 0->1, 1->0, 1->2, 2->3, 3->2 each swap 61 physics frames (1.017 s) after the lock (Unity: 1.0 s transitionTime; the extra frame is the physics-sync wait, deviation 1), mid-fade alpha 0.50, fade-in cleared after 59-60 frames, player exactly on the target Entry marker, lock 0 at swap, correct camera limits, one room in the container, no re-trigger after arriving, visited_rooms accumulates, player node never freed, exits never save; disabled exits (DirtCave14, DirtCave4) inert for 2 s; chair: sits within 4 frames of Up, position == SitSpot, hp 2 -> 5, silk 5 and copper 7 untouched, respawn_chair_name RestChair / respawn_scene DirtCave3, `player.json` + `world.json` written with those values, "Saving..." visible then hidden after 1 s, soft flash 0.371 a few frames after the 0.392 start and 0 after 1.3 s, `damaged()` ignored while sitting (in_i_frame, hurtbox off), no movement control while resting, Down stands up (all flags released) and damage works again; death at the chair: lock 2 while dead (Death +1, LoadLevel +1, as Unity), swap 59 frames after the hit (1.0 s), player sitting on the chair in the freshly loaded DirtCave3 with hp max and silk kept, same player node, lock 0 / alive afterwards, can stand and move; death without a chair: back in DirtCave0 at `respawn_pos`, not kinematic, hp max; boot with a save: DirtCave3 on the chair, hp 6/6 (chair recovery of max_hp 6), silk 5, copper 11, lifeblood 1, visited rooms and kill counts restored, HUD shows 7 masks / 5 of 8 silk / "11"; enemy respawn: killed enemy gone after reload, 5 fresh enemies at full hp in a new room instance, old room freed, kill count kept. `test_save_roundtrip`, `test_movement`, `test_combat`, `test_silk`, `check_rooms`, `test_enemies` are unchanged and still pass (none depended on the removed fallback; `test_combat`'s death test runs without a World, so `RoomLoader.respawn()` returns silently); import and `--quit-after 300` of the main scene print no errors.
- Deviations / findings:
  1. **Stale physics position on teleport (fixed, important)**: a `CharacterBody2D` applies a new transform to the physics server only on the next step. Instancing a room right after moving the player created the new room's Areas (RoomExit, enemy ContactArea, chair) against the OLD position: e.g. leaving DirtCave0 at its exit put the player in DirtCave1, where DirtCave1's exit-to-DirtCave2 trigger overlapped the old position and fired a second transition. `RoomLoader._swap_room` therefore frees the old room, moves the player (position computed from the room's local transforms before it is in the tree), calls `force_update_transform()`, waits one `physics_frame`, then adds the new room. Consequence: a swap takes 1 extra physics frame (61 instead of 60) and `start()` finishes one frame after `World._ready` (nothing else depends on it). Contact damage / chair range are protected by the same fix.
  2. Unity's editor-only reset in `SpawnPointInit` (`respawnPos = 0`, chair name = "" when `Application.isEditor`) is not ported; a save always restores the chair.
  3. Unity `UpdatePlayerPosition` leaves `gravityScale = 0` after a respawn (restored by the ledge-grab else branch once the player is controllable). Here `gravity_on = true` is set at the swap in all branches (plan 7.2); the effect is identical.
  4. The interaction label text is "Rest" (Unity `InteractText` TMP text), not the plan's "Up to rest"; the font is Godot's default (TMP font not ported).
  5. The chair restores **hp only** (`RestChairRecovery`). Silk is NOT refilled (the plan's task text said "hp/silk"; the Unity code only refills hp, plus `RefillRedTool`, out of scope). Lifeblood is untouched too.
  6. Unity makes the player invulnerable via `Physics2D.IgnoreLayerCollision`; here it is `in_i_frame` + Hurtbox off (no sprite blink). `GetOffChair` ends it with `_end_i_frames()`.
  7. Fader / transition timing uses scaled time like Unity's Animator + `WaitForSeconds`; the fade-out alpha is linear 0 -> 1 over the wait (CrossfadeStart.anim) and the fade-in 1 -> 0 over 1 s (CrossfadeEnd.anim); control returns at the swap, during the fade-in.
  8. The chair respawn also saves (Unity `GetOnChair` always calls `SavePlayerData`), so every boot-with-save and every death-respawn at a chair rewrites the save (hp = max).
  9. No main menu: the game continues from the save whenever one exists (Unity: Continue button). To start a new game delete the save (see playtest notes); Unity's New Game button does not delete it either.
  10. `respawn_scene` holds the Unity scene names ("DirtCave3"), the same as the room root node names.
- Known gaps for the whole port (section 1 out-of-scope list plus approximations): no pause / main menu / inventory / journal / map / shop UI, NPCs, bosses, talismans and red/blue/yellow tools (`tool_cooldown` kept in the data), rooms DirtCave4+ and Mossy rooms (their exits are disabled), no A* pathfinding (Dipsa / Crabber move in straight lines and can get stuck behind walls), no URP lights / post-processing (hurt vignette is a simple shader, base vignette 0.3 always on), BGM not copied, dust / hit / slash particles approximated, SilkBind VFX is not removed on interruption, HUD approximates UI.prefab at /5 scale, Gossamer deals 6 ticks (Unity frame-timing quirk), enemies are not persistent (respawn on every room load, like Unity scene loading). Nothing was tuned away from Unity values to pass tests; the hit-stop / camera shake / vignette / transition *feel* has not been judged by a human.
- Open issues: none known. The debug dummies exist only in debug builds and only in DirtCave0.
- How to playtest: open the project in Godot 4.7 and press F5. Controls: arrows = move (Up / Down also sit / stand on the chair and pick silk skills), X = jump, Z = dash, C = attack (Up+C up, Down+C in the air = pogo), F = parry, Q = silk skill (Up+Q Gossamer 6 silk, Down+Q Silk Burst 4 silk, Q alone Heal 8 silk); gamepad per section 3. A new game starts in DirtCave0 (falls from the shaft). Route: DirtCave0 right exit -> DirtCave1 -> its right exit -> DirtCave2 (hub, 5 enemies; the two exits on its right side are inert) -> the exit at the lower left of DirtCave2 -> DirtCave3. The RestChair is in DirtCave3, about 9 tiles left of where you arrive: walk into its range (the "Rest" label appears) and press Up to sit (saves, "Saving..." shows, hp refilled), Down to stand. Die (hp 0, or F10 debug damage) to see the fade and the respawn on the chair (at the start position if you never sat). Save files: `%APPDATA%\Godot\app_userdata\SilkMelodyOcean\player.json` and `world.json`; delete both to start fresh. Debug keys: F3 overlay, F9 shake, F10 damage, F11 lifeblood, F12 fill silk.


### Menus - 2026-11-25 (main menu + pause menu, after P6)
- Done:
  - **Main menu** (`scenes/ui/main_menu.tscn/.gd`, `class_name MainMenu`) is now `run/main_scene`. Port of `MainMenu.unity` / `MainMenu.cs`, laid out on the 1920x1080 canvas / 5: `MainMenu2.png` (960x540) stretched over the viewport, white 0.07 alpha tint (the Unity "Image"), buttons New Game / Continue / Quit (80x16, spacing 6, group centre at y +200 below the screen centre; TMP font 50 -> 10 px), "v0.1.1" at the bottom left (Unity `Version` text; read from the new `application/config/version` setting, set to 0.1.1). Continue: dimmed to text alpha 0.2 and inert without a save (still focusable, like Unity), initial focus when a save exists, otherwise New Game has it. New Game: `RoomLoader.StartMode.NEW_GAME` -> `GameState.reset_to_new_game()` + DirtCave0; the save on disk is NOT deleted (Unity's delete is commented out). Continue: `StartMode.CONTINUE` -> `load_save()` + saved respawn scene / chair. Quit: `get_tree().quit()`.
  - **`SelectButton`** (`scenes/ui/select_button.gd`): flat button with the Unity select frame (`LongSelectFrame.png`, shown only while focused) and the select sound (`menu_button.ogg`, played on focus). `chosen` signal fires on activation unless `inert`. Mouse hover focuses it.
  - **Pause menu** (`scenes/ui/pause_menu.tscn/.gd`, `class_name PauseMenu`, a `CanvasLayer` layer 20 instanced in `world.tscn`, `PROCESS_MODE_ALWAYS`). Port of `PauseMenu.cs` / `PauseMenu.prefab`: black 0.78 alpha panel (1820x979 / 5 inset) with the "PAUSED" title (72 -> 14 px). The `pause` action (Escape, gamepad Back, and now also Start, button 6) opens it, pause / Escape / `ui_cancel` (gamepad B) close it. Opening does `player.control_lock += 1` and `get_tree().paused = true`; closing undoes both (the lock is clamped at 0, other lock changes made meanwhile survive). `Engine.time_scale` is never touched (Hitstop owns it).
  - Extension beyond Unity: buttons **Resume**, **Main Menu**, **Quit** under the title (Resume has the initial focus, `ui_up` / `ui_down` navigation, same focus frame + sound). Main Menu goes back to the menu scene without a save prompt (saving only happens at the rest chair).
  - **`RoomLoader.start(mode)`** now takes an explicit `RoomLoader.StartMode { NEW_GAME, CONTINUE }`. `World.start_mode` (default CONTINUE) is passed by `World._ready`; the menu sets it before the world enters the tree. CONTINUE without a save falls back to a new game with a warning. `RoomLoader.unregister_world()` (called from `World._exit_tree`) drops all references and invalidates in-flight loads; `RoomLoader.is_transitioning()` is true from the start of `start()` / `load_level()` until the room swap finished. `_swap_room` now takes the load id and frees the not-yet-added room if the world went away while waiting for the physics frame.
  - `scenes/ui/scene_flow.gd` (`SceneFlow`): `to_world(tree, mode, old)` / `to_main_menu(tree, old)` swap the current scene by hand (works without `change_scene_to_*` / a current scene, so tests can use it; main menu resets `paused` / `time_scale`).
- Pause design decisions:
  1. **Pausing is refused while the player is dead or `RoomLoader.is_transitioning()`** (boot, fade-out, room swap). The respawn after death is a `load_level`, so death is covered twice. The fade-in (control already returned) is not blocked; the fader tween is pausable and simply waits. Pausing during hit-stop IS allowed: hit-stop only sets `time_scale`, Hitstop's timer is `process_always` + `ignore_time_scale`, so it still restores 1.0 while paused.
  2. **Timers made pausable**: `get_tree().create_timer(t)` defaults to `process_always = true`, so the player's `_wait()` / dash timer, the room transition timer, the chair "Saving..." text, enemy corpse and loot timers would keep running (and expire) while the tree is paused. They now pass `process_always = false` (no change outside of a pause). Hitstop's own timer stays `process_always`.
  3. `GameCamera` is `PROCESS_MODE_ALWAYS` (hit-stop); it now returns early while `paused` and shifts the start of an unscaled shake by the paused time, so a shake neither plays nor expires during a pause.
  4. The menu's initial focus is silent (Unity plays the select sound on the initial selection too); later focus changes play it.
  5. Freeing the world while the menu is open (`PauseMenu._exit_tree`) unpauses the tree.
- Deviations from Unity: menu BGM added afterwards at the user's request: `assets/bgm/mainmenu_theme.mp3` loops on a `Music` AudioStreamPlayer at volume 0.6 (-4.44 dB), as Unity's BGMLoader prefab (the housekeeping note above still applies: replace it before any public release); the font is Godot's default (TMP LiberationSans SDF not ported, as everywhere else); the Unity pause panel is a plain rectangle, here also; Unity pausing during a scene load is possible, here it is refused (see 1); Unity's pause toggles even when the player is dead (it only changes `timeScale`), here refused.
- Tests: new `tools/test_menus.gd` (106 checks, ALL PASS): menu with / without save (focus, dimming, inert Continue, frame, select sound, version), Continue loads room / stats / chair, New Game resets in-memory state and leaves the save files byte-identical, pause (tree paused, lock +1, `time_scale` untouched, player frozen, navigation, Resume, pause key, `ui_cancel`, foreign lock changes preserved), hit-stop overlap, refused during room transition / dead / death-respawn / boot, stun timer frozen while paused, Main Menu (world and player freed, unpaused, `time_scale` 1, RoomLoader references cleared, Continue works again afterwards), `start(NEW_GAME / CONTINUE)` with and without a save, freeing the world while paused or mid-transition. It backs up / restores any real save. `test_world` still passes; its `_boot_world` now takes an explicit mode (NEW_GAME by default, CONTINUE for the boot-with-save test) so it no longer relies on the old auto-continue (without it the default CONTINUE-without-save fallback would only add a warning). Pre-existing, unrelated: `test_save_roundtrip`'s real-time Hitstop overlap check (`hitstop: earlier call must not reset latest`) fails on the previous commit too (verified on a clean checkout of HEAD); Hitstop was not touched. Autoload identifiers and `class_name`s that depend on them cannot be referenced in `-s` test scripts (compile order), so `test_menus` uses `root.get_node` / untyped nodes.
- Playtest: run the project (F5): menu -> New Game; Escape / gamepad Start opens the pause menu (up / down + Enter / A, Escape or B closes); sit on the DirtCave3 chair to save, then Main Menu -> Continue resumes there.

### M1 - 2026-11-25 (game menu: shell, Inventory, Map, Journal; Talisman tab = placeholder, replaced by M2)
- Done:
  - **Data** (`autoload/game_state.gd`, new `resources/inventory_ids.gd` = `InventoryIds`, no autoload dependency): Unity enums `ItemName` / `TalismanName` / `RedToolName` / `BlueToolName` / `YellowToolName` / `EnemyType`, `RED_TOOL_MAX_CHARGE` [10, 5, 2] (RedTool.asset), `NEW_GAME_ITEMS`. New `GameState` fields from `PlayerData`: `inventory_item_amount` (8), `found_talismans` [wanderer], `equipped_talisman`, `red_tools_current_charge` (full), `found_/equipped_red_tools`, `selected_red_tool_id`, `found_/equipped_blue_tools`, `found_/equipped_yellow_tools` (typed `Array[int]` / `Array[float]`), helpers `get_item_amount`, `get_kill_count`, `grant_debug_inventory()` (Unity's editor `debugInventory`: every talisman and tool found; debug-build key **F8** in `world.gd`). `reset_to_new_game()` = `InitNewGameData` (verdantMantle, silkSpool, mask, needle, carapaceBackpack, notebookQuill = 1, the rest 0). Saved in `player.json`. **Old saves**: every missing new key is reset to the new-game value on load (`_apply_inventory_dict` resets first, so stale in-memory inventory never survives), wrong-typed values fall back to empty, short item arrays are padded with 0.
  - **Shell** (`scenes/ui/game_menu/game_menu.tscn/.gd`, `class_name GameMenu`, CanvasLayer **layer 25** instanced in `world.tscn`; above the Fader 10 and the F3 debug overlay 20, below the pause menu 30): `InventoryMenu.cs` port. Full-screen black 0.8627 alpha background, four-tab header (labels "Inventory" / "Tools" / "Map" / "Journal" at the prefab's 380 unit spacing; current tab 50 -> 10 px bold + underline, others 40 -> 8 px), pages built in code from `game_menu_data.gd` (prefab numbers: canvas units / 5; `text_rect_px` applies the TMP `m_margin`, which is negative = outward in most text boxes). Sounds: `Sfx/OpenInventory` (open + every tab switch, as Unity), `CloseInventory`, `Moving` (focus changes in the inventory page; the journal rows use `SelectButton`'s own `menu_button.ogg`, the same clip), `Pressed` (`inventory_equip.ogg`, wired but unused until M2).
  - **Pages**: `InventoryPage` (Mask 300x300, Silk Spool 300x300 and Needle 300x1200 as static slots; grid 5 columns / cell 100 / spacing 40 with Verdant Mantle, Notebook and Quill, Carapace Backpack, Silkbind Sandal, Cool Key in that order when amount > 0, rebuilt on show and destroyed on hide like Unity; Cool Key amount label when > 1; info box name + description; `MenuSlotButton` = icon + `SelectFrame.png` frame only while focused, the Needle frame is `LongSelectFrame` rotated 90 degrees). `MapPage` (DirtCaveArea: all 16 rooms and 16 paths with the prefab positions / sizes / rotations, room colour (0.47, 0.30, 0), white paths, rest-chair icons on DirtCave3 / DirtCave8 and the door-switch icon on DirtCave6; a room shows only when in `visited_rooms`, a path when either of its rooms was visited, icons follow their room; on show: scale reset to 1, content centred on the current room (`RoomLoader.current_room_name`), pulsing `MaskIcon` marker (scale 1 + sin(4 t) / 2); pan with W A S D / right stick at 1000 units/s, zoom with R / F or the triggers at 1 scale/s, scale clamped 0.2..3, `MapPage.step()`). `JournalPage` (rows = `SelectButton`s with the 500x150 `LongSelectFrame` through the new `frame_outset` export, list clipped like the RectMask2D, selected row centred like `JournalButton.OnSelect`, last selected row remembered, "???" + black silhouette + empty texts + "Defeated: 0" when the kill count is 0, otherwise name / description / flavour (italic) / "Defeated: N"; sprite at native size = rect * 100 / PPU 64 on the `GreenGlow` disc). `TalismanPage` = placeholder text on slot index 1 (**M2** replaces it).
  - **Rules**: `open_inventory` (I, gamepad Start) -> Tools tab (index 1), `open_map` (Tab) -> Map tab (2), `menu_tab_left/right` (Q / E, gamepad LB / RB) wrap, `menu_close` (I, Escape, Tab, Start, B) closes. Opening sets `player.in_menu` (already part of the control gate and the rest chair checks) and does NOT pause the tree; closing clears it. Hurt (`player.is_hurt`), death and room transitions / boot close it silently (Unity's `if (player.isHurt) CloseMenu()`; the others are extra) and block opening (`can_open`).
  - **Pause interplay (decided)**: the game menu consumes the `menu_close` event (Escape closes it, the pause menu never sees that Escape); `PauseMenu.can_pause()` is also false while `GameMenu.blocks_pause()` (open, or closed in this very frame); the game menu refuses to open while the tree is paused or the pause menu is open. `World` wires `pause_menu.game_menu` / `game_menu.pause_menu` / `game_menu.player`.
  - **Player**: `swallow_input_edges()` (2 physics ticks): the key that closes the menu may share its binding with a gameplay action (gamepad B = silk skill, Q = silk skill vs tab left), so button edges are ignored right after closing.
  - **Input actions** (project.godot, appended): `open_inventory`, `open_map`, `menu_close`, `menu_tab_left`, `menu_tab_right`, `map_pan_left/right/up/down` (W A S D, right stick), `map_zoom_in` (R, RT), `map_zoom_out` (F, LT). `pause` lost the gamepad Start button (see deviations).
  - Assets copied: `assets/ui/SelectFrame.png`, `GreenGlow.png`, `assets/ui/items/*` (7 item icons + the sandal sheet), `assets/props/DoorSwitch.png`, journal sprites `TwistedDipsa`, `LapisLazer`, `BatterIdle`, `BatterPet`, `GreatCrawlerIdle` in `assets/enemies/`, sounds `open_inventory.mp3`, `close_inventory.wav`, `inventory_equip.ogg`.
- Deviations / findings:
  1. **Keys follow the Unity input file, not the task brief**: Gameplay.Map is **Tab** (keyboard only), `V` is `UseRedTool` (M2) and `E` / LT are `SwapToolRight`; Gameplay.InventoryMenu is I + gamepad Start; Inventory.OutOfMenu is I, Escape, Tab, Start and B (east). V is NOT bound to the map. Tab therefore both opens the map and closes the menu.
  2. **Gamepad Start no longer pauses**: the Menus entry bound Start (button 6) to `pause`; Unity has Start = inventory and Back/Select = pause, so Start moved to `open_inventory` / `menu_close`. Back still pauses.
  3. **Journal has 8 rows, the prefab 6**: `InventoryMenu.prefab` only contains buttons for Crawling, Dipsa, Twisted Dipsa, Crabber, Lapis Lazer, Great Crawler, although `BossBatter.asset` ("Beetle Batter") and `BatterRing.asset` ("Batter's Contraption") exist. Shown in `EnemyType` order (crawling, dipsa, twistedDipsa, crabber, lapisLazer, bossBatter, batterRing, greatCrawler) as requested; `GameMenuData.SHOW_UNLISTED_LORE = false` gives the prefab's 6. Kill-count mapping: the Godot `enemy_type` ints are the `EnemyLore.EnemyType` values (Crawling 0, Dipsa 1, Crabber 3, the same as the Unity prefabs; the Crawling prefab has no explicit value = default 0); the test instantiates the three scenes and checks that a Dipsa kill increments key 1.
  4. Blocked while dead / hurt / transitioning (Unity only blocks via `disableInventoryMenu` during NPC dialogue). Opening while hurt would be undone by the `isHurt` check in the same Unity frame, so it is refused instead.
  5. TMP -> Godot: font sizes rounded to whole px (36 -> 7, 40 -> 8, 50 -> 10, 60 -> 12), Bold = `FontVariation` embolden, Italic = skew, TMP underline = 1 px rect under the tab text, justified text = `HORIZONTAL_ALIGNMENT_FILL`, default font instead of LiberationSans SDF. Text boxes use the TMP margins, so wrapping widths follow the prefab.
  6. Focus navigation: Godot's geometric neighbour search sent Down from the Mask to the (tall, overlapping) Needle slot, so the Mask / Silk Spool / Needle neighbours are set explicitly (Mask above Spool, Needle on the left of both). Unity relied on automatic navigation; not verified there. Mouse hover focuses slots / rows.
  7. The select sound plays on the initial focus too (Unity does), unlike the pause / main menu which stay silent initially.
  8. The Unity `inventoryItemAmount` array is kept 1:1, so the Cool Key and Silkbind Sandal slots exist but nothing grants them (no pickups in DirtCave0-3; set the amount in `GameState` to see them).
  9. The F3 debug overlay (layer 20) is below the menu; because the Unity background is only 0.86 opaque its text shows faintly through (debug builds only).
  10. `--quit-after` runs of the project print "2 ObjectDB instances were leaked at exit / 1 resources still in use", also with all M1 changes stashed (pre-existing, unrelated to the menu). The user's uncommitted SoundManager addon / editor changes in `project.godot`, `world.tscn`, `sunnyland_tileset.tres` were left out of the M1 commit.
- Tests: `tools/test_game_menu.gd` (182 checks, ALL PASS; real world, real key / joypad events): new-game data; open / close with I, Tab, Start, B, Escape; tab order and wrap with Q / E / shoulders and header sizes; Escape closes the game menu without pausing, then pauses; pause refused while it is open and vice versa; hurt closes (silently) and blocks until the stun ends; blocked during a room transition, closed when one starts, blocked while dead and during death / respawn; `in_menu` blocks run / jump / attack while physics keeps running (the player falls and lands with the menu open); B closing the menu does not cast the heal; inventory contents, focus, info box, grid order with extra items, amount label, grid destroyed on hide; map visibility by visited rooms and paths, marker + centring, pan / zoom clamps 0.2..3 with real input, reset on re-entry; journal "???" / silhouette vs discovered, "Defeated: N", scrolling, remembered row; enemy_type mapping; save round trip of every new field; old-format save, partial save and corrupt values fall back to defaults; debug inventory.
- Notes for M2: `TalismanPage` (`scenes/ui/game_menu/talisman_page.gd`) is the placeholder in tab slot 1; replace its body and keep `page_shown` / `page_hidden` / `initial_focus`. `GameMenu.play_pressed()` is the equip sound. All talisman / tool data already saves and loads (`found_*`, `equipped_*`, `selected_red_tool_id`, `red_tools_current_charge`); the rest chair should refill the charges from `InventoryIds.RED_TOOL_MAX_CHARGE` (Unity `RefillRedTool`). Tool keys are not bound yet: Unity `UseRedTool` = V / RB, `SwapToolRight` = E / LT (E is `menu_tab_right` only inside the menu, LT is `map_zoom_out` only in the map, so no conflict). Equipping only while `player.resting`. `player.in_menu` already blocks gameplay input.
- Playtest: F5, New Game, press **I** (Tools placeholder), **Q / E** cycle Inventory / Tools / Map / Journal, **Tab** opens the map (W A S D pan, R / F zoom), arrows move the selection, Esc / I / Tab closes. F8 (debug) grants every talisman / tool (no UI until M2). Kill enemies to fill the journal.

### M2 - 2026-11-25 (Talisman / Tools tab + red tools)
- Done:
  - **Data** (`resources/tool_data.gd` = `ToolData`, no autoload dependency): `RED_TOOLS` / `BLUE_TOOLS` / `YELLOW_TOOLS` from the `.asset` files (name, description, icon; red: maxCharge 10 / 5 / 2, fixCostPerCharge 1 / 1 / 0 - the repair cost is unused, Unity does not use it either), `TALISMANS` slot layouts from TalismanWanderer / TalismanSentinel (Wanderer red (0,152), blue (-146,-85), yellow (146,-85); Sentinel red (0,36), (0,204), blue (-157,-78), (157,-78), no yellow). Toolmaster has no prefab (GameMaster.talismanData has two entries): zero slots, no crest.
  - **`GameState`** (GameMaster.cs): `talisman_changed` signal (OnTalismanChange), `effective_talisman()`, `red/blue/yellow_slot_count()`, `change_to_next_talisman()` (needs >1 found talisman, unequips everything, cycles `found_talismans` with wrap), `unequip_all_tools()`, `swap_tool(right)` (wraps, no-op without equipped tools), `equip_unequip_red/blue/yellow_tool()` (toggle, slot limit from the talisman, selected id falls back to 0 like Unity), `refill_red_tools()`, `get_selected_red_tool()`, `get_red_tool_charge()`, `consume_red_tool_charge()`. Every change also emits `stats_changed` (the HUD is event driven). Equip / charge / selection data was already saved in M1 and still is. `grant_debug_inventory()` (F8) now grants only the talismans that have a prefab (Wanderer, Sentinel), like Unity's `debugInventory` loop over `talismanData`; M1 granted the prefab-less Toolmaster as well (its test expectation was updated).
  - **Talisman page** (`scenes/ui/game_menu/talisman_page.gd`, replaces the M1 placeholder; layout from the TalismanGroup of InventoryMenu.prefab, /5): "Talisman" caption, crest of the equipped talisman (512x512 sprite tinted 0.368 grey, slot sprites 128x128 with the equipped tool icon 100x100 inside, "WANDERER" / "SENTINEL" in 60 -> 12 px), Change Talisman button (LongSelectFrame 512x128 at (+6,+4) shown when focused, ChangeMaskIcon, text), tool list (three divide bars with the Red / Blue / Yellow slot sprite as medallion, groups of 100x100 buttons 140 apart; found = tool sprite, not found = EmptyTool.png; equipped = icon alpha 0.3; `SelectFrame` on focus), info box (name bold 48 -> 10 px, 256x256 image, justified description; empty + image hidden for an unfound tool), vertical bar, red bold-underlined reminder "You can only change tools when resting at a chair" while `player.resting` is false. First focus = Throw Blade. Sounds: `Moving` on every focus, `Pressed` (`inventory_equip.ogg`) on a successful equip / unequip / change (like Unity the Change button plays it even with a single talisman). Equip, unequip and Change Talisman only work while `player.resting` (sat on a chair). Blue / yellow tools equip and show on the crest but have **no gameplay in Unity either** (their descriptions say "Not yet implemented"), so nothing else is done with them.
  - **Red tools** (`scenes/player/red_tool_controller.gd`, node `RedToolController` under the player = RedToolController.cs; `tool_projectile.gd` + `throw_blade_proj.tscn` / `triple_knife_proj.tscn`; `tools/build_tools.gd`): `Player._handle_tool_usage()` = HandleToolUsage inside the normal gameplay gate (`_can_control` now also has `not tool_anim_lock`, Unity's `!toolAnimLock`; so not while resting / in a menu / locked / dashing / paralyzed / parrying / in a silk skill): needs at least one equipped red tool; `swap_tool_right` swaps; `use_red_tool` fires the selected tool when `not in_attack and tool_timer > tool_cooldown (0.35)`, `tool_timer` restarts at the press even when the tool then does nothing (charge 0 / lifeblood). Throw Blade: 1 projectile, 20 u/s = 320 px/s along the facing, damage 3, charge -1. Triple Knife: 3 projectiles (0, +10, -10 deg; facing left the whole vector is negated like Unity), 320 px/s, damage 1 each, one charge. Lifeblood Needle: refused while lifeblood > 0 or charge 0, else charge -1 + the `lifeblood_needle` clip (`tenroh_useLifeBloodNeedle.png`, 4 frames of 256 px, events @0 `begin_tool_anim_lock` (lock, velocity 0, gravity off), @0.25 `lifeblood_needle_effect` (+2 lifeblood, syringe sound, FlashBlue 0.15 s, blue splash particles), @0.5833 `end_tool_anim_lock`). All use the `throw.ogg` sound (random pitch 0.7..1.3 / volume 0.8..1 like every player sound; the needle plays `throw.ogg` at the press and `syringe.ogg` at the effect, as Unity). `damaged()` clears `tool_anim_lock` (Unity) and the clip is stopped like every other one-shot.
  - **Projectiles**: `ToolProjectile extends Projectile` (the P5 class): layer PlayerAttack, mask Ground + Enemy, moves itself with no gravity, dies on its first contact (maxBounce 0: enemy or ground), then gravity 1 / drag 1 / fade 10 per s, 10 s hard lifetime, knife_collide.ogg on contact. Enemy contact = `enemy.damaged(damage, dir.normalized() * 16)` (Unity passes the normalised vector as the impulse = 1 u/s = 16 px/s) through the existing Enemy damage path (i-frames, flash, hit sound, particles, kill count, loot). Collider and sprite from the prefabs: box 1.0466 x 0.4351 u at (0.0233, -0.0045) (x 1.5 for the blade = 25.1 x 10.4 px), sprite ThrowBladeProjectile.png PPU 64 (0.25, blade 0.375). They are added to `RoomLoader.current_room` (Unity: scene root, gone with the scene).
  - **Rest chair** (`rest_chair.gd`): `GameState.refill_red_tools()` in `get_on_chair()` before the save (RestChair.cs:81), so the refill is part of the chair save and of the respawn-on-chair path.
  - **HUD** (`hud.gd`, ToolCircleUI.cs on UI.prefab "ToolCircle"): centre (-691, 249) -> (53.8, 58.2) px, 20x20: black RadialProgressBar BG, radial `TextureProgressBar` fill (origin bottom = 180 deg, clockwise, full circle) = charge / maxCharge, the selected tool's icon on top; hidden without an equipped red tool. Updated from `stats_changed`.
  - **Input** (project.godot, appended): `use_red_tool` = **V** / gamepad RB (right shoulder), `swap_tool_right` = **E** / gamepad LT (left trigger, axis 4), the Unity `UseRedTool` / `SwapToolRight` bindings (`SwapToolLeft` has no binding in Unity, so there is no swap-left control; `GameState.swap_tool(false)` exists). E / RB are `menu_tab_right` inside the menu and LT is `map_zoom_out` inside the map: the menu blocks gameplay, so no conflict.
  - **Assets**: `assets/ui/talisman/*` (slot sprites, EmptyTool, ChangeMaskIcon, both crests), `assets/ui/tools/*` (6 tool icons, RadialProgressBar), `assets/player/ThrowBladeProjectile.png`, `tenroh_useLifeBloodNeedle.png`, `assets/sfx/throw.ogg`, `syringe.ogg`, `knife_collide.ogg`. `flash.gdshader` got a `flash_tint` uniform (default white) for FlashBlue.
- Deviations / findings:
  1. **No scrolling**: the Unity ToolList is a ScrollRect (`ToolButton.ScrollPanel` re-centres the panel on select) but its content (750 high) is smaller than the view (804), so the elastic clamp keeps it top-aligned; the Godot page is a static layout.
  2. **Focus navigation** is Godot's geometric neighbour search (Unity: automatic selectable navigation). Checked by the test: Right / Left walk the row, Down from Throw Blade -> Acid Orb -> Crab Orb, Left from the first column -> Change Talisman. The unfound-tool buttons are focusable but do nothing (Unity: the click listener is only added for found tools).
  3. **Knives / bullets**: Unity's layer matrix lets PlayerAttack collide with EnemyAttack; both projectiles have `projectileHittable` 0, so a knife only bounces off a Dipsa bullet (and bumps its bounce counter). Not ported: tool projectiles pass through enemy bullets. The "deflect enemy projectiles" in the Triple Knife description refers to hittable projectiles (BatterBall, boss, out of scope).
  4. **Needle clip**: the Animator leaves the state through a 0.25 s blend starting at 0.35 s; the Godot clip simply ends at 0.6 s (events at 0 / 0.25 / 0.5833 unchanged). The 256 px frames are drawn centred on the player origin like the heal sheet.
  5. **LifebloodNeedlePE** is approximated from the prefab numbers (burst 10, 1 s, speed 6..18 u/s, size 0.2..0.4 u, cone 45 deg backwards and slightly up, colour (0,0.855,1)..(0,0.29,1), alpha and size fade, gravity 1); the exact curves were not decoded.
  6. **FlashBlue**: Unity swaps the flash material and tints the sprite colour (0, 0.5, 1); here the shared flash shader blends towards `flash_tint` (blue) for 0.15 s. Damage / chair recovery reset it.
  7. **Projectile spawn position** is the player's root, like Unity; the blade / knives start inside the player body and ignore it (mask has no Player layer). Three knives on one enemy in the same tick deal 1 damage because of the enemy's 0.05 s i-frames (same as Unity).
  8. **Input edges**: `Player._was_pressed` = buffered `_input` edge OR `Input.is_action_just_pressed`. An event injected inside the `physics_frame` signal callback is seen by two consecutive ticks (pre-existing; only affects tests that inject there, real events arrive in the process phase). `test_tools.gd` injects after `await process_frame`; actions with a cooldown hid this before, `swap_tool_right` (no cooldown) exposed it.
  9. Unity `ChangeToNextTalisman` does not reset `selectedRedToolId` and does not call `UpdateSlotImage` for the new talisman; the Godot page rebuilds the crest from the data, equivalent because every tool is unequipped. A found talisman without a prefab (Toolmaster, only reachable by editing a save) shows no crest and has no slots instead of throwing (Unity: index out of range).
  10. `--quit-after 300` of the main scene still prints "2 ObjectDB instances were leaked at exit / 1 resources still in use" (pre-existing since M1). The user's uncommitted work (addons/, SoundManager + editor plugin lines and the physics block in project.godot, `sunnyland_tileset.tres`, uid edits in `world.tscn`) was left out of the commit; only the two new input actions of project.godot are in it.
- Tests: new `tools/test_tools.gd` (198 checks, ALL PASS, about 25 s). Part 1 (data): slot counts Wanderer 1/1/1, Sentinel 2/2/0, Toolmaster 0/0/0, equipped-but-not-found falls back to Wanderer; slot limits per colour, toggle, selected id fallback; change talisman unequips all, wraps, emits `talisman_changed`, does nothing with one talisman; swap right / left wrap, no-op when empty, out-of-range selection -> -1; save round trip of talisman / equips / selected id / charges / found tools. Part 2 (flat room, real player + training dummy): Throw Blade 1 projectile, velocity (320, 0) (measured 320.0 px/s over 6 ticks), damage 3, layer 8 / mask 5, charge 10 -> 9, throw sound, left = (-320, 0) with mirrored sprite / collider, enemy hp -3 after 10 ticks from 64 px (dead projectile, one enemy hit, knockback <= 16 px/s, no silk, player unhurt); Triple Knife 3 projectiles at (320, 0) / (315.14, -55.57) / (315.14, +55.57), |v| 320, damage 1, one charge, left = point-reflected fan, 3 knives on one enemy in one tick = -1; charges (last charge, none at 0 for blade / knife, nothing equipped, only the selected tool), cooldown (0.30 s refused, 0.38 s accepted), gate (in_attack, control_lock, is_dashing, in_silk_skill, resting, in_menu, tool_anim_lock, is_paralyzed, is_parrying each block); needle: charge -1 at the press, clip, lock + velocity 0 + gravity off, lifeblood 0 until the event then +2 at 0.267 s (expected 0.25 +-0.05), syringe sound, blue flash tint and its restore, splash spawned, lock released at 0.600 s (0.5833 +-0.05), refused with lifeblood > 0 or charge 0, damage releases the lock; swap key; chair sit refills [10, 5, 2] and the save written by the sit contains it. Part 3 (real world, real key events): F8 grants Wanderer + Sentinel and every tool (idempotent); Tools tab (focus, info box, reminder, crest of 1/1/1 slots, found sprites, frame, navigation, moving sound); not resting: Enter on a tool / Change Talisman does nothing and plays no sound; resting: equip / equip-state alpha 0.3 / crest icon / refused second red tool / blue and yellow equip / unequip / Change Talisman (Sentinel crest 2/2/0, tools cleared, wraps back) / re-open re-reads the data; unfound tools show EmptyTool and an empty info box; V does nothing with the menu open and throws after it closes into the current room; E in the menu changes tab, outside it swaps (wraps); HUD circle hidden without tools, fill 1.0 / 0.7 / 0.4 / 0.5 / 0 / 1.0 after refill, icon follows the swap, start angle 180, a real throw lowers it to 0.9. `test_save_roundtrip`, `test_movement`, `test_combat`, `test_silk`, `check_rooms`, `test_enemies`, `test_world`, `test_menus`, `test_game_menu` (placeholder / debug-inventory expectations updated) all pass; the main scene `--quit-after 300` prints no script errors.
- Visual check: a non-headless script (kept outside the repo) captured the Tools tab not resting (reminder shown), resting with Throw Blade + Acid Orb equipped and Triple Knife focused, the Sentinel crest with two reds / blues, the HUD circle (blade 7 / 10), a blade and knives in flight, and the needle effect (blue flash, splash, two lifeblood masks, half-full circle). Layout matches the prefab; the reminder wraps to three lines over the crest like TMP does at 517 units.
- Playtest: F5, New Game, **F8** (debug grant), walk to the DirtCave3 chair (see P6), sit (Up), press **I**: Tools tab, arrows move, Enter equips / unequips and presses Change Talisman, Q / E switch tabs, Esc / I closes. Stand up (Down), **V** throws / uses the selected tool, **E** swaps it, the circle under the shard counter shows the charge. Sitting again refills the charges and saves.

### UI scenes - 2026-11-26 (HUD and game menu as editor-placed scenes)
- Done: the HUD and the whole game menu layout moved from `.new()` code into real nodes in `.tscn` files (same style as `main_menu.tscn` / `pause_menu.tscn`). Pixel check: non-headless screenshots before / after (HUD with lifeblood + partial silk + shards + tool circle, Inventory, Tools not resting / resting / Sentinel, Map, Journal discovered / unknown) and a rect-by-rect dump of every Control match; only the world behind the menu differs between runs.
- **Scene structure** (edit these in the editor; nothing regenerates them):
  - `scenes/ui/hud.tscn`: `Masks` (HBox), `SilkBar` (LeftCap, Segments, RightCap, atlas sub-resources), `Shards` (Icon, Count), `ToolCircle` (BG, Fill = TextureProgressBar, ToolImage). Masks and silk segments are variable-count and instanced from `scenes/ui/hud/hud_mask.tscn` / `hud_silk_segment.tscn` (their look is in those scenes; `silk_filled.tres` / `silk_empty.tres` are the shared atlas textures).
  - `scenes/ui/game_menu/game_menu.tscn`: `Sfx`, `Holder` (theme `game_menu_theme.tres`) > `Background`, the four pages instanced as `InventoryGroup` / `TalismanGroup` / `MapGroup` / `JournalGroup`, then `MenuTab` (the four tab labels + `Underline`).
  - `scenes/ui/game_menu/pages/`: `inventory_page.tscn` (bars, placed Needle / Mask / SilkSpool slots with their focus neighbours, Name, Desc, empty `InventoryGrid`), `talisman_page.tscn` (caption, `ChangeTalisman` button, `ToolList/RedTools|BlueTools|YellowTools` with divider bar, medal and one placed slot per tool, `ToolInfoBox`, `TalismanHolder`, `Reminder`), `map_page.tscn` (`MapContent/DirtCaveArea` with the 16 paths in `PathGroup` and the 16 rooms with their icons; each path has metadata `rooms` = the two rooms it connects), `journal_page.tscn` (bars, `EnemyList/Panel` with the 8 placed rows, `EnemyImage`, info labels), `map_player_marker.tscn` (instanced on the current room).
  - Small reusable scenes in `scenes/ui/game_menu/`: `menu_slot_button.tscn` (Icon + SelectFrame; `item_id` export), `inventory_key_slot.tscn` (inherits it, adds `Amount`), `journal_row.tscn` (`JournalRow` = `SelectButton` with placed SelectFrame / SelectSound; `enemy_type` export), `talisman_wanderer.tscn` / `talisman_sentinel.tscn` (`TalismanView`: Crest, Red/Blue/YellowSlotN each with an `Image` child, TalismanName; the page shows the view whose `talisman_id` is equipped and hides the other). Shared resources: `game_menu_theme.tres` (white Label colour, empty Button styleboxes), `menu_font_bold.tres`, `menu_font_italic.tres` (FontVariation without base font = the theme default font).
  - Scripts keep behaviour only (data binding via `@onready` node references, visibility, focus, input, signals). Runtime instancing remains only for variable counts: inventory grid slots, HUD masks / silk segments, the map marker. `game_menu_ui.gd` removed; `game_menu_data.gd` now only holds data (items, lore, grid / map numbers); the layout-only constants were deleted. `SelectButton` uses a `SelectFrame` / `SelectSound` child when the scene has one (main / pause menu buttons still get them built).
- How to edit the layout: open the scene in the editor and move / resize the nodes (positions are px on the 384x216 viewport; old Unity canvas units / 5). Pages are instanced `visible = false` in `game_menu.tscn`; to see a page alone, open its scene. A talisman crest is one scene per talisman (add a slot = add a `RedSlotN` TextureRect with an `Image` child; the order of the names is the slot order; `ToolData.TALISMANS` still holds the slot counts used by `GameState`). A new tool = a new `MenuSlotButton` instance in the matching `ToolList` group (order = tool id, `item_id` = kind * 100 + id, plus the entry in `ToolData`).
- Deviations / findings:
  1. The old code-built labels were created at the default 16 px font and so kept a 23 px minimum height; text in boxes shorter than that sat lower. The scene boxes carry the real 23 px height so the text stays where it was.
  2. `GameMenuData.SHOW_UNLISTED_LORE` / `UNLISTED_LORE` (always true) were dropped: the journal places all 8 rows.
  3. The Reminder is a box with a centred `RichTextLabel` (CenterContainer) instead of re-centring the label in code.
  4. The tab underline is still moved by the script (its width follows the bold text of the current tab).
- Tests: all tests unchanged in assertions (see the commit for the run).

## 13. Game menu (inventory / talisman / map / journal) — added 2026-11-25 at the user's request

Scope was out of the original port (§1); the user asked for all four tabs including Talisman. Port faithfully from Unity; log deviations in §12. Two phases: **M1** = menu shell + Inventory + Map + Journal; **M2** = Talisman tab + tools (data, equip, red-tool gameplay, tool HUD).

### 13.1 Unity sources (read these; Unity is read-only)
- Shell: `Assets/Inventory/Other/InventoryMenu.cs` + `InventoryMenu.prefab` (layout, tab headers "MenuTab", SelectFrame/LongSelectFrame, DivideBarRed, sounds `Sfx/Pressed|OpenInventory|Moving|CloseInventory`), `PulsingEffect.cs`.
- Inventory tab: `Assets/Inventory/InventoryTab/*` (`InventoryPage.cs`, `InventoryItem.cs`, `InventoryItemButton.cs`, `InventoryInfoBox.cs`, per-item folders with `.asset` (displayName/description/sprite) and slot `.prefab`), `Other/ItemData.cs`.
- Map tab: `Assets/Inventory/MapTab/*` (`MapPage.cs` pan/zoom + auto-centre on current room, `RoomDisplay.cs` shows only `visitedRooms`, `PathDisplay.cs`, `PlayerMarker.prefab`); room rectangles/paths are laid out inside `InventoryMenu.prefab` under `DirtCaveArea` (rooms named after scenes, e.g. `DirtCave5`, paths named like `4 5`, `2 14`). Port the full DirtCave area layout from the prefab (all rooms; only visited ones show, as Unity).
- Journal tab: `Assets/Inventory/JournalTab/*` (`JournalPage.cs`, `JournalButton.cs` "???" + black silhouette when kill count 0, "Defeated: N", `JournalInfoBox.cs`, `JournalEnemyImage.cs`, `EnemyLore.cs` + 8 `.asset` lore files). Kill counts already exist: `GameState.world.enemy_kill_count` keyed by int enemy_type (§12 P5).
- Talisman tab (M2): `Assets/Inventory/TalismanTab/*` (`TalismanPage.cs`, `Talisman.cs` slot layouts per talisman prefab wanderer/sentinel(/toolmaster has no prefab), `ChangeTalismanButton.cs`, `ToolButton.cs`, `ToolInfoBox.cs`, `RedTool.cs` maxCharge/fixCostPerCharge, `BlueTool.cs`, `YellowTool.cs`, tool `.asset`s and sprites), `Assets/Player/Script/GameMaster.cs` (ChangeToNextTalisman, LoadTalismanFromSave, UnequipAllTools, SwapTool, EquipUnequip*Tool, RefillRedTool, InitNewGameData), `RedToolController.cs` (ThrowBlade 20 u/s, TripleKnife 3 projectiles at 0/±10°, LifebloodNeedle anim trigger, only if lifeblood 0), `ThrowBladeProj.prefab`, `TripleKnifeProj.prefab`, `Player.cs` HandleToolUsage / toolTimer / toolAnimLock / `useLifebloodNeedle` anim, `ToolCircleUI.cs` (HUD radial charge), `RestChair.cs:81` (RefillRedTool on sit), `Inventory/Other/ItemPickup.cs` + `NotifyBox/NotifyCanvas` (pickup + "obtained" popup).
- Input: `InputMaster.inputactions` — Gameplay.InventoryMenu (I / Tab, gamepad per file), Gameplay.Map (V), Inventory.OutOfMenu (I / Escape), LeftTab/RightTab (Q / E), Inventory.Movement2 + Zoom (map pan/zoom), Gameplay.UseRedTool / SwapToolRight (read bindings from the file). Add matching Godot input actions; resolve key conflicts with existing actions (Q is silk_skill in gameplay but LeftTab only inside the menu — fine because the menu blocks gameplay) and log them.

### 13.2 Behaviour rules
- Open with InventoryMenu -> Talisman tab (index 1); with Map -> Map tab (index 2). Tab order follows `inventoryMenuTabs` in the prefab (verify). LeftTab/RightTab wrap. OutOfMenu closes. Getting hurt closes the menu (`player.isHurt`). Blocked when `disableInventoryMenu` (Unity sets it via DisableGameplayControl, e.g. during transitions/death) and while the pause menu is open; the pause menu must not open while the game menu is open (pick a consistent rule, log it).
- Unity does NOT pause time for this menu: it sets `player.inMenu`, which blocks gameplay input (Player.cs line ~160) while physics/enemies continue. Port the same (`in_menu` flag on the player, not tree pause).
- Sounds: open/close/moving/pressed as in the prefab.
- New-game data (GameMaster.InitNewGameData): foundTalismans [wanderer]; red tool charges = maxCharge; inventory items verdantMantle, silkSpool, mask, needle, carapaceBackpack, notebookQuill = 1; others 0. Extend GameState + save/load (keep old saves loading: missing keys -> defaults) and `reset_to_new_game`.
- Unity's editor `debugInventory` flag grants every talisman and tool: port as a debug-build toggle (e.g. a key in world.gd debug keys, logged) since no pickups/shops exist in DirtCave0–3. Equipping tools only works while resting on the chair (`player.resting`), as Unity.
- Red tools (M2): use only when equipped, charge > 0, not in attack, toolTimer > toolCooldown 0.35 s, and under the same gate as other gameplay actions; swap cycles selectedRedToolId. Projectile damage/lifetime from the projectile prefabs (reuse the P5 projectile/Enemy damage path where sensible). Charges refill on sitting at the rest chair. HUD radial charge per ToolCircleUI.
- Layout: Unity canvas 1920x1080 -> 384x216 (/5), same approach as the HUD/menus (§12 Menus entry). Nearest filter. Fonts: Godot default as elsewhere.

### 13.3 Done criteria per phase
- Builders/scenes per project conventions; new test script (`tools/test_game_menu.gd` for M1, `tools/test_tools.gd` for M2), all earlier tests still pass, headless main scene clean, a screenshot of each tab taken by running Godot non-headless with a script that saves `get_viewport().get_texture().get_image()` and checked by eye, local commit with the Opus co-author line, §12 entry.

### Builders removed - 2026-11-26
- Deleted at the user's request: `tools/build_{player,combat,skills,enemies,interactables,tools,rooms}.gd`, `tools/unity_room_converter.py` with `tools/room_data/*.json` and `tools/room_previews/*.png`, and `tools/setup_project_settings.gd` (it rewrote `project.godot`). Nothing in the game or the tests referenced them.
- Why: the generated scenes are committed and loaded directly; re-running `build_skills.gd` would have overwritten the editor-placed `hud.tscn`, `build_rooms.gd` would have overwritten `sunnyland_tileset.tres` and the rooms, and `setup_project_settings.gd` would have overwritten `project.godot`.
- Now: edit scenes in the editor. Porting further Unity rooms (DirtCave4+) means restoring the converter from git history (commit 48f59f4) or building rooms by hand.
