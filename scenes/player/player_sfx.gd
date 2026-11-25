class_name PlayerSfx
extends Node
## Port of PlayerSoundEffect.cs (plan §5.15). Footsteps + one-shot sounds, each played with
## a random volume (linear 0.8..1.0) and pitch (0.7..1.3), exactly like Unity's PlaySoundEffect.

enum Sound { ATTACK, DAMAGED, PARRY, SILKBIND, FOOTSTEP, DASH, JUMP, LANDING, THROWING, SYRINGE }

const SOUND_PATHS: Dictionary = {
	Sound.ATTACK: "res://assets/sfx/player_attack.ogg",
	Sound.DAMAGED: "res://assets/sfx/player_damaged.ogg",
	Sound.PARRY: "res://assets/sfx/parry.ogg",
	Sound.SILKBIND: "res://assets/sfx/silk_bind.ogg",
	Sound.FOOTSTEP: "res://assets/sfx/footstep.mp3",
	Sound.DASH: "res://assets/sfx/dash.ogg",
	Sound.JUMP: "res://assets/sfx/jump.ogg",
	Sound.LANDING: "res://assets/sfx/landing.ogg",
	Sound.THROWING: "res://assets/sfx/throw.ogg",
	Sound.SYRINGE: "res://assets/sfx/syringe.ogg",
}

## Unity: PlayerSoundEffect.randomVolume Random.Range(0.8, 1) (linear).
const VOLUME_MIN: float = 0.8
const VOLUME_MAX: float = 1.0
## Unity: PlayerSoundEffect.randomPitch Random.Range(0.7, 1.3).
const PITCH_MIN: float = 0.7
const PITCH_MAX: float = 1.3

@export var player: Player
## Seconds between footsteps. Unity: footstepFrequency (PlayerStats.footstep_frequency).
@export var footstep_frequency: float = 0.5

var _players: Dictionary = {}
var _footstep_timer: float = 0.0

func _ready() -> void:
	for key: int in SOUND_PATHS:
		var p := AudioStreamPlayer.new()
		p.name = (Sound.keys()[key] as String).capitalize().replace(" ", "")
		p.stream = load(SOUND_PATHS[key] as String) as AudioStream
		add_child(p)
		_players[key] = p
	if player != null and player.stats != null:
		footstep_frequency = player.stats.footstep_frequency

func _process(delta: float) -> void:
	_handle_footstep_sound(delta)

func _handle_footstep_sound(delta: float) -> void:
	_footstep_timer += delta
	if _footstep_timer >= footstep_frequency and player != null \
			and player.is_grounded and player.state == Player.State.RUNNING:
		_footstep_timer = 0.0
		play_sound(Sound.FOOTSTEP)

func play_sound(sound: Sound) -> void:
	var p: AudioStreamPlayer = _players.get(sound) as AudioStreamPlayer
	if p == null:
		return
	p.volume_db = linear_to_db(randf_range(VOLUME_MIN, VOLUME_MAX))
	p.pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
	p.play()
