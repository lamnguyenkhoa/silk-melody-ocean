class_name OneShotParticles
extends CPUParticles2D
## One-shot burst that frees itself when finished (Unity: ParticleSystem stopAction Destroy).
## The spawner sets `emitting = true` after add_child.

func _ready() -> void:
	one_shot = true
	finished.connect(queue_free)
