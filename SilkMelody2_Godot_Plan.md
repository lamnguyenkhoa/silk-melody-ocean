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
- Follows the player with smoothing (Cinemachine damping 1: `position_smoothing_speed ≈ 5`), drag margins ±0.1 (dead zone 0.2), look-ahead 0.5 s (optional: offset toward velocity.x).
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
